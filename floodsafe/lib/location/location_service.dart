import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../dashboard/dashboard_data.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.message);
  final String message;
}

abstract interface class LocationService {
  Future<Place> currentPlace();
}

/// A single foreground fix, requested only after the user taps the GPS button.
/// No background tracking, uploads, or persistent coordinate storage.
class ForegroundLocationService implements LocationService {
  ForegroundLocationService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  @override
  Future<Place> currentPlace() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationFailure(
          'Location is switched off. Enable it in your device settings, or choose a place.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationFailure(
          'Location permission is blocked. Change it in your device or browser settings, or choose a place.',
        );
      }
      // Some browsers cannot query permissions in advance. The actual position
      // request still prompts for and enforces permission in that case.
      if (permission == LocationPermission.denied) {
        throw const LocationFailure(
          'Location permission was not granted. You can still choose a place.',
        );
      }
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final age = _clock().toUtc().difference(fix.timestamp.toUtc());
      if (age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -30)) {
        throw const LocationFailure(
          'That location fix is out of date. Try again or choose a place.',
        );
      }
      if (!fix.accuracy.isFinite || fix.accuracy < 0 || fix.accuracy > 250) {
        throw const LocationFailure(
          'Your location is too approximate. Try again near an open area, or choose a place.',
        );
      }
      if (!fix.latitude.isFinite ||
          !fix.longitude.isFinite ||
          fix.latitude.abs() > 90 ||
          fix.longitude.abs() > 180) {
        throw const LocationFailure(
          'Could not read a valid location. Choose a place instead.',
        );
      }
      return Place(
        id: 'gps:${fix.latitude}:${fix.longitude}',
        name: 'Your current location',
        latitude: fix.latitude,
        longitude: fix.longitude,
        recordedAt: fix.timestamp.toUtc(),
        accuracyMeters: fix.accuracy,
      );
    } on LocationFailure {
      rethrow;
    } on TimeoutException {
      throw const LocationFailure(
        'Location took too long. Try again or choose a place.',
      );
    } catch (_) {
      throw const LocationFailure(
        'Could not access location. Check device or browser permissions, or choose a place. On web, use HTTPS or localhost.',
      );
    }
  }
}
