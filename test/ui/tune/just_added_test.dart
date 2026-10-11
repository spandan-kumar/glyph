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
}
