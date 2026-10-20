import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/bundled_catalog.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/imported_collection.dart';
import 'package:http/testing.dart';

import 'clip_asset_fixture.dart';

/// Serves real repo assets plus an in-memory private pack.
class _Bundle extends CachingAssetBundle {
  _Bundle([this.pack = const {}]);
  final Map<String, List<int>> pack;
  @override
  Future<ByteData> load(String key) async {
    final bytes = pack[key];
    if (bytes != null) return ByteData.sublistView(Uint8List.fromList(bytes));
    if (key.startsWith('$privatePackDir/')) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

const _permission = 'maintainer-confirmed-collection-consent-2026-10-13';

List<dynamic> _row(ClipAsset asset, int id, String title, String category) => [
  id, asset.sha256, asset.bytes, asset.width, asset.height, asset.frames,
  ['red'], title, ['boat'], ['$title Alias'], ['water', 'rocking'], category,
];

void main() {
  final (boat, boatBytes) = clipFixture(id: 7);
  final (cat, catBytes) = clipFixture(id: 8, colours: [0xffffff]);
  Map<String, dynamic> index({String? notice}) => {
    'version': 3,
    'count': 2,
    'permission': _permission,
    'categories': ['Water', 'Animals'],
    'notice': ?notice,
    'rows': [
      _row(boat, 7, 'Rocking Sailboat', 'Water'),
      _row(cat, 8, 'White Cat', 'Animals'),
    ],
  };
  Map<String, List<int>> pack({String? notice}) => {
    importedIndexAsset: utf8.encode(jsonEncode(index(notice: notice))),
    privateClipAsset(boat.sha256): boatBytes,
    privateClipAsset(cat.sha256): catBytes,
  };
  final base = Catalog.parse(File(bundledCatalogAsset).readAsStringSync());

  test('without a private pack the library is the base catalog only', () async {
    expect(await loadPrivateCollection(_Bundle()), isNull);
    final all = await loadBundledCatalog(_Bundle());
    expect(all.items.length, base.items.length);
    expect(all.items.length, 1236);
    expect(all.items.where((i) => i.asset?.type == 'clip-gzip'), isEmpty);
    expect(all.items.where((i) => i.collection == 'Imported'), isEmpty);
  });

  test('a private pack adds its items and loads clips from the pack', () async {
    final bundle = _Bundle(pack());
    final all = await loadBundledCatalog(bundle);
    expect(all.items.length, base.items.length + 2);
    for (final item in base.items) {
      expect(all.byId(item.id)!.toJson(), item.toJson());
    }
    final item = all.byId('imported-7')!;
    expect(item.title, 'Rocking Sailboat');
    expect(item.category, 'Water');
    expect(item.collection, 'Imported');
    expect(item.isPixelArt, isTrue);
    expect(item.notice, isNull, reason: 'no credit line unless the pack has one');
    expect(all.byId('clip:imported-7'), same(item));
    expect(findGenerator(item.generatorId), isA<AssetClipGenerator>());
    expect(all.search('white cat').map((i) => i.id), contains('imported-8'));
    expect(all.search('collection:imported imported-8').single.id, 'imported-8');

    final store = ClipAssetStore(
      bundle: bundle,
      cacheDir: () async => throw StateError('Fresh install: no cache'),
      client: MockClient((_) async => throw StateError('Offline: no network')),
    );
    addTearDown(store.close);
    addTearDown(ClipAssetLibrary.clearCache);
    final clip = await store.load(ClipAssetLibrary.byId(item.generatorId)!.asset);
    expect(clip.frames.length, boat.frames);
  });

  test('the credit line comes from the pack when it has one', () {
    final c = parseImportedCollection(jsonEncode(index(notice: ' Thanks! ')));
    expect(c.items.map((i) => i.notice).toSet(), {'Thanks!'});
    for (final bad in ['', 'x' * 201]) {
      expect(
        () => parseImportedCollection(jsonEncode(index(notice: bad))),
        throwsFormatException,
      );
    }
  });

  test('an unreadable pack is ignored and the base catalog stays', () async {
    final all = await loadBundledCatalog(_Bundle({
      importedIndexAsset: utf8.encode('{"version": 3, "rows": ['),
    }));
    expect(all.items.length, base.items.length);
  });

  test('categorized schema rejects undeclared groups before registration', () {
    parseImportedCollection(jsonEncode(index()));
    final doc = index();
    final row = List<dynamic>.of((doc['rows'] as List).first as List);
    row[7] = 'Rejected name';
    row[11] = 'Undeclared group';
    doc['rows'] = [row];
    doc['count'] = 1;
    expect(() => parseImportedCollection(jsonEncode(doc)), throwsFormatException);
    expect(findGenerator('clip:imported-7')!.name, 'Rocking Sailboat');
    row[11] = 'Water';
    doc['categories'] = ['Water', 'Water'];
    expect(() => parseImportedCollection(jsonEncode(doc)), throwsFormatException);
  });

  test('malformed or duplicate entries are rejected before registration', () {
    final doc = index();
    final rows = doc['rows'] as List;
    doc['rows'] = [rows.first, rows.first];
    expect(() => parseImportedCollection(jsonEncode(doc)), throwsFormatException);
    final wrongPermission = index()..['permission'] = 'CC0';
    expect(
      () => parseImportedCollection(jsonEncode(wrongPermission)),
      throwsFormatException,
    );
  });

  test('named schema validates its search words', () {
    final row = _row(boat, 7, 'Sailboat Review Fixture', 'Water').take(11).toList();
    final doc = {'version': 2, 'count': 1, 'permission': _permission, 'rows': [row]};
    final named = parseImportedCollection(jsonEncode(doc));
    final item = named.items.single;
    expect(item.id, 'imported-7');
    expect(item.asset!.extra['sha256'], boat.sha256);
    expect(item.asset!.extra['bytes'], boat.bytes);
    expect(named.search('boat rocking').single.id, item.id);
    expect(named.search('sailboat review fixture alias').single.id, item.id);
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
        () => parseImportedCollection(jsonEncode({...doc, 'rows': [broken]})),
        throwsFormatException,
      );
      expect(
        findGenerator(item.generatorId)!.name,
        item.title,
        reason: 'a rejected index cannot replace registered metadata',
      );
    }
  });

  test('the original schema still loads its records', () {
    final row = _row(boat, 7, 'unused', 'Water').take(7).toList();
    final doc = {'version': 1, 'count': 1, 'permission': _permission, 'rows': [row]};
    final legacy = parseImportedCollection(jsonEncode(doc));
    expect(legacy.items.single.title, 'Imported 7');
    expect(legacy.items.single.subjects, isEmpty);
    expect(legacy.search('7').single.id, 'imported-7');
  });
}
