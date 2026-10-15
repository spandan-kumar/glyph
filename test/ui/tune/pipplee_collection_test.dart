import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/features/device/boot_intro.dart';
import 'package:glyph/wled/layout.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/pipplee_collection.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/device/fake_wled.dart';

class _Clips extends ClipAssetStore {
  _Clips() : super(cacheDir: () async => Directory.systemTemp);
  final ready = Completer<FrameClip>();
  final requested = <String>[];
  bool playbackPriority = false;
  @override
  Future<FrameClip> load(ClipAsset asset, {bool priority = false}) {
    requested.add(asset.id);
    if (priority) playbackPriority = true;
    return ready.future;
  }
}

class _Playback extends PlaybackController {
  final started = <String>[];
  @override
  Future<void> startStreaming(String host, MatrixLayout layout) async => started.add(host);
}

void main() {
  final original = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  final collection = parsePippleeCollection(File(pippleeIndexAsset).readAsStringSync());
  final catalog = original.merge(collection);

  test('every imported entry belongs to subject groups without a source shelf', () {
    final channels = CatalogChannels(catalog, DateTime(2026, 10, 13));
    final groups = [...channels.lead, ...channels.rest];
    expect(groups.where((c) => c.name == 'Pipplee' || c.id == 'pipplee'), isEmpty);
    final grouped = {for (final group in groups) ...group.all.map((e) => e.key)};
    expect(grouped, containsAll(collection.items.map((i) => 'i:${i.id}')));
    expect(collection.items.any((i) => i.category == 'Pipplee'), isFalse);
    for (final name in ['Flags', 'Patterns', 'Hypnotic']) {
      final group = groups.singleWhere((c) => c.name == name);
      expect(group.all.whereType<ItemEntry>().any((e) => e.item.collection == 'Imported'), isTrue);
    }
    expect(channels.allChannel.all.length, catalog.items.length);
    final importedCat = collection.byId('pipplee-15353')!;
    expect(channels.rest.singleWhere((c) => c.name == 'Animals').all.map((e) => e.key),
        contains('i:${importedCat.id}'));
    final grid = collection.byId('pipplee-12045')!;
    expect(channels.rest.singleWhere((c) => c.name == 'Abstract').all.map((e) => e.key),
        contains('i:${grid.id}'));
  });

  testWidgets('full library search downloads only its visible pick and plays it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ClipAssetLibrary.clearCache();
    final previous = ClipAssetStore.shared, store = _Clips();
    ClipAssetStore.shared = store;
    final dir = Directory.systemTemp.createTempSync('glyph-pipplee-ui');
    BootIntro.autoInstall = false;
    addTearDown(BootIntro.resetForTest);
    final wled = FakeWled();
    final playback = _Playback(), devices = DeviceStore(clientFactory: wled.client);
    await tester.runAsync(() => devices.addAndSelect('fake', 'Test device'));
    addTearDown(() {
      playback.dispose();
      devices.dispose();
      ClipAssetStore.shared = previous;
      store.close();
      ClipAssetLibrary.clearCache();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(GlyphApp(catalog: catalog, devices: devices, playback: playback,
      creations: CreationsStore(directory: () async => dir)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(store.requested, isEmpty);
    await tester.tap(find.byTooltip('Search'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final item = collection.items.firstWhere((i) => int.parse(i.id.substring(8)) > 10000);
    await tester.enterText(find.byType(TextField), item.id);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(store.requested.toSet(), {item.generatorId});
    await tester.tap(find.text(item.title).last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(playback.loadingTitle, item.title);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(TextField), findsNothing, reason: 'search is disposed before loading finishes');
    expect(store.playbackPriority, true);
    final asset = ClipAssetLibrary.byId(item.generatorId)!.asset;
    final clip = decodeClipAsset(Uint8List.fromList(gzip.decode(
      File('catalog_assets/pipplee/${asset.sha256}.clip.gz').readAsBytesSync())), asset);
    ClipAssetLibrary.retain(asset.sha256, clip);
    store.ready.complete(clip);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(playback.item?.id, item.id);
    expect(playback.generator, isA<ClipGenerator>());
    expect(playback.loadingTitle, isNull);
    expect(playback.started, ['fake'], reason: 'streaming starts even after the tile was disposed');
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
