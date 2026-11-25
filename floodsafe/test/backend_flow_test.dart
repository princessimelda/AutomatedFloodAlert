import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:floodsafe/data/api_repository.dart';
import 'package:floodsafe/main.dart';

void main() {
  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Backend place selection loads assessment and published advisory',
    (tester) async {
      final now = DateTime.now().toUtc();
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          final data = switch (request.url.path) {
            '/v1/places' => [
              {'id': 'mathare', 'name': 'Mathare', 'is_demo': true},
            ],
            '/v1/dashboard' => {
              'place_id': 'mathare',
              'source': 'Reviewed local update',
              'is_demo': false,
              'assessment': {
                'level': 'moderate',
                'issued_at': now
                    .subtract(const Duration(hours: 1))
                    .toIso8601String(),
                'valid_until': now
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              },
            },
            '/v1/advisories' => [
              {
                'id': 'practice',
                'place_id': 'mathare',
                'language': 'en',
                'title': 'Household practice advisory',
                'body': 'This is a test advisory.',
                'source': 'Test source',
                'source_url': 'https://example.com/guidance',
                'is_demo': true,
                'published_at': now
                    .subtract(const Duration(hours: 1))
                    .toIso8601String(),
                'valid_until': now
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              },
            ],
            _ => throw StateError('Unexpected endpoint'),
          };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        FloodSafeApp(
          repository: api,
          contentRepository: api,
          connectedToApi: true,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Choose a place');
      expect(find.text('Kibera'), findsNothing);
      await tap(tester, 'Mathare');
      expect(find.text('moderate risk'), findsOneWidget);
      expect(find.textContaining('Development API'), findsNothing);
      expect(find.textContaining('sent to the API'), findsNothing);
      await tap(tester, 'Read preparedness steps');
      await tester.scrollUntilVisible(
        find.text('Household practice advisory'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Household practice advisory'), findsOneWidget);
      expect(
        find.text('TEST ADVISORY · Not an evacuation instruction'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Connected Home excludes sample risk and internal status wording',
    (tester) async {
      final now = DateTime.now().toUtc();
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          final data = request.url.path == '/v1/places'
              ? [
                  {'id': 'mathare', 'name': 'Mathare', 'is_demo': true},
                ]
              : {
                  'place_id': 'mathare',
                  'source': 'FloodSafe database; seeded scenario',
                  'is_demo': true,
                  'assessment': {
                    'level': 'high',
                    'issued_at': now
                        .subtract(const Duration(hours: 1))
                        .toIso8601String(),
                    'valid_until': now
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                  },
                };
          return http.Response(jsonEncode(data), 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        FloodSafeApp(
          repository: api,
          contentRepository: api,
          connectedToApi: true,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Choose a place');
      await tap(tester, 'Mathare');
      expect(find.text('Risk information unavailable'), findsOneWidget);
      expect(find.text('Sample high risk'), findsNothing);
      expect(find.textContaining('TEST DATA'), findsNothing);
      expect(find.textContaining('FloodSafe database'), findsNothing);
      expect(find.textContaining('Development API'), findsNothing);
      expect(find.textContaining('sent to the API'), findsNothing);
      expect(find.textContaining('not saved or tracked'), findsOneWidget);
    },
  );

  testWidgets(
    'Failed place API offers retry and never substitutes built-in samples',
    (tester) async {
      var calls = 0;
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('unavailable', 503)
              : http.Response('[]', 200);
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        FloodSafeApp(
          repository: api,
          contentRepository: api,
          connectedToApi: true,
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'Choose a place');
      expect(find.textContaining('Could not load places'), findsOneWidget);
      expect(find.text('Kibera'), findsNothing);
      await tap(tester, 'Retry places');
      expect(find.text('No matching places are available.'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(
        find.byKey(const Key('read-guidance')).hitTestable(),
        findsOneWidget,
      );
    },
  );
}
