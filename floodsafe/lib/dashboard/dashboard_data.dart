enum RiskLevel { low, moderate, high }

class Place {
  const Place({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    this.recordedAt,
    this.accuracyMeters,
    this.isDemo = false,
  });
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;
  final DateTime? recordedAt;
  final double? accuracyMeters;
  final bool isDemo;
}

const samplePlaces = [
  Place(id: 'kibera', name: 'Kibera', isDemo: true),
  Place(id: 'westlands', name: 'Westlands', isDemo: true),
  Place(id: 'embakasi', name: 'Embakasi', isDemo: true),
  Place(id: 'kasarani', name: 'Kasarani', isDemo: true),
];

/// An assessment's validity is independent of when the app downloaded it.
class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.issuedAt,
    required this.validUntil,
  });
  final RiskLevel level;
  final DateTime issuedAt;
  final DateTime validUntil;

  bool isCurrent(DateTime now) =>
      !now.isBefore(issuedAt) && now.isBefore(validUntil);
}

class DashboardData {
  const DashboardData({
    required this.placeId,
    required this.source,
    required this.isDemo,
    this.assessment,
  });
  final String placeId;
  final String source;
  final bool isDemo;
  final RiskAssessment? assessment;
}

abstract interface class DashboardRepository {
  Future<DashboardData> load(Place place);
}

/// Controlled scenarios, never predictions for real coordinates.
/// Replace this repository with an authenticated API implementation later.
class FixtureDashboardRepository implements DashboardRepository {
  FixtureDashboardRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final Map<String, DashboardData> _fixtures = {};

  @override
  Future<DashboardData> load(Place place) async {
    final now = _clock().toUtc();
    // Preserve original validity on refresh: old information cannot become
    // current merely because the user fetched it again.
    return _fixtures.putIfAbsent(place.id, () {
      final level = switch (place.id) {
        'kibera' || 'embakasi' => RiskLevel.high,
        'kasarani' => RiskLevel.low,
        _ => null,
      };
      final expired = place.id == 'embakasi';
      return DashboardData(
        placeId: place.id,
        source: 'FloodSafe test scenarios · not a weather or flood service',
        isDemo: true,
        assessment: level == null
            ? null
            : RiskAssessment(
                level: level,
                issuedAt: now.subtract(Duration(hours: expired ? 4 : 1)),
                validUntil: expired
                    ? now.subtract(const Duration(hours: 2))
                    : now.add(const Duration(hours: 1)),
              ),
      );
    });
  }
}
