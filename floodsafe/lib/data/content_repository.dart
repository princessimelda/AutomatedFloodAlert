import '../dashboard/dashboard_data.dart';

abstract interface class ContentRepository {
  Future<List<Place>> listPlaces();
  Future<List<Advisory>> loadAdvisories({Place? place});
}

class FixtureContentRepository implements ContentRepository {
  const FixtureContentRepository();
  @override
  Future<List<Place>> listPlaces() async => samplePlaces;
  @override
  Future<List<Advisory>> loadAdvisories({Place? place}) async => [];
}

class Advisory {
  const Advisory({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.sourceUrl,
    required this.publishedAt,
    required this.validUntil,
    required this.isDemo,
  });
  final String id;
  final String title;
  final String body;
  final String source;
  final String sourceUrl;
  final DateTime publishedAt;
  final DateTime validUntil;
  final bool isDemo;

  bool current(DateTime now) =>
      !now.isBefore(publishedAt) && now.isBefore(validUntil);
}
