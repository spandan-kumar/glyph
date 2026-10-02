import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Catalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
  });

  Future<PlaybackController> pumpApp(WidgetTester tester,
      {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final devices = DeviceStore();
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await tester.pumpWidget(GlyphApp(catalog: catalog, devices: devices, playback: playback));
    // Previews tick forever, so pump fixed durations instead of settling.
    await tester.pump(const Duration(milliseconds: 300));
    return playback;
  }

  testWidgets('discover grid renders and playing an item shows the mini player',
      (tester) async {
    final playback = await pumpApp(tester);
    expect(find.text('Glyph'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    final first = catalog.items.first;
    await tester.tap(find.text(first.title).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Preview only · no matrix connected'), findsOneWidget);

    // Open the now-playing sheet and change palette + a param.
    await tester.tap(find.text('Preview only · no matrix connected'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Save to matrix'), findsOneWidget);
    expect(find.text('COLOURS'), findsOneWidget);
    await tester.drag(find.byType(Slider).last, const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    // The render loop is a periodic Timer; stop it before the test ends.
    playback.pause();
  });

  testWidgets('category filter and search narrow the grid', (tester) async {
    await pumpApp(tester);
    final category = catalog.categories.first;
    await tester.tap(find.text(category).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No animations match'), findsOneWidget);
  });

  testWidgets('every tab builds without overflow', (tester) async {
    await pumpApp(tester, size: const Size(360, 740));
    for (final tab in ['Create', 'On Device', 'Matrix', 'Discover']) {
      await tester.tap(find.text(tab));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: tab);
      if (tab == 'Matrix') expect(find.text('Add by IP'), findsOneWidget);
    }
  });
}
