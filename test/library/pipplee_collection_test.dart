import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/bundled_catalog.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_manifest.dart';
import 'package:glyph/library/pipplee_collection.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(File(key).readAsBytesSync());
}

void main() {
  final source = File(pippleeIndexAsset).readAsStringSync();
  final collection = parsePippleeCollection(source);

  test(
    'all 12,361 source IDs are present, with permission and working generators',
    () {
      final provenance = jsonDecode(
        File('catalog_assets/pipplee/provenance.json').readAsStringSync(),
      ) as Map;
      final sourceIds = {
        for (final row in provenance['entries'] as List) 'pipplee-${row['id']}',
      };
      expect(collection.items.length, 12361);
      expect(collection.items.map((i) => i.id).toSet(), sourceIds);
      expect(collection.items.map((i) => i.title).toSet().length, 12361);
      for (final item in collection.items) {
        expect(findGenerator(item.generatorId), isA<AssetClipGenerator>());
        expect(item.asset!.license, 'shared-with-permission');
        expect(item.notice, pippleeNotice);
        expect(item.isPixelArt, isTrue);
      }
    },
  );

  test(
    'every unique clip hash, header, frame count and full timing is valid',
    () {
      final checked = <String>{};
      final provenance = jsonDecode(
        File('catalog_assets/pipplee/provenance.json').readAsStringSync(),
      ) as Map;
      final records = {
        for (final row in provenance['entries'] as List) row['id'] as int: row,
      };
      for (final item in collection.items) {
        final asset = ClipAssetLibrary.byId(item.generatorId)!.asset;
        final record =
            records[int.parse(item.id.substring('pipplee-'.length))]!;
        expect(asset.frames, record['frames']);
        if (!checked.add(asset.sha256)) continue;
        final bytes = File('catalog_assets/pipplee/${asset.sha256}.clip.gz')
            .readAsBytesSync();
        expect(bytes.length, asset.bytes);
        expect(CatalogManifest.sha256Hex(bytes), asset.sha256);
        final raw = Uint8List.fromList(gzip.decode(bytes));
        final clip = decodeClipAsset(raw, asset);
        expect(clip.totalMs, record['duration_ms']);
        expect(clip.frames.length, asset.frames);
      }
    },
  );

  test('bundled loading retains the existing library and adds every collection item', () async {
    final old = Catalog.parse(File(bundledCatalogAsset).readAsStringSync());
    final all = await loadBundledCatalog(_Bundle());
    expect(all.items.length, old.items.length + 12361);
    expect(all.inCategory('Pipplee').length, 12361);
    for (final item in old.items) {
      expect(all.byId(item.id)!.toJson(), item.toJson());
    }
    expect(all.search('pipplee red'), isNotEmpty);
  });

  test('malformed or duplicate entries are rejected before registration', () {
    final doc = jsonDecode(source) as Map<String, dynamic>;
    final rows = doc['rows'] as List;
    doc['rows'] = [rows.first, rows.first];
    doc['count'] = 2;
    expect(
      () => parsePippleeCollection(jsonEncode(doc)),
      throwsFormatException,
    );
    doc['permission'] = 'CC0';
    expect(
      () => parsePippleeCollection(jsonEncode(doc)),
      throwsFormatException,
    );
  });
}
