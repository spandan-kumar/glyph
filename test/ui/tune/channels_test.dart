import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/frame.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/tune/channels.dart';

LibraryItem _item(String id, String category, {String? collection, List<String> tags = const []}) =>
    LibraryItem(id: id, title: id, category: category, generatorId: 'sprite:$id',
        paletteId: 'rainbow', collection: collection, tags: tags);

void main() {
  final now = DateTime(2026, 10, 14);

  test('All leads every home group and retains the whole library and creations', () {
    final catalog = Catalog(items: [
      for (var i = 0; i < 40; i++) _item('cat-$i', 'Animals'),
      _item('grid', 'Abstract', collection: 'Imported'),
    ]);
    final creation = Creation(id: 'mine', title: 'My drawing', kind: 'drawing',
        clip: FrameClip(width: 1, height: 1, frames: [Frame(1, 1)], delaysMs: [100]),
        updatedAt: now);
    final channels = assembleChannels(base: CatalogChannels(catalog, now),
        favourites: ['cat-0'], recents: ['cat-0', 'grid'], creations: [creation]);
    final all = channels.first;
    expect(all.id, 'all');
    expect(all.name, 'All');
    expect(all.items.length, 30);
    expect(all.all.map((e) => e.key).toSet(), {
      for (final i in catalog.items) 'i:${i.id}', 'c:mine',
    });
    expect(all.all.length, catalog.items.length + 1);
    expect(all.items.map((e) => e.key), contains('i:grid'), reason: 'preview includes different categories');
    expect(all.expanded().items.length, 42);
    expect(channels[1].id, 'now');
    expect(channels.where((c) => c.id == 'all'), hasLength(1));
  });

  test('imports join subject rails without a source shelf or abstract Pixel Pals', () {
    final cat = _item('cat', 'Animals', collection: 'Imported');
    final grid = _item('grid', 'Abstract', collection: 'Imported', tags: ['cute']);
    final heart = _item('heart', 'Love', collection: 'Imported');
    final base = CatalogChannels(Catalog(items: [cat, grid, heart]), now);
    expect([...base.lead, ...base.rest].where((c) => c.name == 'Imported'), isEmpty);
    expect(base.rest.singleWhere((c) => c.name == 'Animals').all.single.key, 'i:cat');
    expect(base.rest.singleWhere((c) => c.name == 'Abstract').all.single.key, 'i:grid');
    expect(base.rest.singleWhere((c) => c.name == 'Love').all.single.key, 'i:heart');
    expect(base.lead.singleWhere((c) => c.id == 'pals').all.map((e) => e.key), ['i:cat']);
  });

  test('All respects withdrawn items and is absent when there are no looks', () {
    final catalog = Catalog(items: [_item('cat', 'Animals'), _item('retired', 'Abstract')])
        .merge(Catalog(items: []), revoked: {'retired'});
    final channels = assembleChannels(base: CatalogChannels(catalog, now),
        favourites: ['retired'], recents: ['retired'], creations: []);
    expect(channels.first.all.map((e) => e.key), ['i:cat']);
    final empty = assembleChannels(base: CatalogChannels(Catalog(items: []), now),
        favourites: [], recents: [], creations: []);
    expect(empty.where((c) => c.id == 'all'), isEmpty);
  });

  test('saved favourites and recents for looks no longer in the library are skipped', () {
    final catalog = Catalog(items: [_item('cat', 'Animals')]);
    final channels = assembleChannels(base: CatalogChannels(catalog, now),
        favourites: ['imported-42', 'cat', 'clip:imported-42'],
        recents: ['imported-42', 'clip:imported-42', 'cat'], creations: []);
    final favs = channels.singleWhere((c) => c.id == 'favs');
    final lately = channels.singleWhere((c) => c.id == 'lately');
    expect(favs.all.map((e) => e.key), ['i:cat']);
    expect(lately.all.map((e) => e.key), ['i:cat']);
    final none = assembleChannels(base: CatalogChannels(catalog, now),
        favourites: ['imported-42'], recents: ['imported-42'], creations: []);
    expect(none.where((c) => c.id == 'favs' || c.id == 'lately'), isEmpty);
  });
}
