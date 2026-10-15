import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/pipplee_collection.dart';
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every collection clip ships in the app and loads on a fresh offline install', () async {
    final catalog = parsePippleeCollection(
      await rootBundle.loadString(pippleeIndexAsset),
    );
    final expected = {
      for (final item in catalog.items)
        'catalog_assets/pipplee/${ClipAssetLibrary.byId(item.generatorId)!.asset.sha256}.clip.gz',
    };
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(
      manifest.listAssets().where((s) => s.endsWith('.clip.gz')).toSet(),
      expected,
    );
    expect(expected.length, 12273);
    expect(ClipAssetStore.shared.bundle, same(rootBundle));

    final store = ClipAssetStore(
      bundle: rootBundle,
      cacheDir: () async => throw StateError('Fresh install: no cache'),
      client: MockClient((_) async => throw StateError('Offline: no network')),
    );
    addTearDown(store.close);
    addTearDown(ClipAssetLibrary.clearCache);
    final rows =
        (jsonDecode(await rootBundle.loadString(pippleeIndexAsset))
                as Map)['rows']
            as List;
    rows.sort((a, b) => (a[2] as int).compareTo(b[2] as int));
    for (final row in [rows.first, rows[rows.length ~/ 2], rows.last]) {
      ClipAssetLibrary.clearCache();
      final asset = ClipAssetLibrary.byId('clip:pipplee-${row[0]}')!.asset;
      final clip = await store.load(asset);
      expect(clip.frames.length, asset.frames);
      expect(clip.width, asset.width);
      expect(clip.height, asset.height);
    }
  });
}
