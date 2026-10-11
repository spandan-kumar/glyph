import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/generators/intro.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/features/device/device_manager.dart';
import 'package:glyph/features/device/widgets/common.dart';
import 'package:glyph/features/device/widgets/routines.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/matrix/matrix_screen.dart';
import 'package:glyph/ui/onboarding/onboarding_flow.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/wled/device.dart';
import 'package:glyph/wled/presets.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

void main() {
  late FakeWled wled;
  final fakeGif = Uint8List.fromList(List.filled(321, 7));

  setUp(() {
    wled = FakeWled(); // def.ps = 102 (Pipplee)
    BootIntro.resetForTest();
    BootIntro.bake = (w, h) async => fakeGif;
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
      'devices.selected': '192.168.29.6',
    });
  });
  tearDown(BootIntro.resetForTest);

  Future<DeviceCapabilities> caps() => wled.client('h').capabilities();

  Map<String, dynamic> presetBody(int id) => (wled.presets['$id'] as Map).cast<String, dynamic>();

  group('install', () {
    test('uploads the GIF, writes both presets without playing, points power-on at the playlist', () async {
      final c = wled.client('192.168.29.6');
      expect(await BootIntro.ensure(c, await caps()), isTrue);

      expect(wled.uploads, ['/glyph-intro.gif', '/presets.json']);
      expect(wled.gifs['/glyph-intro.gif'], fakeGif);
      final intro = presetBody(250), playlist = presetBody(249);
      expect(intro['n'], 'Glyph intro');
      expect((intro['seg'] as List).single, containsPair('n', 'glyph-intro.gif'));
      expect(playlist['n'], 'Power-on');
      expect(playlist['playlist'], {
        'ps': [250],
        'dur': [56],
        'transition': [0],
        'repeat': 1,
        'r': false,
        'end': 102,
      });
      expect(wled.bootPreset, 249);
      // Nothing was played or saved through the JSON API.
      expect(wled.posts.where((p) => p.$1 == '/json/state'), isEmpty);
      // The user's presets are untouched.
      expect(presetBody(1)['n'], 'Ocean Plasma');
      expect(presetBody(102)['n'], 'pipplee.gif');
    });

    test('is idempotent: a second connect writes nothing', () async {
      final c = wled.client('192.168.29.6');
      await BootIntro.ensure(c, await caps());
      final uploads = wled.uploads.length, posts = wled.posts.length;
      expect(await BootIntro.ensure(c, await caps()), isFalse);
      expect(wled.uploads.length, uploads);
      expect(wled.posts.length, posts);
    });

    test('re-uploads a GIF of the wrong size only', () async {
      final c = wled.client('192.168.29.6');
      await BootIntro.ensure(c, await caps());
      wled.files.firstWhere((f) => f['name'] == 'glyph-intro.gif')['size'] = 12;
      wled.uploads.clear();
      expect(await BootIntro.ensure(c, await caps()), isTrue);
      expect(wled.uploads, ['/glyph-intro.gif']);
    });

    test('with no power-on look the intro rests on the logo', () async {
      (wled.cfg['def'] as Map)['ps'] = 0;
      await BootIntro.ensure(wled.client('192.168.29.6'), await caps());
      expect((presetBody(249)['playlist'] as Map)['end'], 250);
      expect(wled.bootPreset, 249);
    });

    test('a power-on look chosen elsewhere becomes the playlist end', () async {
      final c = wled.client('192.168.29.6');
      await BootIntro.ensure(c, await caps());
      (wled.cfg['def'] as Map)['ps'] = 1; // changed in WLED's own page
      expect(await BootIntro.ensure(c, await caps()), isTrue);
      expect((presetBody(249)['playlist'] as Map)['end'], 1);
      expect(wled.bootPreset, 249);
    });

    test('changing the power-on look keeps the intro first', () async {
      final c = wled.client('192.168.29.6');
      await BootIntro.ensure(c, await caps());
      await BootIntro.setPowerOnLook(c, 1);
      expect((presetBody(249)['playlist'] as Map)['ps'], [250]);
      expect((presetBody(249)['playlist'] as Map)['end'], 1);
      expect(wled.bootPreset, 249);
      await BootIntro.setPowerOnLook(c, 0);
      expect((presetBody(249)['playlist'] as Map)['end'], 250);
    });

    test('the intro plays once, then holds the logo', () {
      final g = GlyphIntro();
      final fx = g.create(16, 16, 1);
      final f = Frame(16, 16);
      final params = Params.defaultsFor(g), palette = paletteById(g.defaultPalette);
      var t = 0.0;
      Frame at(double until) {
        while (t < until) {
          fx.render(f, t, 0.05, params, palette);
          t += 0.05;
        }
        return f.copy();
      }

      final first = at(0.1);
      final held = at(GlyphIntro.duration + 1);
      expect(held.rgb.any((v) => v > 0), isTrue);
      expect(held.rgb, isNot(first.rgb));
      // The logo stays put; only its small spark twinkles.
      final later = at(GlyphIntro.duration + 4);
      var changed = 0;
      for (var i = 0; i < 16 * 16; i++) {
        if (later.get(i % 16, i ~/ 16) != held.get(i % 16, i ~/ 16)) changed++;
      }
      expect(changed, lessThan(16), reason: '$changed of 256 pixels changed');
    });

    test('bakes the real intro start to end and holds the logo', () {
      final gif = bakeIntroGif((16, 16));
      expect(gif.sublist(0, 6), ascii.encode('GIF89a'));
      expect(BootIntro.durationDs, ((GlyphIntro.duration + 0.6) * 10).round());
    });
  });

  group('in the app', () {
    Future<DeviceManager> installed() async {
      final c = wled.client('192.168.29.6');
      await BootIntro.ensure(c, await caps());
      final store = DeviceStore(clientFactory: wled.client);
      await store.load();
      final m = DeviceManager(store)..syncHost();
      while (!m.isLoaded || m.isLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return m;
    }

    test('system items are hidden and can\'t be deleted', () async {
      final m = await installed();
      expect(m.bootIntro.installed, isTrue);
      expect(m.powerOnLook, 102);
      expect(keptItems(m).map((p) => p.id), isNot(contains(250)));
      expect(pickable(m).map((p) => p.id), isNot(anyOf(contains(249), contains(250))));
      await expectLater(m.deletePreset(250), throwsA(isA<WledException>()));
      await expectLater(m.deletePreset(249), throwsA(isA<WledException>()));
      await expectLater(m.deleteFile('/glyph-intro.gif'), throwsA(isA<WledException>()));
      expect(wled.deleted, isEmpty);
      expect(wled.presets.containsKey('250'), isTrue);
      m.dispose();
    });

    test('choosing a power-on look updates the playlist end, not def.ps', () async {
      final m = await installed();
      await m.setBootPreset(1);
      expect(wled.bootPreset, 249);
      expect((presetBody(249)['playlist'] as Map)['end'], 1);
      expect(m.powerOnLook, 1);
      m.dispose();
    });

    test('deleting the power-on look makes the intro rest on the logo', () async {
      final m = await installed();
      await m.deletePreset(102);
      expect(wled.presets.containsKey('102'), isFalse);
      expect((presetBody(249)['playlist'] as Map)['end'], 250);
      expect(wled.bootPreset, 249);
      expect(m.powerOnLook, 0);
      m.dispose();
    });
  });

  testWidgets('intro-only power-on is hidden and Routines has a useful empty state', (tester) async {
    (wled.cfg['def'] as Map)['ps'] = 0;
    wled.cfg['timers'] = {'ins': []};
    final devices = DeviceStore(clientFactory: wled.client);
    addTearDown(devices.dispose);
    late DeviceManager manager;
    await tester.runAsync(() async {
      await devices.addAndSelect('fake', 'Test device');
      await BootIntro.ensure(devices.client!, devices.caps!);
      manager = DeviceManager(devices);
      await manager.load();
    });
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(
        body: RoutinesSection(manager: manager))));
    expect(find.textContaining('When it powers on'), findsNothing);
    expect(find.textContaining('Glyph intro'), findsNothing);
    expect(find.textContaining('No routines yet.'), findsOneWidget);
    expect(find.text('Choose a power-on look'), findsOneWidget);
    expect(find.text('New routine'), findsOneWidget);
    expect(manager.bootIntro.installed, isTrue);
    expect(wled.bootPreset, 249);
    expect(tester.takeException(), isNull);
  });

  testWidgets('installs on connect; Device tab hides the system intro and shows only the chosen look', (tester) async {
    tester.view.physicalSize = const Size(360, 740) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final devices = DeviceStore(clientFactory: wled.client);
    final playback = PlaybackController();
    addTearDown(playback.dispose);
    await devices.load();
    await tester.pumpWidget(
      AppScope(
        playback: playback,
        devices: devices,
        catalog: Catalog.parse(File('assets/catalog/starter.json').readAsStringSync()),
        creations: CreationsStore(directory: () async => Directory.systemTemp.createTemp('glyph')),
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: MatrixScreen(services: SetupServices(discover: _none, scan: _none))),
        ),
      ),
    );
    await settle(tester, 1600);
    expect(wled.uploads, contains('/presets.json'));
    expect(wled.bootPreset, 249);
    expect(WledPreset.parseAll(wled.presets).map((p) => p.name), containsAll(['Glyph intro', 'Power-on']));

    final row = find.text('When it powers on → Pipplee');
    await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(find.text('Glyph intro'), findsNothing, reason: 'not a Saved tile');
    expect(find.text('Power-on'), findsNothing, reason: 'not a show');

    // Choose a new power-on look: the intro stays first.
    await tester.tap(row);
    await settle(tester, 600);
    expect(find.text('Glyph intro'), findsNothing, reason: 'not offered in the picker');
    expect(find.text('No saved look'), findsOneWidget);
    await tester.tap(find.text('Ocean Plasma').last);
    await settle(tester, 1600);
    expect(wled.bootPreset, 249);
    expect((presetBody(249)['playlist'] as Map)['end'], 1);
    expect(find.text('When it powers on → Ocean Plasma'), findsOneWidget);

    // Storage doesn't list the intro's file.
    await tester.scrollUntilVisible(find.textContaining('KB used'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('KB used'));
    await settle(tester, 600);
    expect(find.text('ocean-plasma.gif'), findsOneWidget);
    expect(find.text('glyph-intro.gif'), findsNothing);
    expect(tester.takeException(), isNull);
    playback.pause();
  });
}

Stream<Never> _none() => const Stream.empty();

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
