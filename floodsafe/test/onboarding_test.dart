import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floodsafe/account/account_screen.dart';
import 'package:floodsafe/main.dart';
import 'package:floodsafe/onboarding.dart';
import 'package:floodsafe/ui.dart';

import 'account_test.dart' show FakeAccount;

// Optional review captures; CI tests the layouts without writing images.
Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['FLOODSAFE_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('preview-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (Platform.environment['FLOODSAFE_PREVIEW_DIR'] == null) return;
    for (final entry in {
      'Roboto': ['assets/fonts/Roboto.ttf'],
      'Lora': ['assets/fonts/Lora.ttf'],
      // Widget tests default otherwise unspecified styles to Ahem blocks.
      'Ahem': ['assets/fonts/Roboto.ttf'],
      'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(rootBundle.load(file));
      }
      await loader.load();
    }
  });

  Future<void> show(
    WidgetTester tester,
    Widget screen,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const FloodSafeApp());
    final appTheme = Theme.of(tester.element(find.byType(Scaffold).first));
    // Resolve the app's inherited button font explicitly: widget-test defaults
    // use Ahem when a component style omits its font family.
    final buttonStyle = appTheme.filledButtonTheme.style!;
    final theme = appTheme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle.copyWith(
          textStyle: WidgetStatePropertyAll(
            buttonStyle.textStyle!.resolve({})!.copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const Key('preview-boundary'),
            child: child!,
          ),
        ),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 1000.0]) {
    testWidgets('Landscape and welcome adapt to width $width', (tester) async {
      await show(tester, const WelcomeScreen(), Size(width, 800));
      expect(find.text('Welcome'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'welcome-${width.toInt()}');
      await show(
        tester,
        const Scaffold(body: Center(child: Landscape(height: 230))),
        Size(width, 250),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'landscape-${width.toInt()}');
    });
    testWidgets('Welcome keeps actions reachable at 200% and width $width', (
      tester,
    ) async {
      await show(tester, const WelcomeScreen(), Size(width, 600), scale: 2);
      final explore = find.text('Explore the demo first');
      await tester.ensureVisible(explore);
      await tester.pumpAndSettle();
      expect(explore.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Account screen stays readable at width $width', (
      tester,
    ) async {
      final account = FakeAccount();
      addTearDown(account.events.close);
      await show(tester, AccountScreen(repository: account), Size(width, 800));
      expect(find.text('Sign in to save places'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'account-${width.toInt()}');
    });
    testWidgets('Account actions stay reachable at 200% and width $width', (
      tester,
    ) async {
      final account = FakeAccount();
      addTearDown(account.events.close);
      await show(
        tester,
        AccountScreen(repository: account),
        Size(width, 600),
        scale: 2,
      );
      final back = find.text('Back to Home');
      await tester.scrollUntilVisible(
        back,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(back.hitTestable(), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
