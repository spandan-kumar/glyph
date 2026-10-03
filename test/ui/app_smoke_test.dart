import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/main.dart';
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
}
