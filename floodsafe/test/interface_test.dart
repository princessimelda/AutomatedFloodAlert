import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floodsafe/main.dart';

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['FLOODSAFE_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('interface-preview')),
    );
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
      'Lora': 'assets/fonts/Lora.ttf',
      'Ahem': 'assets/fonts/Lora.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  Future<void> start(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const RepaintBoundary(
        key: Key('interface-preview'),
        child: FloodSafeApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Desktop navigation opens help and emergency resources', (
    tester,
  ) async {
    await start(tester, const Size(1440, 1100));
    expect(find.byKey(const Key('home-intro')), findsOneWidget);
    expect(find.byKey(const Key('nav-2')), findsOneWidget);
    expect(find.text('English'), findsNothing);
    await _capture(tester, 'home-desktop');
    await tester.tap(find.byKey(const Key('nav-5')));
    await tester.pumpAndSettle();
    expect(find.text('Call 112'), findsOneWidget);
    expect(find.text('Call 999'), findsOneWidget);
    expect(find.text('Call 1199'), findsOneWidget);
    await _capture(tester, 'emergency-desktop');
    await tester.tap(find.byKey(const Key('nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a question for practical help.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mobile menu and emergency page support 200 percent text', (
    tester,
  ) async {
    await start(tester, const Size(320, 720), scale: 2);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emergency Help'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Call 112'), 180);
    await tester.pumpAndSettle();
    expect(find.text('Call 112').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'emergency-mobile-large-text');
  });
}
