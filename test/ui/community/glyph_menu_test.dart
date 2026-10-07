import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/community.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/community/glyph_menu.dart';
import 'package:glyph/ui/matrix/matrix_screen.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final opened = <Uri>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened.clear();
    Community.environment = () async =>
        const AppEnv(version: '1.3.0', build: '5', phone: 'Test Phone', os: 'Android 14 (SDK 34)');
    Community.launcher = (uri) async {
      opened.add(uri);
      return true;
    };
    LastError.clear();
  });
  tearDown(Community.resetForTest);

  Future<PlaybackController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore();
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await devices.load();
    final catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    final creations = CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph'));
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: catalog,
        creations: creations,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(
            body: MatrixScreen(services: SetupServices(discover: _none, scan: _none)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return playback;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(GlyphMenuKey).first);
    await settle(tester);
  }

  testWidgets('the Device tab is only about devices; the Glyph menu holds community and help', (tester) async {
    final playback = await pump(tester);
    expect(find.text('Connect your device'), findsWidgets, reason: 'no device yet');
    expect(find.text('COMMUNITY'), findsNothing);
    expect(find.text('Send feedback'), findsNothing);

    await openMenu(tester);
    for (final label in ['COMMUNITY', 'HELP & FEEDBACK', 'GLYPH']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final row in [
      'Chat on Discord',
      'Share your setup',
      'Roadmap',
      'Send feedback',
      'Suggest an animation',
      'Request display support',
      'What\'s new',
      'Source code',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Glyph 1.3.0 · Free & open source · MIT'), findsOneWidget);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Send feedback previews what is included; Discord first, GitHub second', (tester) async {
    final playback = await pump(tester);
    LastError.record('Couldn\'t send it: timed out talking to 192.168.1.20');
    await openMenu(tester);
    await tester.tap(find.text('Send feedback'));
    await settle(tester);
    expect(opened, isEmpty, reason: 'nothing opens until the person agrees');
    expect(find.text('Ask on Discord'), findsOneWidget);
    expect(find.text('Report on GitHub'), findsOneWidget);
    expect(find.text('Just copy the details'), findsOneWidget);
    final preview = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(preview, contains('Glyph 1.3.0 (5)'));
    expect(preview, contains('Device: not connected'));
    expect(preview, contains('Last error: Couldn\'t send it'));
    expect(preview, isNot(contains('192.168')));

    await tester.ensureVisible(find.text('Report on GitHub'));
    await settle(tester, 100);
    await tester.tap(find.text('Report on GitHub'));
    await settle(tester);
    expect(opened, hasLength(1));
    expect(opened.single.queryParameters['template'], 'bug.yml');
    expect(opened.single.queryParameters['diagnostics'], preview);
    expect(find.text('Report on GitHub'), findsNothing, reason: 'sheet closed');
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('menu links open their pages and close the menu', (tester) async {
    final playback = await pump(tester);
    await openMenu(tester);
    await tester.tap(find.text('Chat on Discord'));
    await settle(tester);
    expect(opened, [Community.discord]);
    expect(find.text('Roadmap'), findsNothing, reason: 'menu closed');
    await openMenu(tester);
    await tester.tap(find.text('Suggest an animation'));
    await settle(tester);
    expect(opened.last.queryParameters['template'], 'animation_request.yml');
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('setting up a device offers display support right there', (tester) async {
    final playback = await pump(tester);
    await tester.scrollUntilVisible(find.text('Not WLED? Ask for your display'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Not WLED? Ask for your display'));
    await settle(tester);
    expect(opened.single.queryParameters['template'], 'display_request.yml');
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });
}

/// Pumps fixed frames (previews tick forever, so never pumpAndSettle).
Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Stream<Never> _none() => const Stream.empty();
