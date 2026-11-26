import '../dashboard/dashboard_data.dart';

class FoundPlace {
  const FoundPlace(this.place, this.description);
  final Place place;
  final String description;
}

abstract interface class PlaceSearchRepository {
  Future<List<FoundPlace>> searchPlaces(String query);
}

class RainfallEstimate {
  const RainfallEstimate({
    required this.rainMm,
    required this.intervalMinutes,
    required this.validAt,
    required this.forecastRainMm,
    required this.forecastStart,
    required this.forecastEnd,
    required this.retrievedAt,
    required this.validUntil,
  });
  final double rainMm, forecastRainMm;
  final int intervalMinutes;
  final DateTime validAt, forecastStart, forecastEnd, retrievedAt, validUntil;
  bool current(DateTime now) =>
      now.isBefore(validUntil) &&
      !retrievedAt.isAfter(now.add(const Duration(minutes: 1)));
}

abstract interface class WeatherRepository {
  Future<RainfallEstimate> rainfall(double latitude, double longitude);
}
