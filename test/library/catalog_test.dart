import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';

void main() {
  final source = File('assets/catalog/starter.json').readAsStringSync();
  final catalog = Catalog.parse(source);

  test('starter catalog shape', () {
    expect(catalog.version, 1);
    expect(catalog.items.length, greaterThanOrEqualTo(90));
    expect(catalog.categories.length, greaterThanOrEqualTo(6));
    for (final c in catalog.categories) {
      expect(catalog.inCategory(c), isNotEmpty, reason: c);
    }
  });

  test('ids and titles are unique', () {
    final ids = catalog.items.map((i) => i.id).toList();
    expect(ids.toSet().length, ids.length);
    final titles = catalog.items.map((i) => i.title.toLowerCase()).toList();
    expect(titles.toSet().length, titles.length);
    for (final id in ids) {
      expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id), isTrue, reason: id);
    }
  });

  test('every item points at a real generator, palette and params', () {
    final genIds = {for (final g in generators) g.id: g};
    final palIds = palettes.map((p) => p.id).toSet();
    for (final item in catalog.items) {
      final g = genIds[item.generatorId];
      expect(g, isNotNull, reason: '${item.id}: ${item.generatorId}');
      expect(palIds, contains(item.paletteId), reason: item.id);
      final specs = {for (final s in g!.params) s.key: s};
      for (final MapEntry(:key, :value) in item.params.entries) {
        expect(specs.containsKey(key), isTrue, reason: '${item.id}: unknown param $key');
        final s = specs[key]!;
        expect(value, inInclusiveRange(s.min, s.max), reason: '${item.id}.$key');
      }
      if (item.speed != null) {
        expect(item.speed, inInclusiveRange(0.1, 4), reason: item.id);
      }
      expect(item.title.trim(), isNotEmpty);
      expect(catalog.categories, contains(item.category));
    }
  });

  test('variations are not duplicates of each other', () {
    final seen = <String>{};
    for (final i in catalog.items) {
      final keys = i.params.keys.toList()..sort();
      final sig = '${i.generatorId}|${i.paletteId}|'
          '${keys.map((k) => '$k=${i.params[k]}').join(',')}';
      expect(seen.add(sig), isTrue, reason: '${i.id} duplicates another item');
    }
  });

  test('search and categories', () {
    expect(catalog.search('').length, catalog.items.length);
    final fire = catalog.search('flame');
    expect(fire, isNotEmpty);
    expect(catalog.search('BLUE flame').first.id, 'blue-flame');
    expect(catalog.search('diwali').map((i) => i.id).toList(), contains('diwali-fireworks'));
    expect(catalog.search('zzzz-nothing'), isEmpty);
    // Title matches rank above tag-only matches.
    final xmas = catalog.search('christmas');
    expect(xmas.first.title.toLowerCase(), contains('christmas'));
  });

  test('json round-trip, including future fields', () {
    final again = Catalog.fromJson(catalog.toJson());
    expect(again.items.length, catalog.items.length);
    expect(again.categories, catalog.categories);
    expect(again.items.first.toJson(), catalog.items.first.toJson());

    final future = Catalog.parse('''
{
  "version": 2,
  "categories": ["Pixel Art"],
  "items": [
    {"id": "cat", "title": "Pixel Cat", "category": "Pixel Art",
     "generator": "plasma", "palette": "rainbow", "speed": 1.5,
     "asset": {"type": "gif", "url": "https://example.com/cat.gif",
               "license": "CC-BY-4.0", "author": "Someone", "frames": 12}},
    {"id": "new", "title": "New Thing", "category": "Brand New",
     "generator": "fire", "palette": "lava"}
  ]
}''');
    expect(future.version, 2);
    expect(future.categories, ['Pixel Art', 'Brand New']);
    final cat = future.byId('cat')!;
    expect(cat.speed, 1.5);
    expect(cat.params, isEmpty);
    expect(cat.asset!.type, 'gif');
    expect(cat.asset!.license, 'CC-BY-4.0');
    expect(cat.asset!.toJson()['frames'], 12);
    expect(LibraryItem.fromJson(cat.toJson()).asset!.url, cat.asset!.url);

    final merged = catalog.merge(future);
    expect(merged.items.length, catalog.items.length + 2);
    expect(merged.categories.take(catalog.categories.length).toList(), catalog.categories);
    expect(merged.categories, containsAll(['Pixel Art', 'Brand New']));
  });
}
