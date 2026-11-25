import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dashboard/dashboard_data.dart';
import 'content_repository.dart';
import '../assistant/assistant_repository.dart';
import '../alerts/alert_repository.dart';
import '../maps/route_repository.dart';

import 'package:latlong2/latlong.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
}

class ApiRepository
    implements
        DashboardRepository,
        ContentRepository,
        AssistantRepository,
        AlertRepository,
        RouteRepository {
  ApiRepository({
    required String baseUrl,
    http.Client? client,
    this.accessToken,
  }) : _baseUrl = Uri.parse(baseUrl),
       _client = client ?? http.Client() {
    if (!_baseUrl.hasAuthority ||
        _baseUrl.userInfo.isNotEmpty ||
        _baseUrl.hasQuery ||
        _baseUrl.hasFragment ||
        !(_baseUrl.scheme == 'https' ||
            (_baseUrl.scheme == 'http' &&
                const [
                  'localhost',
                  '127.0.0.1',
                  '::1',
                  '10.0.2.2',
                ].contains(_baseUrl.host)))) {
      throw ArgumentError(
        'Use an HTTPS API URL, or HTTP on localhost for development.',
      );
    }
  }
  final Uri _baseUrl;
  final http.Client _client;
  final String? Function()? accessToken;

  @override
  Future<WalkingRoute> findRoute({
    required LatLng origin,
    LatLng? destination,
    required bool avoidSteps,
    required List<LatLng> blocked,
  }) async {
    Map<String, double> point(LatLng p) => {
      'latitude': p.latitude,
      'longitude': p.longitude,
    };
    final response = await _client
        .post(
          _url('/v1/routes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'origin': point(origin),
            if (destination != null) 'destination': point(destination),
            'avoid_steps': avoidSteps,
            'blocked_points': blocked.map(point).toList(),
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw const ApiFailure(
        'Route search is unavailable. Try again shortly or contact Emergency Help.',
      );
    }
    final data = _object(jsonDecode(response.body));
    final status = _string(data, 'status');
    final until = _date(data, 'valid_until');
    final generated = _date(data, 'generated_at');
    final points = _list(data['geometry']).map((item) {
      final p = _object(item);
      final lat = p['latitude'], lon = p['longitude'];
      if (lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat < -1.50 ||
          lat > -1.10 ||
          lon < 36.60 ||
          lon > 37.12) {
        throw const ApiFailure('Route information is invalid.');
      }
      return LatLng(lat.toDouble(), lon.toDouble());
    }).toList();
    if (!const [
          'found',
          'no_route',
          'no_assembly_point',
          'unmapped_start',
        ].contains(status) ||
        data['flood_safety'] != 'unverified' ||
        !until.isAfter(DateTime.now().toUtc()) ||
        !until.isAfter(generated) ||
        until.difference(generated) > const Duration(minutes: 10) ||
        generated.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        ) ||
        (status == 'found' && points.length < 2)) {
      throw const ApiFailure(
        'Route information is unavailable or out of date.',
      );
    }
    int? count(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is! int || value < 0) {
        throw const ApiFailure('Route information is invalid.');
      }
      return value;
    }

    return WalkingRoute(
      status: status,
      message: _string(data, 'message'),
      points: points,
      validUntil: until,
      destinationName: data['destination_name'] as String?,
      distanceM: count('distance_m'),
      minutes: count('walking_minutes'),
      startGap: count('start_gap_m'),
      endGap: count('destination_gap_m'),
      roads: _list(data['roads']).map((r) => r as String).toList(),
    );
  }

  @override
  Future<List<PublicAlert>> alerts({String? placeId}) async {
    final result = await _decode(
      _client.get(
        _url('/api/v1/alerts', {
          if (placeId != null && !placeId.startsWith('gps:'))
            'place_id': placeId,
        }),
      ),
    );
    final ids = <String>{};
    return _list(result).map((item) {
      final json = _object(item);
      final id = _string(json, 'id');
      final issued = _date(json, 'issued_at');
      final until = _date(json, 'valid_until');
      final severity = _string(json, 'severity');
      final locations = _list(json['locations'])
          .map((l) => _string(_object(l), 'name'))
          .toList();
      if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ||
          !ids.add(id) ||
          !_bool(json, 'is_demo') ||
          !until.isAfter(issued) ||
          until.difference(issued) > const Duration(days: 1) ||
          !const [
            'information',
            'advisory',
            'warning',
            'critical',
          ].contains(severity) ||
          locations.isEmpty) {
        throw const ApiFailure('Invalid published test alert.');
      }
      return PublicAlert(
        id: id,
        title: _string(json, 'title'),
        message: _string(json, 'message'),
        action: _string(json, 'recommended_action'),
        severity: severity,
        locations: locations,
        issuedAt: issued,
        validUntil: until,
      );
    }).toList();
  }

  @override
  Future<void> acknowledge(String id) async {
    final token = accessToken?.call();
    if (token == null ||
        token.isEmpty ||
        !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) {
      throw const ApiFailure('Sign in to acknowledge.');
    }
    await _decode(
      _client.post(
        _url('/api/v1/alerts/$id/acknowledge'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
  }

  Uri _url(String path, [Map<String, String>? query]) => _baseUrl.replace(
    path: '${_baseUrl.path.replaceFirst(RegExp(r'/$'), '')}$path',
    queryParameters: query,
  );

  Future<Object?> _decode(Future<http.Response> response) async {
    try {
      final result = await response.timeout(const Duration(seconds: 10));
      if (result.statusCode != 200) {
        throw const ApiFailure(
          'Could not load information from the server. Try again.',
        );
      }
      return jsonDecode(utf8.decode(result.bodyBytes));
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'The server is unavailable or returned invalid information. Try again.',
      );
    }
  }

  @override
  Future<List<Place>> listPlaces() async {
    final data = await _decode(_client.get(_url('/v1/places')));
    return _list(data).map((item) {
      final json = _object(item);
      return Place(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        isDemo: _bool(json, 'is_demo'),
      );
    }).toList();
  }

  @override
  Future<DashboardData> load(Place place) async {
    final json = _object(
      await _decode(
        _client.post(
          _url('/v1/dashboard'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'place_id': place.id,
            if (place.latitude != null) 'latitude': place.latitude,
            if (place.longitude != null) 'longitude': place.longitude,
          }),
        ),
      ),
    );
    RiskAssessment? assessment;
    if (json['assessment'] != null) {
      final risk = _object(json['assessment']);
      final level = switch (_string(risk, 'level')) {
        'low' => RiskLevel.low,
        'moderate' => RiskLevel.moderate,
        'high' => RiskLevel.high,
        _ => throw const ApiFailure('Unknown assessment level.'),
      };
      final issued = _date(risk, 'issued_at');
      final until = _date(risk, 'valid_until');
      if (!until.isAfter(issued)) {
        throw const ApiFailure('Invalid assessment validity.');
      }
      assessment = RiskAssessment(
        level: level,
        issuedAt: issued,
        validUntil: until,
      );
    }
    return DashboardData(
      placeId: _string(json, 'place_id'),
      source: _string(json, 'source'),
      isDemo: _bool(json, 'is_demo'),
      // Seeded scenarios must not become public statements about local risk.
      // Preserve provenance in the contract, but show an unavailable state
      // until a real published assessment exists.
      assessment: _bool(json, 'is_demo') ? null : assessment,
    );
  }

  @override
  Future<List<Advisory>> loadAdvisories({Place? place}) async {
    // GPS identifiers can contain coordinates. Never put those into a URL.
    final query = {
      'language': 'en',
      if (place != null && !place.id.startsWith('gps:')) 'place_id': place.id,
    };
    final data = await _decode(_client.get(_url('/v1/advisories', query)));
    return _list(data).map((item) {
      final json = _object(item);
      final published = _date(json, 'published_at');
      final until = _date(json, 'valid_until');
      final source = _string(json, 'source_url');
      if (!until.isAfter(published) ||
          Uri.tryParse(source)?.scheme != 'https') {
        throw const ApiFailure('Invalid advisory metadata.');
      }
      return Advisory(
        id: _string(json, 'id'),
        title: _string(json, 'title'),
        body: _string(json, 'body'),
        source: _string(json, 'source'),
        sourceUrl: source,
        publishedAt: published,
        validUntil: until,
        isDemo: _bool(json, 'is_demo'),
      );
    }).toList();
  }

  @override
  Future<List<AssistantQuestion>> questions() async {
    final result = await _decode(
      _client.get(_url('/v1/assistant/questions', {'language': 'en'})),
    );
    return _list(result).map((item) {
      final json = _object(item);
      return AssistantQuestion(
        id: _string(json, 'id'),
        language: _string(json, 'language'),
        category: _string(json, 'category'),
        question: _string(json, 'question'),
      );
    }).toList();
  }

  @override
  Future<AssistantAnswer> answer(AssistantQuestion question) async {
    final json = _object(
      await _decode(
        _client.get(
          _url('/v1/assistant/questions/${Uri.encodeComponent(question.id)}', {
            'language': question.language,
          }),
        ),
      ),
    );
    final reviewed = _date(json, 'reviewed_at');
    final until = _date(json, 'valid_until');
    final sourceUrl = _string(json, 'source_url');
    final source = Uri.tryParse(sourceUrl);
    if (_string(json, 'id') != question.id ||
        _string(json, 'language') != question.language ||
        !until.isAfter(reviewed) ||
        source?.scheme != 'https' ||
        source!.host.isEmpty) {
      throw const ApiFailure('Invalid published answer.');
    }
    return AssistantAnswer(
      id: question.id,
      language: question.language,
      question: _string(json, 'question'),
      answer: _string(json, 'answer'),
      source: _string(json, 'source'),
      sourceUrl: sourceUrl,
      reviewedAt: reviewed,
      validUntil: until,
    );
  }

  void close() => _client.close();
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const ApiFailure('Invalid response object.');
  }
  return value;
}

List<dynamic> _list(Object? value) {
  if (value is! List || value.length > 1000) {
    throw const ApiFailure('Invalid response list.');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const ApiFailure('Missing response text.');
  }
  return value;
}

bool _bool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw const ApiFailure('Missing data provenance.');
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const ApiFailure('Timestamp needs a timezone.');
  }
  final result = DateTime.tryParse(value);
  if (result == null) throw const ApiFailure('Invalid timestamp.');
  return result.toUtc();
}
