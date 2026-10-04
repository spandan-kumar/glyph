import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/community.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/community/community_section.dart';
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

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('Community shows with no device; Send feedback previews before opening GitHub', (tester) async {
    final playback = await pump(tester);
    expect(find.text('Connect your device'), findsWidgets, reason: 'no device yet');
    await reveal(tester, find.text('Send feedback'));
    expect(find.text('COMMUNITY'), findsOneWidget);
    for (final row in [
      'Suggest an animation',
      'Request support for your display',
      'Share your setup',
      'Roadmap',
      'Chat on Discord',
      'What\'s new',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await reveal(tester, find.textContaining('Free & open source'));
    expect(find.text('Glyph 1.3.0 · Free & open source · MIT'), findsOneWidget);

    LastError.record('Couldn\'t send it: timed out talking to 192.168.1.20');
    await reveal(tester, find.text('Send feedback'));
    await tester.tap(find.text('Send feedback'));
    await settle(tester);
    expect(opened, isEmpty, reason: 'nothing opens until the person agrees');
    expect(find.text('Open GitHub'), findsOneWidget);
    expect(find.text('Copy instead'), findsOneWidget);
    expect(find.textContaining('GitHub account'), findsOneWidget);
    final preview = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(preview, contains('Glyph 1.3.0 (5)'));
    expect(preview, contains('Device: not connected'));
    expect(preview, contains('Last error: Couldn\'t send it'));
    expect(preview, isNot(contains('192.168')));

    await tester.ensureVisible(find.text('Open GitHub'));
    await settle(tester, 100);
    await tester.tap(find.text('Open GitHub'));
    await settle(tester);
    expect(opened, hasLength(1));
    expect(opened.single.queryParameters['template'], 'bug.yml');
    expect(opened.single.queryParameters['diagnostics'], preview);
    expect(find.text('Open GitHub'), findsNothing, reason: 'sheet closed');

    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('link rows open their pages', (tester) async {
    final playback = await pump(tester);
    await reveal(tester, find.text('Roadmap'));
    await tester.tap(find.text('Roadmap'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Suggest an animation'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, [Community.roadmap, isA<Uri>()]);
    expect(opened.last.queryParameters['template'], 'animation_request.yml');
    expect(find.byType(CommunitySection), findsOneWidget);
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
