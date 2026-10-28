import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/data/api_repository.dart';

void main() {
  Map<String, dynamic> dashboard() => {
    'place_id': 'kibera',
    'source': 'Published test data',
    'is_demo': true,
    'assessment': {
      'level': 'high',
      'issued_at': '2026-10-28T09:00:00Z',
      'valid_until': '2026-10-28T10:00:00Z',
    },
  };

  test(
    'Parses dashboard and place provenance without assuming live data',
    () async {
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          if (request.url.path == '/v1/places') {
            return http.Response(
              jsonEncode([
                {'id': 'kibera', 'name': 'Kibera', 'is_demo': true},
              ]),
              200,
            );
          }
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'place_id': 'kibera'});
          return http.Response(jsonEncode(dashboard()), 200);
        }),
      );
      addTearDown(api.close);
      expect((await api.listPlaces()).single.isDemo, isTrue);
      final data = await api.load(samplePlaces.first);
      expect(data.placeId, 'kibera');
      expect(data.isDemo, isTrue);
      expect(data.assessment!.level, RiskLevel.high);
    },
  );

  test(
    'GPS coordinates are only sent in dashboard POST body, never advisory URL',
    () async {
      final requests = <http.Request>[];
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'place_id': 'gps:-1.29:36.82',
                'source': 'No assessment',
                'is_demo': false,
                'assessment': null,
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      );
      addTearDown(api.close);
      const place = Place(
        id: 'gps:-1.29:36.82',
        name: 'Current location',
        latitude: -1.29,
        longitude: 36.82,
      );
      expect((await api.load(place)).assessment, isNull);
      await api.loadAdvisories(place: place);
      expect(jsonDecode(requests.first.body)['latitude'], -1.29);
      expect(requests.last.url.queryParameters, {'language': 'en'});
      expect(requests.last.url.toString(), isNot(contains('36.82')));
    },
  );

  test(
    'Missing provenance, unknown severity and invalid dates are rejected',
    () async {
      final cases = [
        {...dashboard()}..remove('is_demo'),
        {
          ...dashboard(),
          'assessment': {
            'level': 'unknown',
            'issued_at': '2026-10-28T09:00:00Z',
            'valid_until': '2026-10-28T10:00:00Z',
          },
        },
        {
          ...dashboard(),
          'assessment': {
            'level': 'low',
            'issued_at': '2026-10-28T09:00:00',
            'valid_until': '2026-10-28T10:00:00Z',
          },
        },
        {
          ...dashboard(),
          'assessment': {
            'level': 'low',
            'issued_at': '2026-10-28T09:00:00Z',
            'valid_until': '2026-10-28T08:00:00Z',
          },
        },
      ];
      for (final data in cases) {
        final api = ApiRepository(
          baseUrl: 'http://localhost:8000',
          client: MockClient((_) async => http.Response(jsonEncode(data), 200)),
        );
        await expectLater(
          api.load(samplePlaces.first),
          throwsA(isA<ApiFailure>()),
        );
        api.close();
      }
    },
  );

  test(
    'HTTP errors and malformed JSON never fall back to sample assessments',
    () async {
      for (final response in [
        http.Response('unavailable', 503),
        http.Response('not JSON', 200),
        http.Response('[]', 200),
      ]) {
        final api = ApiRepository(
          baseUrl: 'http://localhost:8000',
          client: MockClient((_) async => response),
        );
        await expectLater(
          api.load(samplePlaces.first),
          throwsA(isA<ApiFailure>()),
        );
        api.close();
      }
    },
  );

  test('Rejects remote plain HTTP and URLs containing credentials', () {
    for (final url in [
      'http://remote.example',
      'https://user:password@example.com',
      'https://example.com?secret=x',
    ]) {
      expect(() => ApiRepository(baseUrl: url), throwsArgumentError);
    }
  });

  testWidgets('A timed-out API request fails without waiting indefinitely', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final api = ApiRepository(
      baseUrl: 'http://localhost:8000',
      client: MockClient((_) => response.future),
    );
    addTearDown(api.close);
    final expectation = expectLater(
      api.load(samplePlaces.first),
      throwsA(isA<ApiFailure>()),
    );
    await tester.pump(const Duration(seconds: 11));
    await expectation;
    response.complete(http.Response(jsonEncode(dashboard()), 200));
    await tester.pump();
  });
}
