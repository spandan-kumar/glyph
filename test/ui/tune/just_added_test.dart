import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/library/bundled_catalog.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/ui/tune/channels.dart';

void main() {
  tearDown(() => bundledRevision = 0);

  LibraryItem item(String id, int added) => LibraryItem(
    id: id,
    title: id,
    category: 'Chill',
    generatorId: 'plasma',
    paletteId: 'ocean',
    added: added,
  );
  final catalog = Catalog(items: [item('old', 3), item('newer', 4), item('newest', 5)]);
  final now = DateTime(2026, 10, 7, 12);

  test('Just added leads with items newer than the bundled revision', () {
    bundledRevision = 3;
    final lead = CatalogChannels(catalog, now).lead;
    expect(lead.first.id, 'new');
    expect(lead.first.name, 'Just added');
    expect(lead.first.all.map((e) => e.title).toSet(), {'newer', 'newest'});
  });

  test('there is no shelf when nothing is newer or the revision is unknown', () {
    bundledRevision = 5;
    expect(CatalogChannels(catalog, now).lead.any((c) => c.id == 'new'), isFalse);
    bundledRevision = 0;
    expect(CatalogChannels(catalog, now).lead.any((c) => c.id == 'new'), isFalse);
  });

  test('Community has its own rail after Just added, only when there are items', () {
    LibraryItem made(String id, String category, int added) => LibraryItem(
      id: id,
      title: id,
      category: category,
      generatorId: id,
      paletteId: 'ocean',
      added: added,
      notice: 'By @someone · CC0',
    );
    bundledRevision = 3;
    final withCommunity = Catalog(items: [item('old', 3), made('fresh', 'Community', 4), made('fresh2', 'Community', 4)]);
    final c = CatalogChannels(withCommunity, now);
    expect(c.lead.map((e) => e.id).take(2), ['new', 'community']);
    expect(c.lead[1].name, 'Community');
    expect(c.lead[1].all.map((e) => e.title).toSet(), {'fresh', 'fresh2'});
    expect(c.rest.any((e) => e.name == 'Community'), isFalse);

    expect(CatalogChannels(catalog, now).lead.any((e) => e.id == 'community'), isFalse);
  });
}
