import 'package:glyph/library/legacy_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/library/user_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('favourites migrate, deduplicate and persist without dropping unknown IDs', () async {
    final old = '$legacyCollectionPrefix-42';
    SharedPreferences.setMockInitialValues({UserLibrary.favouritesKey: [old, 'imported-42', 'unknown']});
    final library = UserLibrary();
    await library.load();
    expect(library.favourites, {'imported-42', 'unknown'});
    expect(library.isFavourite(old), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UserLibrary.favouritesKey), ['imported-42', 'unknown']);
    final reload = UserLibrary();
    await reload.load();
    expect(reload.favourites, library.favourites);
    await reload.toggleFavourite(old);
    expect(reload.isFavourite('imported-42'), isFalse);
  });

  test('recents migrate in order and deduplicate canonical IDs on disk', () async {
    final old = '$legacyCollectionPrefix-42';
    SharedPreferences.setMockInitialValues({UserLibrary.recentsKey: [old, 'unknown', 'imported-42', 'clip:$old']});
    final library = UserLibrary();
    await library.load();
    expect(library.recents, ['imported-42', 'unknown', 'clip:imported-42']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(UserLibrary.recentsKey), library.recents);
    await library.markPlayed(old);
    expect(library.recents.first, 'imported-42');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('favourites persist across instances', () async {
    final a = UserLibrary();
    await a.load();
    await a.toggleFavourite('ocean-plasma');
    await a.toggleFavourite('beating-heart');
    await a.toggleFavourite('ocean-plasma'); // un-favourite
    expect(a.favourites, {'beating-heart'});

    final b = UserLibrary();
    await b.load();
    expect(b.isFavourite('beating-heart'), isTrue);
    expect(b.isFavourite('ocean-plasma'), isFalse);
  });

  test('recents are most-recent-first, de-duplicated and capped', () async {
    final a = UserLibrary();
    for (var i = 0; i < UserLibrary.maxRecents + 5; i++) {
      await a.markPlayed('item-$i');
    }
    await a.markPlayed('item-3');
    expect(a.recents.first, 'item-3');
    expect(a.recents.length, UserLibrary.maxRecents);
    expect(a.recents.toSet().length, a.recents.length);

    final b = UserLibrary();
    await b.load();
    expect(b.recents, a.recents);
    await b.clearRecents();
    final c = UserLibrary();
    await c.load();
    expect(c.recents, isEmpty);
  });

  test('changes made before load completes are not lost', () async {
    SharedPreferences.setMockInitialValues({UserLibrary.favouritesKey: ['old']});
    final a = UserLibrary();
    final pending = a.toggleFavourite('new');
    expect(a.isFavourite('new'), isTrue);
    await pending;
    expect(a.favourites, {'old', 'new'});
    final b = UserLibrary();
    await b.load();
    expect(b.favourites, {'old', 'new'});
  });

  test('notifies listeners', () async {
    final a = UserLibrary();
    var n = 0;
    a.addListener(() => n++);
    await a.load();
    await a.toggleFavourite('x');
    expect(n, greaterThanOrEqualTo(2));
  });
}
