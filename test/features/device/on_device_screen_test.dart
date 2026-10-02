import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/screens/devices_screen.dart';
import 'package:glyph/ui/screens/on_device_screen.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;

  setUp(() {
    wled = FakeWled();
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([
        const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson(),
        const SavedDevice(host: '192.168.29.7', name: 'Shelf').toJson(),
      ]),
      'devices.selected': '192.168.29.6',
    });
  });

  Future<(DeviceStore, PlaybackController)> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore(clientFactory: wled.client);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await devices.load();
    final catalog = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    final creations = CreationsStore(
      directory: () async => Directory.systemTemp.createTemp('glyph'),
    );
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: catalog,
        creations: creations,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return (devices, playback);
  }

  /// Fixed-duration pumps (previews tick forever, so never pumpAndSettle).
  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(Duration(milliseconds: ms ~/ 4));
    }
  }

  /// TabBarView ignores pointers until its page animation has fully ended.
  Future<void> switchTab(WidgetTester tester) => settle(tester, 1200);

  testWidgets('On Device: presets, playlists, schedule, files at 360x740', (tester) async {
    final (devices, playback) = await pump(tester, const OnDeviceScreen());

    // Header synced from /json/state.
    expect(find.text('WLED'), findsWidgets, reason: 'name from /json/info');
    expect(find.byType(Switch), findsWidgets);
    expect(find.text('pipplee.gif'), findsWidgets, reason: 'active preset 102');

    // Presets tab.
    expect(find.text('Ocean Plasma'), findsOneWidget);
    expect(find.text('#1 · GIF · ocean-plasma.gif'), findsOneWidget);
    expect(find.textContaining('Turns the matrix off'), findsOneWidget);
    await tester.tap(find.text('Ocean Plasma'));
    await settle(tester, 800);
    expect(wled.posts.any((p) => p.$2['ps'] == 1), isTrue);
    expect(tester.takeException(), isNull);

    // Delete dialog warns about the shared GIF / offers to delete it.
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text('Ocean Plasma'), matching: find.byType(ListTile)),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(find.text('Also delete ocean-plasma.gif'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // Power toggle in the header.
    await tester.tap(find.byType(Switch).first);
    await settle(tester);
    expect(wled.posts.last.$2, {'on': false});

    // Playlists tab + editor.
    await tester.tap(find.text('Playlists'));
    await switchTab(tester);
    expect(find.text('glyph_test_list'), findsOneWidget);
    expect(find.textContaining('2 presets'), findsOneWidget);
    await tester.tap(find.text('New playlist'));
    await settle(tester, 600);
    expect(find.text('New playlist'), findsWidgets);
    await tester.tap(find.text('Add'));
    await settle(tester, 600);
    await tester.tap(find.text('Ocean Plasma').last);
    await settle(tester, 600);
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester, 600);

    // Schedule tab: timers from the real read-back.
    await tester.tap(find.text('Schedule'));
    await switchTab(tester);
    expect(find.text('03:07'), findsOneWidget);
    expect(find.text('30 min before sunset'), findsOneWidget);
    expect(find.text('Every hour at :15'), findsOneWidget);
    expect(find.text('At power-on'), findsOneWidget);
    await tester.tap(find.text('03:07'));
    await settle(tester, 600);
    expect(find.text('Edit schedule'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(180, 20));
    await settle(tester, 600);

    // Files tab.
    await tester.tap(find.text('Files'));
    await switchTab(tester);
    expect(find.text('98 of 983 KB used'), findsOneWidget);
    expect(find.text('duck.gif'), findsOneWidget);
    expect(find.textContaining('Used by Ocean Plasma'), findsOneWidget);
    await tester.drag(find.text('duck.gif'), const Offset(0, -500));
    await settle(tester);
    expect(find.textContaining('Needed by WLED'), findsWidgets);
    expect(tester.takeException(), isNull);

    devices.setBrightness(40);
    await settle(tester);
    playback.pause();
  });

  testWidgets('Matrix screen: rename, mirror group, switching chips', (tester) async {
    final (devices, playback) = await pump(tester, const DevicesScreen());
    await settle(tester);
    expect(find.text('MIRROR GROUP'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await tester.ensureVisible(find.byType(SwitchListTile).first);
    await settle(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await settle(tester);
    expect(devices.mirrorHosts, {'192.168.29.7'});
    expect(playback.mirrors.single.host, '192.168.29.7');

    await tester.ensureVisible(find.byTooltip('Rename on the matrix'));
    await settle(tester);
    await tester.tap(find.byTooltip('Rename on the matrix'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Living room');
    await tester.tap(find.text('Save'));
    await settle(tester, 800);
    expect(wled.posts.any((p) => p.$1 == '/json/cfg'), isTrue);
    expect(tester.takeException(), isNull);
    playback.pause();
  });

  testWidgets('On Device shows an empty state without a matrix', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final (_, playback) = await pump(tester, const OnDeviceScreen());
    expect(find.textContaining('Connect a matrix'), findsOneWidget);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}
