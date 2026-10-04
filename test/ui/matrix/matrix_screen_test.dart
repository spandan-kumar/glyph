import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/features/device/widgets/device_settings.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/design/toggle.dart';
import 'package:glyph/ui/matrix/matrix_screen.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';

void main() {
  late FakeWled wled;

  final twoMatrices = {
    'devices.v1': jsonEncode([
      const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson(),
      const SavedDevice(host: '192.168.29.7', name: 'Shelf').toJson(),
    ]),
    'devices.selected': '192.168.29.6',
  };

  setUp(() {
    wled = FakeWled();
    // The intro install has its own tests (boot_intro_test.dart).
    BootIntro.autoInstall = false;
  });
  tearDown(BootIntro.resetForTest);

  const quiet = SetupServices(discover: _none, scan: _none);

  Future<(DeviceStore, PlaybackController)> pump(WidgetTester tester, {SettingsViewBuilder? settingsView}) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore(clientFactory: wled.client);
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
          home: Scaffold(body: MatrixScreen(services: quiet, settingsView: settingsView)),
        ),
      ),
    );
    await settle(tester, 800);
    return (devices, playback);
  }

  /// Scrolls the hub until [f] is on screen.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester, 200);
  }

  testWidgets('connected: header, controls, Saved, Shows, Routines, Storage at 360x740', (tester) async {
    SharedPreferences.setMockInitialValues(twoMatrices);
    final (devices, playback) = await pump(tester);

    // Header in plain words.
    expect(find.text('DEVICE'), findsOneWidget, reason: 'section label');
    expect(find.text('WLED'), findsOneWidget, reason: 'name from /json/info');
    expect(find.text('16×16 · WLED 16.0.1 · Wi-Fi 20%'), findsOneWidget);
    expect(find.textContaining('Weak Wi-Fi'), findsOneWidget);
    // The Stage shows what's saved and playing (preset 102 plays pipplee.gif).
    expect(find.text('SAVED ON YOUR DEVICE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Power.
    await reveal(tester, find.byKey(const ValueKey('power')));
    await tester.tap(find.byKey(const ValueKey('power')));
    await settle(tester);
    expect(wled.posts.last.$2, {'on': false});
    await tester.tap(find.byKey(const ValueKey('power')));
    await settle(tester);

    // Saved: tiles, not the "off" entry; tap plays.
    await reveal(tester, find.text('Ocean Plasma'));
    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('WLED Turn Off'), findsNothing);
    await tester.tap(find.text('Ocean Plasma'));
    await settle(tester, 800);
    expect(wled.posts.any((p) => p.$2['ps'] == 1), isTrue);

    // Long-press menu → delete offers to free the GIF.
    await tester.longPress(find.text('Ocean Plasma'));
    await settle(tester);
    expect(find.text('Saved on your device.'), findsOneWidget);
    for (final a in ['Play now', 'Rename', 'Delete']) {
      expect(find.text(a), findsWidgets, reason: a);
    }
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(find.textContaining('Also free up'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(tester.takeException(), isNull);

    // Shows.
    await reveal(tester, find.text('glyph_test_list'));
    expect(find.textContaining('2 animations'), findsOneWidget);
    expect(find.text('New show'), findsOneWidget);

    // Routines as sentences.
    await reveal(tester, find.text('Every hour at :15 → something removed'));
    expect(find.text('These run on your device, even when your phone is off.'), findsOneWidget);
    expect(find.text('When it powers on → Pipplee'), findsOneWidget);
    expect(find.text('Mon, Wed, Fri at 3:07 → something removed'), findsOneWidget);
    expect(
      find.text('Every day 30 min before sunset, 2 Nov – 20 Feb → glyph_test_list'),
      findsOneWidget,
    );

    // Storage in plain words.
    await reveal(tester, find.text('98 KB of 983 KB used'));
    expect(
      find.textContaining(RegExp(r'^\d+ B is used by old files that nothing plays anymore\. Tap to free it up\.$')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Your devices: chips, mirror group, settings, advanced.
    await reveal(tester, find.text('Shelf').last);
    expect(find.text('YOUR DEVICES'), findsOneWidget);
    expect(find.text('Add a device'), findsOneWidget);
    expect(find.text('Device settings'), findsOneWidget);
    expect(find.text('The full WLED setup, inside Glyph'), findsOneWidget);
    await reveal(tester, find.byType(LbToggle).last);
    await tester.tap(find.byType(LbToggle).last);
    await settle(tester);
    expect(devices.mirrorHosts, {'192.168.29.7'});
    await reveal(tester, find.text('Advanced'));
    await tester.tap(find.text('Advanced'));
    await settle(tester);
    await reveal(tester, find.text('Forget this device'));
    expect(find.text('192.168.29.6'), findsWidgets);
    expect(find.text('Zig-zag rows'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // No jargon in the primary UI.
    for (final word in ['preset', 'Preset', 'playlist', 'Playlist', 'segment', 'DDP', 'matrix', 'Kept', 'kept']) {
      expect(find.textContaining(word), findsNothing, reason: word);
    }
    playback.pause();
  });

  testWidgets('rename and fix orientation from Your devices', (tester) async {
    SharedPreferences.setMockInitialValues(twoMatrices);
    final (_, playback) = await pump(tester);
    await reveal(tester, find.text('Rename'));
    await tester.tap(find.text('Rename'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Living room');
    await tester.tap(find.text('Save'));
    await settle(tester, 800);
    expect(wled.posts.any((p) => p.$1 == '/json/cfg'), isTrue);

    await reveal(tester, find.text('Fix orientation'));
    await tester.tap(find.text('Fix orientation'));
    await settle(tester, 600);
    expect(find.text('Which way is the arrow pointing on your device?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, 600);
    expect(find.text('Which way is the arrow pointing on your device?'), findsNothing);
    playback.pause();
  });

  testWidgets('no device: an inviting empty state that opens the search', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final (_, playback) = await pump(tester);
    expect(find.text('DEVICE'), findsOneWidget);
    expect(find.text('Connect your device'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect your device'));
    await settle(tester, 600);
    expect(find.text('Add a device'), findsOneWidget);
    expect(find.text('Can\'t see it?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester, 600);
    expect(find.text('Add a device'), findsNothing);
    playback.pause();
  });

  testWidgets('saved but unreachable: says so plainly, still lets you switch', (tester) async {
    SharedPreferences.setMockInitialValues(twoMatrices);
    wled.offline = true;
    final (devices, playback) = await pump(tester);
    expect(devices.isConnected, isFalse);
    expect(find.text('Matrix'), findsWidgets);
    expect(find.text('Can\'t reach it right now'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Device settings'), findsNothing, reason: 'only offered when it answers');
    await reveal(tester, find.text('Add a device'));
    expect(find.text('Shelf'), findsWidgets);
    expect(tester.takeException(), isNull);

    wled.offline = false;
    // Back up: the Community section below can scroll it out of the list.
    await tester.scrollUntilVisible(find.text('Try again'), -200, scrollable: find.byType(Scrollable).first);
    await settle(tester, 200);
    await tester.tap(find.text('Try again'));
    await settle(tester, 800);
    expect(devices.isConnected, isTrue);
    // The header may sit just above the viewport after scrolling back up.
    expect(find.text('16×16 · WLED 16.0.1 · Wi-Fi 20%', skipOffstage: false), findsOneWidget);
    playback.pause();
  });

  testWidgets('Device settings opens WLED\'s own pages and re-reads the device on close', (tester) async {
    SharedPreferences.setMockInitialValues(twoMatrices);
    final (_, playback) = await pump(
      tester,
      settingsView: (context, url) => Center(child: Text('web view: $url')),
    );
    await reveal(tester, find.text('Device settings'));
    await tester.tap(find.text('Device settings'));
    await settle(tester, 600);
    expect(find.byType(DeviceSettingsPage), findsOneWidget);
    expect(find.text('web view: http://192.168.29.6/settings'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(tester.takeException(), isNull);

    wled.gets.clear();
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, 600);
    expect(find.byType(DeviceSettingsPage), findsNothing);
    expect(wled.gets, contains('/json/info'), reason: 'changes made in WLED show up');
    expect(find.text('Device settings'), findsOneWidget);
    playback.pause();
  });
}

Stream<Never> _none() => const Stream.empty();

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
