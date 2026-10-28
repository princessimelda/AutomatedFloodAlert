import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';
import 'package:floodsafe/location/location_service.dart';
import 'package:floodsafe/main.dart';

class DeniedLocation implements LocationService {
  @override
  Future<Place> currentPlace() async => throw const LocationFailure(
    'Location permission was not granted. You can still choose a place.',
  );
}

class PendingLocation implements LocationService {
  final result = Completer<Place>();
  @override
  Future<Place> currentPlace() => result.future;
}

class ControlledRepository implements DashboardRepository {
  final responses = <Completer<DashboardData>>[];
  @override
  Future<DashboardData> load(Place place) {
    final response = Completer<DashboardData>();
    responses.add(response);
    return response.future;
  }
}

void main() {
  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    DashboardRepository? repository,
    LocationService? locationService,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      FloodSafeApp(repository: repository, locationService: locationService),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String place) async {
    await tester.ensureVisible(find.byKey(const Key('location-search')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-search')));
    await tester.pumpAndSettle();
    await tapText(tester, place);
  }

  testWidgets('Home offers guidance without login, GPS or an assumed place', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('No place selected'), findsOneWidget);
    expect(find.text('Choose a place to begin'), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const Key('risk-status'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('read-guidance'))).dy),
      reason: 'The situation must be visible above the persistent action.',
    );
    expect(
      find.byKey(const Key('read-guidance')).hitTestable(),
      findsOneWidget,
    );
    expect(find.text('Sample high risk'), findsNothing);
    await tapText(tester, 'Read preparedness steps');
    expect(find.text('1. Avoid floodwater'), findsOneWidget);
    expect(find.text('Preparedness steps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Manual selection changes risk and preserves missing/stale distinctions',
    (tester) async {
      await start(tester);
      await choose(tester, 'Kibera');
      expect(find.text('Sample high risk'), findsOneWidget);
      expect(find.text('TEST DATA · Not live conditions'), findsOneWidget);
      await choose(tester, 'Westlands');
      expect(find.text('Risk information unavailable'), findsOneWidget);
      expect(find.text('Sample high risk'), findsNothing);
      await choose(tester, 'Embakasi');
      expect(find.text('Information out of date'), findsOneWidget);
      expect(find.text('Sample high risk'), findsNothing);
      await choose(tester, 'Kasarani');
      expect(find.text('Sample low risk'), findsOneWidget);
    },
  );

  testWidgets('Denied GPS leaves manual selection and guidance available', (
    tester,
  ) async {
    await start(tester, locationService: DeniedLocation());
    await tapText(tester, 'Use my location');
    expect(find.textContaining('permission was not granted'), findsOneWidget);
    await choose(tester, 'Westlands');
    expect(find.text('Westlands'), findsOneWidget);
    expect(find.textContaining('permission was not granted'), findsNothing);
    await tapText(tester, 'Read preparedness steps');
    expect(find.text('1. Avoid floodwater'), findsOneWidget);
  });

  testWidgets('Late GPS result cannot replace a manually selected place', (
    tester,
  ) async {
    final location = PendingLocation();
    await start(tester, locationService: location);
    await tapText(tester, 'Use my location');
    await choose(tester, 'Kasarani');
    location.result.complete(
      const Place(id: 'gps:test', name: 'Your current location'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kasarani'), findsOneWidget);
    expect(find.text('Your current location'), findsNothing);
  });

  testWidgets('A real coordinate does not inherit a sample area assessment', (
    tester,
  ) async {
    final location = PendingLocation();
    await start(tester, locationService: location);
    await choose(tester, 'Kibera');
    await tapText(tester, 'Use my location');
    location.result.complete(
      Place(
        id: 'gps:test',
        name: 'Your current location',
        latitude: -1.29,
        longitude: 36.82,
        recordedAt: DateTime.now().toUtc(),
        accuracyMeters: 20,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your current location'), findsOneWidget);
    expect(find.text('Risk information unavailable'), findsOneWidget);
    expect(find.text('Sample high risk'), findsNothing);
    expect(find.textContaining('Accuracy about 20 m'), findsOneWidget);
  });

  testWidgets(
    'Loading and failure never display the previous risk; retry works',
    (tester) async {
      final repository = ControlledRepository();
      await start(tester, repository: repository);
      await choose(tester, 'Kibera');
      expect(find.text('Checking selected place…'), findsOneWidget);
      repository.responses.first.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load this place'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(repository.responses, hasLength(2));
      repository.responses.last.complete(
        const DashboardData(placeId: 'kibera', source: 'Test', isDemo: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Risk information unavailable'), findsOneWidget);
    },
  );

  testWidgets(
    'Search supports empty results and cancellation without changing place',
    (tester) async {
      await start(tester);
      await choose(tester, 'Kibera');
      await tester.tap(find.byKey(const Key('location-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not a place');
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching sample places'), findsOneWidget);
      await tapText(tester, 'Cancel');
      expect(find.text('Kibera'), findsOneWidget);
    },
  );

  testWidgets('Help remains reachable and sample news is hidden', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('Flood News'), findsNothing);
    await tapText(tester, 'Help');
    expect(find.text('FloodSafe guide'), findsOneWidget);
    await tapText(tester, 'Home');
    expect(find.text('No place selected'), findsOneWidget);
  });

  testWidgets('Unconfigured accounts preserve guest access', (tester) async {
    await start(tester);
    await tester.tap(find.byTooltip('Your profile and sign-in options'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Account services are not configured'),
      findsOneWidget,
    );
    await tapText(tester, 'Back to Home');
    expect(find.text('No place selected'), findsOneWidget);
  });

  for (final size in [const Size(320, 640), const Size(1000, 600)]) {
    testWidgets('Core flow supports enlarged text at $size', (tester) async {
      await start(tester, size: size, scale: 2);
      await choose(tester, 'Kibera');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Read preparedness steps');
      await tester.scrollUntilVisible(
        find.text('1. Avoid floodwater'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('1. Avoid floodwater'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home controls pass Android touch-target and label checks', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await start(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
