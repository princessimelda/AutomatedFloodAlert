import 'package:latlong2/latlong.dart';

abstract interface class RouteRepository {
  Future<WalkingRoute> findRoute({
    required LatLng origin,
    LatLng? destination,
    required bool avoidSteps,
    required List<LatLng> blocked,
  });
}

class WalkingRoute {
  const WalkingRoute({
    required this.status,
    required this.message,
    required this.points,
    required this.validUntil,
    this.destinationName,
    this.distanceM,
    this.minutes,
    this.startGap,
    this.endGap,
    this.roads = const [],
  });
  final String status, message;
  final List<LatLng> points;
  final DateTime validUntil;
  final String? destinationName;
  final int? distanceM, minutes, startGap, endGap;
  final List<String> roads;
}
