import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/account/account_repository.dart';
import 'package:floodsafe/data/content_repository.dart';
import 'package:floodsafe/location/location_service.dart';
import 'package:floodsafe/maps/map_locations.dart';
import 'package:floodsafe/maps/map_screen.dart';
import 'package:floodsafe/maps/route_repository.dart';
import 'package:latlong2/latlong.dart';

class PendingRoutes implements RouteRepository {
  final result = Completer<WalkingRoute>();
  @override
  Future<WalkingRoute> findRoute({
    required LatLng origin,
    LatLng? destination,
    required bool avoidSteps,
    required List<LatLng> blocked,
  }) => result.future;
}

class OfflineTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
        ),
      );
}

class MapAccount implements AccountRepository {
  @override
  String get userId => 'test-owner';
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<SavedPlace>> savedPlaces() async => [
    SavedPlace('saved', samplePlaces.first, true),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestLocation implements LocationService {
  TestLocation({this.denied = false});
  final bool denied;
  @override
  Future<Place> currentPlace() async {
    if (denied) {
      throw const LocationFailure('Permission denied. Choose a place.');
    }
    return Place(
      id: 'gps:test',
      name: 'Your current location',
      latitude: -1.28,
      longitude: 36.81,
      accuracyMeters: 20,
      recordedAt: DateTime.utc(2026, 10, 28),
    );
  }
}

Future<void> reveal(
  WidgetTester tester,
  Finder finder, {
  double step = 180,
}) async {
  for (var i = 0; i < 80 && finder.evaluate().isEmpty; i++) {
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(
      (position.pixels + step).clamp(0, position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Changing start discards a late route response', (tester) async {
    final routes = PendingRoutes();
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          selected: samplePlaces.first,
          routes: routes,
          content: const FixtureContentRepository(),
          locationService: TestLocation(),
          tileProvider: OfflineTiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.text('Find nearest mapped assembly point');
    await reveal(tester, search);
    await tester.tap(search);
    await tester.pump();
    // Change the start while the first search is still in flight.
    await tester.ensureVisible(find.text('Choose start on map'));
    await tester.pump();
    await tester.tap(find.text('Choose start on map'));
    await tester.pump();
    routes.result.complete(
      WalkingRoute(
        status: 'found',
        message: 'Old route must be discarded',
        points: const [LatLng(-1.3, 36.8), LatLng(-1.301, 36.8)],
        validUntil: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Old route must be discarded'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('Known centres and GPS points remain distinct', () {
    expect(mapPosition(samplePlaces.first), neighbourhoodCentres['kibera']);
    expect(mapPosition(const Place(id: 'unknown', name: 'Unknown')), isNull);
    expect(
      mapPosition(
        const Place(
          id: 'gps:test',
          name: 'GPS',
          latitude: double.nan,
          longitude: 0,
        ),
      ),
      isNull,
    );
  });
  Future<void> start(WidgetTester tester, {bool denied = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          content: const FixtureContentRepository(),
          locationService: TestLocation(denied: denied),
          tileProvider: OfflineTiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Saved places receive selectable bookmark markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          content: const FixtureContentRepository(),
          locationService: TestLocation(),
          account: MapAccount(),
          tileProvider: OfflineTiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kibera, saved place'), findsOneWidget);
    await tester.tap(find.byTooltip('Kibera, saved place'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('View information on Home'));
    expect(find.text('Approximate neighbourhood centre'), findsOneWidget);
  });
  testWidgets('Map controls fit enlarged text on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester);
    await reveal(tester, find.text('Kibera'));
    await tester.tap(find.text('Kibera'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Map selection has an accessible list and labelled attribution', (
    tester,
  ) async {
    await start(tester);
    await reveal(tester, find.text('Kibera'));
    await tester.tap(find.text('Kibera'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('View information on Home'), step: -150);
    expect(find.text('Approximate neighbourhood centre'), findsOneWidget);
    expect(find.text('No current flood update for this area.'), findsOneWidget);
    expect(find.textContaining('TEST SCENARIO'), findsNothing);
    expect(find.textContaining('Sample assessment'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('GPS position includes accuracy and creates a circle', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.byType(CircleLayer), findsOneWidget);
    await reveal(tester, find.textContaining('Device location'));
    expect(find.textContaining('accuracy ±20 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Permission denial retains manual selection', (tester) async {
    await start(tester, denied: true);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('Permission denied. Choose a place.'), findsOneWidget);
    await reveal(tester, find.text('Kibera'));
    expect(find.text('Kibera'), findsOneWidget);
  });
}
