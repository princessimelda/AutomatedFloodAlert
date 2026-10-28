import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dashboard_data.dart';

enum DashboardStatus { choosePlace, loading, ready, unavailable, stale, error }

class DashboardController extends ChangeNotifier {
  DashboardController({
    required this.repository,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _clock = clock ?? DateTime.now;

  final DashboardRepository repository;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  Place? place;
  DashboardData? data;
  bool loading = false;
  bool failed = false;
  bool _disposed = false;
  int _request = 0;
  Timer? _expiry;

  DashboardStatus get status {
    if (place == null) return DashboardStatus.choosePlace;
    if (loading) return DashboardStatus.loading;
    if (failed) return DashboardStatus.error;
    final assessment = data?.assessment;
    if (assessment == null) return DashboardStatus.unavailable;
    if (!assessment.isCurrent(_clock().toUtc())) return DashboardStatus.stale;
    return DashboardStatus.ready;
  }

  Future<void> selectPlace(Place selected) async {
    if (_disposed) return;
    final request = ++_request;
    _expiry?.cancel();
    place = selected;
    // Clear the old area's risk immediately, including while loading.
    data = null;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final result = await repository.load(selected).timeout(requestTimeout);
      if (_disposed || request != _request) return;
      if (result.placeId != selected.id) {
        throw StateError('Assessment does not belong to the selected place.');
      }
      data = result;
      final assessment = result.assessment;
      if (assessment != null && assessment.isCurrent(_clock().toUtc())) {
        _expiry = Timer(assessment.validUntil.difference(_clock().toUtc()), () {
          if (!_disposed) notifyListeners();
        });
      }
    } catch (_) {
      if (_disposed || request != _request) return;
      failed = true;
    }
    loading = false;
    notifyListeners();
  }

  void clear() {
    _request++;
    _expiry?.cancel();
    place = null;
    data = null;
    loading = false;
    failed = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    final selected = place;
    if (selected != null) await selectPlace(selected);
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _expiry?.cancel();
    super.dispose();
  }
}
