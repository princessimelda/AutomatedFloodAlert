import 'dart:io';

import 'package:floodsafe/data/api_repository.dart';

/// Read-only cross-runtime smoke check; never sends real GPS coordinates.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/check_api.dart <local-api-url> [expected-alert-id]',
    );
    exitCode = 2;
    return;
  }
  final api = ApiRepository(baseUrl: arguments.first);
  try {
    final places = await api.listPlaces();
    for (final place in places) {
      final dashboard = await api.load(place);
      if (dashboard.placeId != place.id) {
        throw StateError('Dashboard response belongs to a different place.');
      }
    }
    final advisories = await api.loadAdvisories();
    final questions = await api.questions();
    if (questions.isEmpty) throw StateError('No published questions.');
    for (final question in questions) {
      final answer = await api.answer(question);
      if (!answer.current(DateTime.now().toUtc())) {
        throw StateError('Answer is no longer current.');
      }
    }
    final alerts = await api.alerts();
    if (arguments.length == 2 && !alerts.any((a) => a.id == arguments[1])) {
      throw StateError('Expected published test alert was not returned.');
    }
    if (alerts.any((a) => !a.current(DateTime.now().toUtc()))) {
      throw StateError('An expired or future alert was returned.');
    }
    stdout.writeln(
      'API contract check passed: ${places.length} places, ${advisories.length} advisories, ${questions.length} guided answers and ${alerts.length} published test alerts parsed.',
    );
  } catch (_) {
    stderr.writeln(
      'API contract check failed. Check server readiness and the configured URL.',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
