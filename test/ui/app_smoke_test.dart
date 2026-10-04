import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/design/led_text.dart';
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
      await tester.tap(find.descendant(of: find.byType(Dock), matching: find.bySemanticsLabel(tab)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: tab);
    }
    // No matrix yet: the hub invites a connection.
    await tester.tap(find.descendant(of: find.byType(Dock), matching: find.bySemanticsLabel('Device')));
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

  testWidgets('the dock is a small floating island in the pixel font', (tester) async {
    final playback = await pumpApp(tester);
    final dock = find.byType(Dock);
    expect(dock, findsOneWidget);
    expect(find.descendant(of: dock, matching: find.byType(Icon)), findsNothing);
    // Labels are LED pixel text, reachable by their accessibility labels.
    expect(find.descendant(of: dock, matching: find.byType(LedText)), findsNWidgets(3));
    for (final label in ['Display', 'Make', 'Device']) {
      expect(find.descendant(of: dock, matching: find.bySemanticsLabel(label)), findsOneWidget);
    }
    final screen = tester.getSize(find.byType(MaterialApp));
    final island = tester.getRect(find.descendant(of: dock, matching: find.byType(BackdropFilter)));
    expect(island.width, lessThan(screen.width * 0.75), reason: 'floats, doesn\'t span the screen');
    expect((island.center.dx - screen.width / 2).abs(), lessThan(1), reason: 'centred');

    // Equal tabs: Make sits dead centre.
    final make = tester.getCenter(find.descendant(of: dock, matching: find.bySemanticsLabel('Make')));
    expect((make.dx - screen.width / 2).abs(), lessThan(1), reason: 'symmetric');

    final indicator = find.byKey(const ValueKey('dock-indicator'));
    double block() => tester.getRect(indicator).center.dx;
    final atDisplay = block();
    await tester.tap(find.descendant(of: dock, matching: find.bySemanticsLabel('Device')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = block();
    await tester.pump(const Duration(milliseconds: 400));
    final atDevice = block();
    expect(midway, inExclusiveRange(atDisplay, atDevice), reason: 'the block slides');
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the dock tucks away scrolling down and returns scrolling up', (tester) async {
    final playback = await pumpApp(tester);
    final dock = find.byType(Dock);
    await tester.tap(find.descendant(of: dock, matching: find.bySemanticsLabel('Make')));
    await tester.pump(const Duration(milliseconds: 500));
    final screenH = tester.getSize(find.byType(MaterialApp)).height;
    double top() => tester.getRect(find.descendant(of: dock, matching: find.byType(BackdropFilter))).top;
    final shown = top();
    expect(shown, lessThan(screenH));

    await tester.drag(find.text('Timer'), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(top(), greaterThanOrEqualTo(screenH - 4), reason: 'slid away');

    await tester.drag(find.text('Music'), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(top(), closeTo(shown, 0.5), reason: 'back');
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
