import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dashboard/dashboard_data.dart';
import 'content_repository.dart';
import '../assistant/assistant_repository.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
}

class ApiRepository
    implements DashboardRepository, ContentRepository, AssistantRepository {
  ApiRepository({required String baseUrl, http.Client? client})
    : _baseUrl = Uri.parse(baseUrl),
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
      assessment: assessment,
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
