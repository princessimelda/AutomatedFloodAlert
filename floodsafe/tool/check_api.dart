import 'dart:io';

import 'package:floodsafe/data/api_repository.dart';

/// Read-only cross-runtime smoke check; never sends real GPS coordinates.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/check_api.dart <local-api-url>');
    exitCode = 2;
    return;
  }
  final api = ApiRepository(baseUrl: arguments.single);
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
    stdout.writeln(
      'API contract check passed: ${places.length} places, ${advisories.length} advisories and ${questions.length} guided answers parsed.',
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
