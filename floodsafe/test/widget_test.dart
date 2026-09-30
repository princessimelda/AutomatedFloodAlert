import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/main.dart';

void main() {
  Future<void> start(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FloodSafeApp());
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Phone validation, demo verification, location and route preview',
    (tester) async {
      await start(tester, const Size(390, 844));
      await tapText(tester, 'Continue');
      expect(
        find.text('Enter a Kenyan number, e.g. 712345678.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('phone-input')), '712345678');
      await tapText(tester, 'Continue');
      expect(find.text('Verify your number'), findsOneWidget);
      await tapText(tester, 'Verify & continue');
      expect(
        find.text('For this demo, enter the code 123456.'),
        findsOneWidget,
      );
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(Key('otp-$i')), '${i + 1}');
      }
      await tapText(tester, 'Verify & continue');
      await tapText(tester, 'Use demo location');
      expect(find.text('Kibera, Nairobi'), findsOneWidget);
      await tapText(tester, 'Preview safe-route feature');
      expect(find.text('Your route preview is ready'), findsOneWidget);
      await tapText(tester, 'Got it');
      expect(find.text('Hide demo route'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Manual location selection, filtered news and article details', (
    tester,
  ) async {
    await start(tester, const Size(360, 800));
    await tapText(tester, 'Explore the demo first');
    await tapText(tester, 'Choose a location myself');
    await tester.tap(find.byKey(const Key('location-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search locations'),
      'West',
    );
    await tapText(tester, 'Westlands');
    expect(find.text('Westlands, Nairobi'), findsOneWidget);
    await tapText(tester, 'Flood News');
    await tapText(tester, 'River Levels');
    expect(find.text('A closer look at Nairobi River'), findsOneWidget);
    expect(find.text('Heavy rainfall across Nairobi'), findsNothing);
    await tapText(tester, 'A closer look at Nairobi River');
    expect(find.text('SAMPLE CONTENT'), findsOneWidget);
    await tapText(tester, 'Back to updates');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop navigation and scripted assistant work', (tester) async {
    await start(tester, const Size(1440, 1000));
    await tapText(tester, 'Explore the demo first');
    await tapText(tester, 'Use demo location');
    expect(find.text('Overview'), findsOneWidget);
    await tapText(tester, 'AI Assistant');
    await tapText(tester, 'Explain the risk map');
    expect(
      find.textContaining('not current flood predictions'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('assistant-input')), 'hello');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot answer live questions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compact welcome fits a small phone', (tester) async {
    await start(tester, const Size(320, 640));
    await tapText(tester, 'Explore the demo first');
    await tapText(tester, 'Use demo location');
    expect(tester.takeException(), isNull);
  });
  testWidgets('Welcome adapts to a short desktop window', (tester) async {
    await start(tester, const Size(1000, 600));
    await tapText(tester, 'Explore the demo first');
    await tapText(tester, 'Use demo location');
    expect(tester.takeException(), isNull);
  });
}
