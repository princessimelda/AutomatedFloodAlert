import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/seasonal_advisory.dart';

void main() {
  testWidgets(
    'Seasonal outlook has provenance and is not a local flood warning',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeasonalAdvisory(now: DateTime.utc(2026, 11, 25)),
          ),
        ),
      );
      expect(
        find.text('Seasonal outlook · October–December 2026'),
        findsOneWidget,
      );
      expect(find.textContaining('Issued 26 August 2026'), findsOneWidget);
      expect(find.textContaining('does not confirm flooding'), findsOneWidget);
      expect(seasonalSource, contains('ncof13'));
    },
  );

  testWidgets('Past outlook does not retain active seasonal forecast wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SeasonalAdvisory(now: DateTime.utc(2027, 1, 1))),
      ),
    );
    expect(
      find.textContaining('This seasonal outlook has ended'),
      findsOneWidget,
    );
    expect(find.textContaining('expects above-average rainfall'), findsNothing);
  });
}
