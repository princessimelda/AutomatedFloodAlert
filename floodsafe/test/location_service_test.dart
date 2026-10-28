import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:floodsafe/location/location_service.dart';

class FakeGeolocator extends GeolocatorPlatform {
  FakeGeolocator(this.fix);
  final Position fix;
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.denied;
  bool timedOut = false;
  int prompts = 0;
  int fixes = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return requested;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    fixes++;
    if (timedOut) throw TimeoutException('timeout');
    return fix;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 28, 10);
  Position fix({
    DateTime? timestamp,
    double accuracy = 20,
    double latitude = -1.29,
  }) => Position(
    longitude: 36.82,
    latitude: latitude,
    timestamp: timestamp ?? now,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
  late GeolocatorPlatform original;
  late FakeGeolocator platform;
  late ForegroundLocationService service;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = FakeGeolocator(fix());
    GeolocatorPlatform.instance = platform;
    service = ForegroundLocationService(clock: () => now);
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test(
    'GPS returns coordinates and metadata without inventing a neighbourhood',
    () async {
      final place = await service.currentPlace();
      expect(place.name, 'Your current location');
      expect(place.id, startsWith('gps:'));
      expect(place.latitude, -1.29);
      expect(place.recordedAt, now);
      expect(place.accuracyMeters, 20);
      expect(platform.prompts, 0);
    },
  );

  test(
    'Disabled services and permanent denial do not request a position',
    () async {
      platform.enabled = false;
      await expectLater(
        service.currentPlace(),
        throwsA(isA<LocationFailure>()),
      );
      platform.enabled = true;
      platform.permission = LocationPermission.deniedForever;
      await expectLater(
        service.currentPlace(),
        throwsA(isA<LocationFailure>()),
      );
      expect(platform.fixes, 0);
      expect(platform.prompts, 0);
    },
  );

  test('A denied permission is prompted once and can be granted', () async {
    platform.permission = LocationPermission.denied;
    await expectLater(service.currentPlace(), throwsA(isA<LocationFailure>()));
    expect(platform.fixes, 0);
    platform.requested = LocationPermission.whileInUse;
    await service.currentPlace();
    expect(platform.fixes, 1);
  });

  test(
    'A browser without permission-query support still requests a fix',
    () async {
      platform.permission = LocationPermission.unableToDetermine;
      await service.currentPlace();
      expect(platform.fixes, 1);
    },
  );

  test(
    'Stale, future, inaccurate and invalid coordinates are rejected',
    () async {
      for (final position in [
        fix(timestamp: now.subtract(const Duration(minutes: 3))),
        fix(timestamp: now.add(const Duration(minutes: 1))),
        fix(accuracy: 500),
        fix(accuracy: double.nan),
        fix(latitude: 91),
      ]) {
        GeolocatorPlatform.instance = FakeGeolocator(position);
        await expectLater(
          service.currentPlace(),
          throwsA(isA<LocationFailure>()),
        );
      }
    },
  );

  test('Position timeout becomes a recoverable user-facing failure', () async {
    platform.timedOut = true;
    await expectLater(
      service.currentPlace(),
      throwsA(
        isA<LocationFailure>().having(
          (failure) => failure.message,
          'message',
          contains('too long'),
        ),
      ),
    );
  });
}
