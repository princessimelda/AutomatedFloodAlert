import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/dashboard/dashboard_controller.dart';
import 'package:floodsafe/dashboard/dashboard_data.dart';

class CallbackRepository implements DashboardRepository {
  CallbackRepository(this.callback);
  final Future<DashboardData> Function(Place) callback;
  @override
  Future<DashboardData> load(Place place) => callback(place);
}

void main() {
  final now = DateTime.utc(2026, 10, 28, 9);
  DashboardData assessment(String id, {DateTime? expires, DateTime? issued}) =>
      DashboardData(
        placeId: id,
        source: 'Test fixture',
        isDemo: true,
        assessment: RiskAssessment(
          level: RiskLevel.high,
          issuedAt: issued ?? now.subtract(const Duration(hours: 1)),
          validUntil: expires ?? now.add(const Duration(hours: 1)),
        ),
      );

  test(
    'No implicit location; unavailable and expired data are not low risk',
    () async {
      final controller = DashboardController(
        repository: FixtureDashboardRepository(clock: () => now),
        clock: () => now,
      );
      addTearDown(controller.dispose);
      expect(controller.status, DashboardStatus.choosePlace);
      await controller.selectPlace(samplePlaces[1]);
      expect(controller.status, DashboardStatus.unavailable);
      expect(controller.data!.assessment, isNull);
      await controller.selectPlace(samplePlaces[2]);
      expect(controller.status, DashboardStatus.stale);
    },
  );

  test(
    'Future-dated and exactly expired assessments are not current',
    () async {
      for (final data in [
        assessment('kibera', expires: now),
        assessment('kibera', issued: now.add(const Duration(minutes: 1))),
      ]) {
        final controller = DashboardController(
          repository: CallbackRepository((_) async => data),
          clock: () => now,
        );
        await controller.selectPlace(samplePlaces.first);
        expect(controller.status, DashboardStatus.stale);
        controller.dispose();
      }
    },
  );

  test('Old requests cannot replace newer place data', () async {
    final first = Completer<DashboardData>();
    final second = Completer<DashboardData>();
    final controller = DashboardController(
      repository: CallbackRepository(
        (place) => place.id == 'kibera' ? first.future : second.future,
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    final oldLoad = controller.selectPlace(samplePlaces.first);
    final newLoad = controller.selectPlace(samplePlaces.last);
    second.complete(assessment('kasarani'));
    await newLoad;
    first.complete(assessment('kibera'));
    await oldLoad;
    expect(controller.place!.id, 'kasarani');
    expect(controller.data!.placeId, 'kasarani');
  });

  test('A failed request clears prior risk and can be retried', () async {
    var fail = false;
    final controller = DashboardController(
      repository: CallbackRepository((place) async {
        if (fail) throw Exception('offline');
        return assessment(place.id);
      }),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await controller.selectPlace(samplePlaces.first);
    expect(controller.status, DashboardStatus.ready);
    fail = true;
    final request = controller.selectPlace(samplePlaces.last);
    expect(controller.data, isNull);
    expect(controller.status, DashboardStatus.loading);
    await request;
    expect(controller.status, DashboardStatus.error);
    fail = false;
    await controller.refresh();
    expect(controller.status, DashboardStatus.ready);
    expect(controller.data!.placeId, 'kasarani');
  });

  test('Mismatched response cannot display another area’s risk', () async {
    final controller = DashboardController(
      repository: CallbackRepository((_) async => assessment('wrong-place')),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    await controller.selectPlace(samplePlaces.first);
    expect(controller.status, DashboardStatus.error);
    expect(controller.data, isNull);
  });

  test(
    'Fetching a fixture again does not extend assessment validity',
    () async {
      var clock = now;
      final repository = FixtureDashboardRepository(clock: () => clock);
      final original = await repository.load(samplePlaces.first);
      clock = clock.add(const Duration(hours: 2));
      final refreshed = await repository.load(samplePlaces.first);
      expect(refreshed.assessment!.validUntil, original.assessment!.validUntil);
      expect(refreshed.assessment!.isCurrent(clock), isFalse);
      final gps = await repository.load(
        const Place(id: 'gps:test', name: 'Current location'),
      );
      expect(gps.assessment, isNull);
    },
  );

  testWidgets('An assessment expires while the page remains open', (
    tester,
  ) async {
    var clock = now;
    final controller = DashboardController(
      repository: CallbackRepository(
        (_) async =>
            assessment('kibera', expires: now.add(const Duration(seconds: 2))),
      ),
      clock: () => clock,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.selectPlace(samplePlaces.first);
    expect(controller.status, DashboardStatus.ready);
    final before = notifications;
    clock = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(controller.status, DashboardStatus.stale);
    expect(notifications, greaterThan(before));
  });

  testWidgets('Timeout settles as error and ignores the late response', (
    tester,
  ) async {
    final response = Completer<DashboardData>();
    final controller = DashboardController(
      repository: CallbackRepository((_) => response.future),
      requestTimeout: const Duration(seconds: 1),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    final request = controller.selectPlace(samplePlaces.first);
    await tester.pump(const Duration(seconds: 1));
    await request;
    expect(controller.status, DashboardStatus.error);
    response.complete(assessment('kibera'));
    await tester.pump();
    expect(controller.status, DashboardStatus.error);
    expect(controller.data, isNull);
  });

  test(
    'Disposal during a request does not notify or schedule expiry',
    () async {
      final response = Completer<DashboardData>();
      final controller = DashboardController(
        repository: CallbackRepository((_) => response.future),
        clock: () => now,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);
      final request = controller.selectPlace(samplePlaces.first);
      controller.dispose();
      response.complete(assessment('kibera'));
      await request;
      expect(notifications, 1);
    },
  );
}
