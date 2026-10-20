import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/library/bundled_catalog.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/imported_collection.dart';
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app bundles clips only from a private pack, and all of them', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final clips =
        manifest.listAssets().where((s) => s.endsWith('.clip.gz')).toSet();
    expect(ClipAssetStore.shared.bundle, same(rootBundle));
    if (!manifest.listAssets().contains(importedIndexAsset)) {
      // Public builds: no collection index, no clip files, nothing to load.
      expect(clips, isEmpty);
      expect(await loadPrivateCollection(rootBundle), isNull);
      return;
    }
    // A private build with the pack dropped in: every clip ships offline.
    final catalog = parseImportedCollection(
      await rootBundle.loadString(importedIndexAsset),
    );
    expect(clips, {
      for (final item in catalog.items)
        privateClipAsset(ClipAssetLibrary.byId(item.generatorId)!.asset.sha256),
    });
    final store = ClipAssetStore(
      bundle: rootBundle,
      cacheDir: () async => throw StateError('Fresh install: no cache'),
      client: MockClient((_) async => throw StateError('Offline: no network')),
    );
    addTearDown(store.close);
    addTearDown(ClipAssetLibrary.clearCache);
    final rows =
        (jsonDecode(await rootBundle.loadString(importedIndexAsset))
                as Map)['rows']
            as List;
    rows.sort((a, b) => (a[2] as int).compareTo(b[2] as int));
    for (final row in [rows.first, rows[rows.length ~/ 2], rows.last]) {
      ClipAssetLibrary.clearCache();
      final asset = ClipAssetLibrary.byId('clip:imported-${row[0]}')!.asset;
      final clip = await store.load(asset);
      expect(clip.frames.length, asset.frames);
    }
  });
}
