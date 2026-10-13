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
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/pipplee_collection.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clips extends ClipAssetStore {
  _Clips() : super(cacheDir: () async => Directory.systemTemp);
  final ready = Completer<FrameClip>();
  final requested = <String>[];
  @override
  Future<FrameClip> load(ClipAsset asset) {
    requested.add(asset.id);
    return ready.future;
  }
}

void main() {
  final original = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  final collection = parsePippleeCollection(File(pippleeIndexAsset).readAsStringSync());
  final catalog = original.merge(collection);

  test('the full collection has a lead rail and retains every browsable entry', () {
    final channels = CatalogChannels(catalog, DateTime(2026, 10, 13));
    final rail = channels.lead.singleWhere((c) => c.id == 'pipplee');
    expect(rail.items.length, 30);
    expect(rail.all.length, 12361);
    expect(channels.rest.where((c) => c.name == 'Pipplee'), isEmpty);
  });

  testWidgets('full library search downloads only its visible pick and plays it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    ClipAssetLibrary.clearCache();
    final previous = ClipAssetStore.shared, store = _Clips();
    ClipAssetStore.shared = store;
    final dir = Directory.systemTemp.createTempSync('glyph-pipplee-ui');
    final playback = PlaybackController(), devices = DeviceStore();
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
    await tester.enterText(find.byType(TextField), item.title);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(store.requested.toSet(), {item.generatorId});
    await tester.tap(find.text(item.title).last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(playback.loadingTitle, item.title);
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
    expect(tester.takeException(), isNull);
    playback.pause();
    await tester.pumpWidget(const SizedBox());
  });
}
