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
        expect(item.title.startsWith('Pipplee '), isFalse);
        expect(item.subjects, isNotEmpty);
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
        expect(asset.sha256, record['clip_sha256']);
        expect(asset.width, record['width']);
        expect(asset.height, record['height']);
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
    expect(all.items.where((i) => i.collection == 'Imported').length, 12361);
    expect(all.inCategory('Pipplee'), isEmpty);
    for (final item in old.items) {
      expect(all.byId(item.id)!.toJson(), item.toJson());
    }
    expect(all.search('imported red'), isNotEmpty);
  });

  test('reviewed sample names and subject aliases are searchable in the full library', () {
    final all = Catalog.parse(File(bundledCatalogAsset).readAsStringSync())
        .merge(collection);
    final queries = {
      'boat': 17315,
      'neon alien': 16050,
      'pink flower': 5146,
      'blue robot': 8751,
      'rainbow circle': 12045,
      'rgb grid': 12394,
      'white cat': 15353,
      'yellow bandage': 16704,
    };
    for (final entry in queries.entries) {
      expect(
        all.search(entry.key).map((i) => i.id),
        contains('pipplee-${entry.value}'),
        reason: entry.key,
      );
    }
  });

  test('curated subjects stay bound to the correct source clip', () {
    expect(
      collection.search('duck sunglasses').map((i) => i.id),
      contains('pipplee-5307'),
    );
    expect(
      collection.search('duck rail').map((i) => i.id),
      contains('pipplee-8431'),
    );
    expect(
      collection.search('red robot head').map((i) => i.id),
      contains('pipplee-8473'),
    );
    expect(
      collection.search('white cyan bar').map((i) => i.id),
      contains('pipplee-8336'),
    );
    expect(collection.byId('pipplee-5307')!.subjects, isNot(contains('skull')));
    expect(collection.byId('pipplee-8431')!.subjects, isNot(contains('love')));
    expect(
      collection.byId('pipplee-8336')!.subjects,
      isNot(contains('pumpkin')),
    );
  });

  test('categorized clips retain collection credit and join subject groups', () {
    expect(collection.byId('pipplee-17315')!.category, 'Water');
    expect(collection.byId('pipplee-15353')!.category, 'Animals');
    expect(collection.byId('pipplee-5146')!.category, 'Nature');
    expect(collection.byId('pipplee-12045')!.category, 'Abstract');
    expect(collection.items.every((i) => i.collection == 'Imported'), isTrue);
    expect(collection.categories, isNot(contains('Pipplee')));
    final item = collection.byId('pipplee-15353')!;
    expect(collection.search('collection:imported ${item.id}').single.id, item.id);
    expect(collection.search('collection:animals ${item.id}'), isEmpty);
  });

  test('categorized schema rejects undeclared groups before registration', () {
    final doc = jsonDecode(source) as Map<String, dynamic>;
    final row = List<dynamic>.of((doc['rows'] as List).first as List);
    final originalName = collection.items.first.title;
    row[7] = 'Rejected name';
    row[11] = 'Undeclared group';
    doc['rows'] = [row];
    doc['count'] = 1;
    expect(() => parsePippleeCollection(jsonEncode(doc)), throwsFormatException);
    expect(findGenerator(collection.items.first.generatorId)!.name, originalName);
    row[11] = (doc['categories'] as List).first;
    doc['categories'] = [row[11], row[11]];
    expect(() => parsePippleeCollection(jsonEncode(doc)), throwsFormatException);
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

  test(
    'named schema preserves content identities and adds reviewed search words',
    () {
      final original = (jsonDecode(source) as Map)['rows'].first as List;
      final row = [
        ...original.take(7),
        'Sailboat Review Fixture',
        ['boat', 'sailboat'],
        ['Sailing Boat Review Fixture'],
        ['water', 'rocking'],
      ];
      final doc = {
        'version': 2,
        'count': 1,
        'permission': 'maintainer-confirmed-pipplee-consent-2026-10-13',
        'rows': [row],
      };
      addTearDown(() => parsePippleeCollection(source));
      final named = parsePippleeCollection(jsonEncode(doc));
      final item = named.items.single;
      expect(item.id, 'pipplee-${original[0]}');
      expect(item.asset!.extra['sha256'], original[1]);
      expect(item.asset!.extra['bytes'], original[2]);
      expect(item.title, 'Sailboat Review Fixture');
      expect(named.search('boat rocking').single.id, item.id);
      expect(named.search('sailing boat review fixture').single.id, item.id);
      expect(named.search(item.id).single.id, item.id);
      for (final broken in [
        [...row]..[7] = '',
        [...row]..[7] = 'x' * 81,
        [...row]..[8] = [],
        [...row]..[8] = ['x' * 65],
        [...row]..[9] = [false],
        [...row]..[9] = List.filled(9, 'alias'),
        [...row]..[10] = [],
        [...row]..[10] = ['bad\nword'],
      ]) {
        expect(
          () => parsePippleeCollection(
            jsonEncode({
              ...doc,
              'rows': [broken],
            }),
          ),
          throwsFormatException,
        );
        expect(
          findGenerator(item.generatorId)!.name,
          item.title,
          reason: 'a rejected index cannot replace registered metadata',
        );
      }
    },
  );

  test('legacy schema still loads its exact source records', () {
    final original = (jsonDecode(source) as Map)['rows'].first as List;
    final doc = {
      'version': 1,
      'count': 1,
      'permission': 'maintainer-confirmed-pipplee-consent-2026-10-13',
      'rows': [original.take(7).toList()],
    };
    addTearDown(() => parsePippleeCollection(source));
    final legacy = parsePippleeCollection(jsonEncode(doc));
    expect(legacy.items.single.title, 'Pipplee ${original[0]}');
    expect(legacy.items.single.subjects, isEmpty);
    expect(legacy.search('${original[0]}').single.id, 'pipplee-${original[0]}');
  });
}
