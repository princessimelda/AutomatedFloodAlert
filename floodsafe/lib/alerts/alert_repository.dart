class PublicAlert {
  const PublicAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.action,
    required this.severity,
    required this.locations,
    required this.issuedAt,
    required this.validUntil,
  });
  final String id, title, message, action, severity;
  final List<String> locations;
  final DateTime issuedAt, validUntil;

  bool current(DateTime now) =>
      !now.isBefore(issuedAt) && now.isBefore(validUntil);
}

abstract interface class AlertRepository {
  Future<List<PublicAlert>> alerts({String? placeId});
  Future<void> acknowledge(String id);
}

class EmptyAlertRepository implements AlertRepository {
  const EmptyAlertRepository();
  @override
  Future<List<PublicAlert>> alerts({String? placeId}) async => [];
  @override
  Future<void> acknowledge(String id) async =>
      throw StateError('Sign in required');
}
