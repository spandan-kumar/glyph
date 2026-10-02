import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/engine/generator.dart';
import 'package:glyph/engine/palette.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/widgets/discover/seasons.dart';

void main() {
  final catalog = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  final starter = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());

  test('size and shape', () {
    expect(catalog.version, Catalog.currentVersion);
    expect(catalog.items.length, greaterThanOrEqualTo(1000));
    expect(catalog.categories.length, greaterThanOrEqualTo(12));
    for (final c in catalog.categories) {
      expect(catalog.inCategory(c).length, greaterThanOrEqualTo(10), reason: c);
    }
    expect(catalog.items.where((i) => i.isPixelArt).length, greaterThanOrEqualTo(300));
  });

  test('ids, titles and looks are unique; tags present', () {
    final ids = catalog.items.map((i) => i.id).toList();
    expect(ids.toSet().length, ids.length);
    final titles = catalog.items.map((i) => i.title.toLowerCase()).toList();
    expect(titles.toSet().length, titles.length);
    final sigs = <String>{};
    for (final i in catalog.items) {
      expect(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(i.id), isTrue, reason: i.id);
      expect(i.tags, isNotEmpty, reason: i.id);
      final keys = i.params.keys.toList()..sort();
      expect(sigs.add('${i.generatorId}|${i.paletteId}|${keys.map((k) => '$k=${i.params[k]}').join(',')}'), isTrue,
          reason: '${i.id} duplicates another look');
    }
  });

  test('every item references a real generator, palette and in-range params', () {
    final palIds = palettes.map((p) => p.id).toSet();
    for (final item in catalog.items) {
      final g = findGenerator(item.generatorId);
      expect(g, isNotNull, reason: '${item.id}: ${item.generatorId}');
      expect(palIds, contains(item.paletteId), reason: item.id);
      final specs = {for (final s in g!.params) s.key: s};
      for (final MapEntry(:key, :value) in item.params.entries) {
        expect(specs.containsKey(key), isTrue, reason: '${item.id}: unknown param $key');
        expect(value, inInclusiveRange(specs[key]!.min, specs[key]!.max), reason: '${item.id}.$key');
      }
      if (item.speed != null) expect(item.speed, inInclusiveRange(0.1, 4));
      expect(catalog.categories, contains(item.category));
    }
  });

  test('every generator and sprite is used', () {
    final used = catalog.items.map((i) => i.generatorId).toSet();
    for (final g in allGenerators) {
      expect(used, contains(g.id));
    }
  });

  test('starter items keep their ids, so saved favourites survive', () {
    for (final s in starter.items) {
      final i = catalog.byId(s.id);
      expect(i, isNotNull, reason: s.id);
      expect(i!.generatorId, s.generatorId);
      expect(i.paletteId, s.paletteId);
      expect(i.params, s.params);
    }
    expect(catalog.items.first.id, starter.items.first.id);
  });

  test('featured shelf and seasonal collections are populated', () {
    expect(catalog.featured.length, greaterThanOrEqualTo(12));
    expect(catalog.featured.map((i) => i.featured).toSet().length, catalog.featured.length);
    for (var m = 1; m <= 12; m++) {
      for (final d in [1, 15, 28]) {
        final s = seasonFor(DateTime(2026, m, d));
        expect(seasonalItems(catalog, s).length, greaterThanOrEqualTo(6), reason: '${s.title} ($m/$d)');
      }
    }
    expect(seasonFor(DateTime(2026, 10, 3)).title, 'Spooky Season');
    expect(seasonFor(DateTime(2026, 12, 31)).tags, contains('new year'));
  });

  test('search ranks title hits first and spans tags and categories', () {
    expect(catalog.search('BLUE flame').first.id, 'blue-flame');
    expect(catalog.search('pizza').first.title, contains('Pizza'));
    expect(catalog.search('halloween').length, greaterThan(20));
    expect(catalog.search('christmas').first.title.toLowerCase(), contains('christmas'));
    expect(catalog.search('food').every((i) => i.category == 'Food & Drink' || i.tags.any((t) => t.contains('food'))), isTrue);
    final heart = catalog.search('heart');
    expect(heart.take(5).every((i) => i.title.toLowerCase().contains('heart')), isTrue);
    expect(catalog.search('qqqzzz'), isEmpty);
  });

  test('a sample of every generator renders the catalogued look', () {
    final seen = <String>{};
    for (final i in catalog.items) {
      if (!seen.add(i.generatorId)) continue;
      final g = generatorById(i.generatorId);
      final inst = g.create(16, 16, 1);
      final f = Frame(16, 16);
      final p = Params.defaultsFor(g, i.params);
      for (var k = 0; k < 60; k++) {
        inst.render(f, k / 30, 1 / 30, p, paletteById(i.paletteId));
      }
    }
  });
}
