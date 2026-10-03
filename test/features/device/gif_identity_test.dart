import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/gif_encoder.dart';
import 'package:glyph/features/device/device_manager.dart';
import 'package:glyph/features/device/widgets/common.dart';
import 'package:glyph/features/device/widgets/kept.dart';
import 'package:glyph/features/device/widgets/storage.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/ui/widgets/led_matrix_view.dart';
import 'package:glyph/wled/device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_wled.dart';

/// Regression: after deleting files or saved items, every tile must still
/// show its own animation (a real device showed names over the wrong GIFs).
void main() {
  late FakeWled wled;

  // One colour per file, so a tile's picture says which file it came from.
  const colours = {
    '/ocean-plasma.gif': 0xFF0000,
    '/pipplee.gif': 0x00FF00,
    '/duck.gif': 0x0000FF,
    '/goose.gif': 0xFFFF00,
    '/mypaint.gif': 0xFF00FF,
  };

  setUp(() {
    wled = FakeWled();
    for (final (id, name, file) in const [(3, 'Duck', 'duck.gif'), (4, 'Goose', 'goose.gif'), (5, 'My paint', 'mypaint.gif')]) {
      wled.presets['$id'] = {
        'on': true,
        'n': name,
        'seg': [
          {'id': 0, 'n': file, 'fx': 53},
        ],
      };
    }
    for (final MapEntry(key: path, value: c) in colours.entries) {
      wled.gifs[path] = encodeGif([Frame(1, 1)..set(0, 0, c)], [100]);
    }
    SharedPreferences.setMockInitialValues({
      'devices.v1': jsonEncode([const SavedDevice(host: '192.168.29.6', name: 'Matrix').toJson()]),
      'devices.selected': '192.168.29.6',
    });
  });

  Future<DeviceManager> pump(WidgetTester tester, Widget Function(DeviceStore, DeviceManager) build) async {
    tester.view.physicalSize = const Size(360, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = DeviceStore(clientFactory: wled.client);
    await store.load();
    final manager = DeviceManager(store)..syncHost();
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: Listenable.merge([store, manager]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [build(store, manager)],
            ),
          ),
        ),
      ),
    );
    await decode(tester);
    return manager;
  }

  /// What each Saved tile shows: name → colour of its picture (null when
  /// it shows no animation).
  Map<String, int?> tiles(WidgetTester tester) => {
    for (final e in find.byType(KeptTile).evaluate())
      (e.widget as KeptTile).preset.name: () {
        final views = find.descendant(of: find.byWidget(e.widget), matching: find.byType(LedMatrixView));
        if (views.evaluate().isEmpty) return null;
        return tester.widget<LedMatrixView>(views.first).frame.get(0, 0);
      }(),
  };

  bool missing(String name) => find
      .descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(KeptTile)),
        matching: find.text('FILE MISSING'),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('Saved tiles keep their own animation when one in the middle is deleted', (tester) async {
    await pump(tester, (s, m) => KeptSection(manager: m, store: s, onPlay: (_) async {}));
    expect(tiles(tester), {
      'Ocean Plasma': 0xFF0000,
      'Duck': 0x0000FF,
      'Goose': 0xFFFF00,
      'My paint': 0xFF00FF,
      'Pipplee': 0x00FF00,
    });

    // Delete Goose (and its file) from the middle of the grid.
    await tester.longPress(find.text('Goose'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester, 800);
    await decode(tester);
    expect(wled.deleted, ['/goose.gif']);
    expect(tiles(tester), {
      'Ocean Plasma': 0xFF0000,
      'Duck': 0x0000FF,
      'My paint': 0xFF00FF,
      'Pipplee': 0x00FF00,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting files leaves the other tiles right and marks the missing ones', (tester) async {
    final manager = await pump(tester, (s, m) => KeptSection(manager: m, store: s, onPlay: (_) async {}));
    await manager.deleteFile('/duck.gif');
    await settle(tester, 800);
    await decode(tester);
    await manager.deleteFile('/ocean-plasma.gif');
    await settle(tester, 800);
    await decode(tester);
    expect(tiles(tester), {
      'Ocean Plasma': null,
      'Duck': null,
      'Goose': 0xFFFF00,
      'My paint': 0xFF00FF,
      'Pipplee': 0x00FF00,
    });
    expect(missing('Duck'), isTrue);
    expect(missing('Ocean Plasma'), isTrue);
    expect(missing('Goose'), isFalse);

    // A missing one doesn't try to play; its menu offers Delete.
    final played = <int>[];
    await tester.pumpWidget(const SizedBox());
    await pump(tester, (s, m) => KeptSection(manager: m, store: s, onPlay: (id) async => played.add(id)));
    await tester.tap(find.text('Duck'));
    await settle(tester);
    expect(played, isEmpty);
    expect(find.textContaining('animation file is gone'), findsOneWidget);
    expect(find.text('Play now'), findsNothing);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file sent again under the same name shows the new animation', (tester) async {
    final manager = await pump(tester, (s, m) => KeptSection(manager: m, store: s, onPlay: (_) async {}));
    expect(tiles(tester)['Duck'], 0x0000FF);
    // Replaced on the device (e.g. sent again from Display).
    wled.gifs['/duck.gif'] = encodeGif([Frame(1, 1)..set(0, 0, 0x00FFFF)], [100]);
    final entry = wled.files.firstWhere((f) => f['name'] == 'duck.gif');
    entry['size'] = (entry['size'] as int) + 1;
    await manager.reloadPresets(settle: false);
    await settle(tester);
    await decode(tester);
    expect(tiles(tester)['Duck'], 0x00FFFF);
  });

  testWidgets('Storage rows keep their own animation, and deleting a used file warns', (tester) async {
    final manager = await pump(tester, (s, m) => StorageSection(manager: m, store: s));
    await tester.tap(find.textContaining('KB used'));
    await settle(tester, 600);
    await decode(tester);
    expect(find.byType(StoragePage), findsOneWidget);
    Map<String, int?> rows() => {
      for (final e in find.byType(GifThumb).evaluate())
        (e.widget as GifThumb).name: () {
          final v = find.descendant(of: find.byWidget(e.widget), matching: find.byType(LedMatrixView));
          return v.evaluate().isEmpty ? null : tester.widget<LedMatrixView>(v.first).frame.get(0, 0);
        }(),
    };
    for (final MapEntry(:key, :value) in rows().entries) {
      expect(value, colours[key], reason: key);
    }
    final gone = manager.deleteFile('/pipplee.gif');
    await settle(tester, 800);
    await tester.runAsync(() => gone);
    await decode(tester);
    expect(rows().keys, isNot(contains('/pipplee.gif')));
    for (final MapEntry(:key, :value) in rows().entries) {
      expect(value, colours[key], reason: key);
    }

    // Ocean Plasma uses ocean-plasma.gif: deleting it says so.
    final row = find.ancestor(of: find.text('ocean-plasma.gif'), matching: find.byType(Row1));
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Delete')));
    await settle(tester);
    expect(find.text('“Ocean Plasma” uses this file — it will stop working.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Lets GIF decoding (an isolate) finish, then draws.
Future<void> decode(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await settle(tester, 200);
  }
}

Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}
