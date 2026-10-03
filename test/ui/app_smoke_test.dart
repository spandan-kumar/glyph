import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/design/dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  });

  Future<PlaybackController> pumpApp(WidgetTester tester,
      {Size size = const Size(412, 915), bool onboarding = false}) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    final creations = CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph'));
    await tester.pumpWidget(GlyphApp(
      catalog: catalog,
      devices: DeviceStore(),
      playback: playback,
      creations: creations,
      showOnboarding: onboarding,
    ));
    // Previews tick forever, so pump fixed durations instead of settling.
    await tester.pump(const Duration(milliseconds: 400));
    return playback;
  }

  testWidgets('every destination builds without overflow on a narrow phone', (tester) async {
    final playback = await pumpApp(tester, size: const Size(360, 740));
    for (final tab in ['Make', 'Device', 'Display']) {
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: tab);
    }
    // No matrix yet: the hub invites a connection.
    await tester.tap(find.text('Device').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Connect'), findsWidgets);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('first run can be skipped straight into Display', (tester) async {
    final playback = await pumpApp(tester, onboarding: true);
    expect(find.text('Find my device'), findsOneWidget);
    await tester.tap(find.text('Just looking around'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Display'), findsWidgets);
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dock is a typographic strip: LED glyphs, a sliding lit segment', (tester) async {
    final playback = await pumpApp(tester);
    final dock = find.byType(Dock);
    expect(dock, findsOneWidget);
    // No stock Material icons: each tab is a painted LED glyph and its name.
    expect(find.descendant(of: dock, matching: find.byType(Icon)), findsNothing);
    for (final label in ['Display', 'Make', 'Device']) {
      expect(find.descendant(of: dock, matching: find.text(label)), findsOneWidget);
    }
    final rect = tester.getRect(dock);
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(rect.width, screen.width, reason: 'spans the width; the strip itself is inset by gutters');

    final indicator = find.byKey(const ValueKey('dock-indicator'));
    Rect segment() => tester.getRect(find.descendant(of: indicator, matching: find.byType(AnimatedContainer)));
    final atDisplay = segment().center.dx;
    expect(atDisplay, lessThan(screen.width / 3));

    await tester.tap(find.descendant(of: dock, matching: find.text('Device')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = segment().center.dx;
    await tester.pump(const Duration(milliseconds: 400));
    final atDevice = segment().center.dx;
    expect(midway, inExclusiveRange(atDisplay, atDevice), reason: 'the segment slides');
    expect(atDevice, greaterThan(screen.width * 2 / 3));
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
