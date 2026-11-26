import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/data/api_repository.dart';
import 'package:floodsafe/data/local_information_repository.dart';
import 'package:floodsafe/main.dart';
import 'package:floodsafe/place_search.dart';
import 'package:floodsafe/rainfall_panel.dart';

class PendingWeather implements WeatherRepository {
  final responses = <Completer<RainfallEstimate>>[];
  @override
  Future<RainfallEstimate> rainfall(double latitude, double longitude) {
    final response = Completer<RainfallEstimate>();
    responses.add(response);
    return response.future;
  }
}

class PendingSearch implements PlaceSearchRepository {
  final responses = <Completer<List<FoundPlace>>>[];
  @override
  Future<List<FoundPlace>> searchPlaces(String query) {
    final response = Completer<List<FoundPlace>>();
    responses.add(response);
    return response.future;
  }
}

const found = FoundPlace(
  Place(
    id: 'gps:search:N123',
    name: 'Mathare',
    latitude: -1.2584151,
    longitude: 36.8712653,
  ),
  'Nairobi',
);

void main() {
  testWidgets(
    'Weather drops old-place responses and clears expired values before retry',
    (tester) async {
      final repository = PendingWeather();
      final now = DateTime.now().toUtc();
      RainfallEstimate estimate(double mm, int seconds) => RainfallEstimate(
        rainMm: mm,
        intervalMinutes: 15,
        validAt: now,
        forecastRainMm: 8,
        forecastStart: now,
        forecastEnd: now.add(const Duration(hours: 24)),
        retrievedAt: now,
        validUntil: now.add(Duration(seconds: seconds)),
      );
      Widget screen(Place place) => MaterialApp(
        home: Scaffold(
          body: RainfallPanel(place: place, repository: repository),
        ),
      );
      await tester.pumpWidget(screen(found.place));
      await tester.pumpWidget(
        screen(
          const Place(
            id: 'gps:search:N124',
            name: 'Ngara',
            latitude: -1.28,
            longitude: 36.83,
          ),
        ),
      );
      repository.responses.first.complete(estimate(99, 900));
      await tester.pump();
      expect(find.text('99.0 mm'), findsNothing);
      repository.responses[1].complete(estimate(1.2, 2));
      await tester.pumpAndSettle();
      expect(find.text('1.2 mm'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(repository.responses, hasLength(3));
      expect(find.text('1.2 mm'), findsNothing);
      repository.responses.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Rainfall information could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('0.0 mm'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Place search stays usable at width 320 and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = PendingSearch();
    Place? selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: NairobiPlaceSearch(
              repository: repository,
              onSelected: (place) => selected = place,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Mathare');
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Search'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    repository.responses.single.complete([found]);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Mathare'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Mathare'));
    expect(selected?.id, 'gps:search:N123');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Search waits for submission and discards a superseded response',
    (tester) async {
      final repository = PendingSearch();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NairobiPlaceSearch(
              repository: repository,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Mathare');
      await tester.pump();
      expect(repository.responses, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Ngara');
      await tester.pump();
      repository.responses.first.complete([found]);
      await tester.pumpAndSettle();
      expect(find.text('Mathare'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      repository.responses.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Place search could not load'),
        findsOneWidget,
      );
      expect(find.textContaining('No places found'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A found place selects coordinates and loads rainfall without GPS accuracy',
    (tester) async {
      final now = DateTime.now().toUtc();
      final calls = <http.Request>[];
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient((request) async {
          calls.add(request);
          final Object data = switch (request.url.path) {
            '/v1/places' => [],
            '/v1/places/search' => [
              {
                'id': 'gps:search:N123',
                'name': 'Mathare',
                'description': 'Nairobi',
                'latitude': -1.2584151,
                'longitude': 36.8712653,
                'source': 'OpenStreetMap',
              },
            ],
            '/v1/dashboard' => {
              'place_id': 'gps:search:N123',
              'source': 'No published assessment',
              'is_demo': false,
              'assessment': null,
            },
            '/v1/weather' => {
              'source': 'Open-Meteo',
              'kind': 'weather_estimate',
              'rain_mm': 1.2,
              'interval_minutes': 15,
              'valid_at': now.toIso8601String(),
              'forecast_rain_mm': 12.5,
              'forecast_start': now.toIso8601String(),
              'forecast_end': now
                  .add(const Duration(hours: 24))
                  .toIso8601String(),
              'retrieved_at': now.toIso8601String(),
              'valid_until': now
                  .add(const Duration(minutes: 15))
                  .toIso8601String(),
            },
            _ => throw StateError('Unexpected request'),
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
      await tester.ensureVisible(find.byKey(const Key('location-search')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('location-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Mathare');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ListTile, 'Mathare'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Mathare'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('1.2 mm'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1.2 mm'), findsOneWidget);
      expect(
        find.textContaining('12.5 mm · 24-hour rainfall forecast'),
        findsOneWidget,
      );
      expect(find.textContaining('accurate to about'), findsNothing);
      final weather = calls.singleWhere(
        (request) => request.url.path == '/v1/weather',
      );
      expect(weather.method, 'POST');
      expect(jsonDecode(weather.body)['latitude'], -1.2584151);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'Search rejects out-of-area coordinates even if a provider returns them',
    () async {
      final api = ApiRepository(
        baseUrl: 'http://localhost:8000',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'id': 'gps:search:N1',
                'name': 'Far away',
                'description': 'Outside Nairobi',
                'source': 'OpenStreetMap',
                'latitude': 0,
                'longitude': 36.8,
              },
            ]),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.searchPlaces('Somewhere'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}
