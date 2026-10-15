import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/imported_collection.dart';

LibraryItem item(
  String id,
  String title, {
  List<String> tags = const [],
  List<String> aliases = const [],
  List<String> subjects = const [],
  String category = 'Animals',
  String? collection,
  LibraryAsset? asset,
}) => LibraryItem(
  id: id,
  title: title,
  category: category,
  generatorId: 'hidden-generator',
  paletteId: 'rainbow',
  tags: tags,
  aliases: aliases,
  subjects: subjects,
  collection: collection,
  asset: asset,
);

List<String> ids(Catalog c, String q) => c.search(q).map((i) => i.id).toList();

void main() {
  test('normalizes case, punctuation, dimensions and reviewed spelling equivalents', () {
    final c = Catalog(
      items: [
        item('cat', 'Cozy Grey Cat', tags: ['blue', '32x32']),
      ],
    );
    expect(ids(c, '  COZY, gray--cat! '), ['cat']);
    expect(ids(c, 'cosy cat'), ['cat']);
    expect(ids(c, 'blue 32 × 32'), ['cat']);
    expect(ids(c, 'blue 16x16'), isEmpty);
    expect(ids(c, ';;;'), ['cat']);
  });

  test('colorful spelling variants match the same authored descriptor', () {
    final c = Catalog(items: [
      item('british', 'Confetti', tags: ['colourful']),
      item('american', 'Fireworks', tags: ['colorful']),
    ]);
    expect(ids(c, 'colorful'), ['british', 'american']);
    expect(ids(c, 'colourful'), ['british', 'american']);
    expect(c.searchResults('colorful').correctedQuery, isNull);
  });

  test('matches whole words; only completes an unknown final word', () {
    final c = Catalog(
      items: [
        item('cat', 'Sleeping Cat', tags: ['blue']),
        item('church', 'Blue Cathedral'),
        item('catfish', 'Catfish'),
      ],
    );
    expect(ids(c, 'cat'), ['cat']);
    expect(ids(c, 'blue cat'), ['cat']);
    expect(ids(c, 'blue cath'), ['church']);
    expect(ids(c, 'cath blue'), isEmpty);
    expect(ids(c, 'cat blue sleeping'), ['cat']);
    expect(
      ids(c, 'blue sleeping dog'),
      isEmpty,
      reason: 'no query word is dropped',
    );
    expect(
      ids(Catalog(items: [item('church', 'Cathedral')]), 'cat'),
      isEmpty,
      reason: 'short subject words are not arbitrary prefixes even if metadata is missing',
    );
  });

  test(
    'exact name, alias, subject and descriptor tiers rank in that order',
    () {
      final c = Catalog(
        items: [
          item('descriptor', 'Evening', category: 'Cat'),
          item('subject', 'Sleepy Friend', subjects: ['cat']),
          item('alias', 'Small Friend', aliases: ['cat']),
          item('title', 'Cat'),
          item('title-word', 'Cat Nap'),
        ],
      );
      expect(ids(c, 'cat'), [
        'title',
        'alias',
        'title-word',
        'subject',
        'descriptor',
      ]);
      expect(ids(c, 'cat'), ids(c, 'cat'), reason: 'ties are stable');
      expect(ids(c, 'title-word'), [
        'title-word',
      ], reason: 'full stable IDs still work');
    },
  );

  test('all metadata survives serialization and catalogue merges rebuild the index', () {
    final original = item(
      'cat',
      'Cat',
      aliases: ['kitten'],
      subjects: ['pet'],
      collection: 'Originals',
    );
    final c = Catalog.parse(jsonEncode(Catalog(items: [original]).toJson()));
    expect(c.items.single.toJson(), original.toJson());
    expect(ids(c, 'kitten'), ['cat']);
    expect(ids(c, 'pet collection:originals'), ['cat']);
    final next = c.merge(
      Catalog(
        items: [
          item('dog', 'Dog', aliases: ['puppy']),
        ],
      ),
    );
    expect(ids(next, 'puppy'), ['dog']);
    expect(ids(c, 'puppy'), isEmpty);
  });

  test('search ignores internal generator and placeholder palette IDs', () {
    final c = Catalog(
      items: [item('cat', 'Cat'), item('rainbow', 'Rainbow Rings')],
    );
    expect(ids(c, 'rainbow'), ['rainbow']);
    expect(ids(c, 'hidden-generator'), isEmpty);
    expect(ids(c, 'animals'), ['cat', 'rainbow']);
  });

  test('small unique spelling slips are corrected visibly; direct matches always win', () {
    final c = Catalog(
      items: [item('kitten', 'Kitten'), item('flames', 'Flames')],
    );
    expect(ids(c, 'kiten'), ['kitten']);
    expect(c.searchResults('kiten').correctedQuery, 'kitten');
    expect(ids(c, 'flmaes'), ['flames']);
    expect(ids(c, 'ct'), isEmpty);
    expect(ids(c, 'qqqzzz'), isEmpty);
    final direct = c.merge(Catalog(items: [item('spelling', 'Kiten')]));
    expect(ids(direct, 'kiten'), ['spelling']);
    expect(direct.searchResults('kiten').correctedQuery, isNull);
    final ambiguous = Catalog(
      items: [item('cat', 'Cats'), item('car', 'Cars')],
    );
    expect(ambiguous.searchResults('cals').items, isEmpty);
    expect(
      ambiguous.searchResults('cals').suggestions,
      containsAll(['cats', 'cars']),
    );
  });

  test(
    'large spelling errors suggest indexed names without guessing subjects',
    () {
      final c = Catalog(items: [item('fixture', 'Powerpuff Girls')]);
      final result = c.searchResults('powefupp girls');
      expect(result.items, isEmpty);
      expect(result.suggestions, ['powerpuff girls']);
      expect(c.search('girls'), isNotEmpty);
      expect(
        Catalog(items: [item('unknown', 'Imported 99')])
            .searchResults('powefupp girls')
            .suggestions,
        isEmpty,
      );
    },
  );

  test(
    'corrections and suggestions cannot relax size or collection constraints',
    () {
      final c = Catalog(
        items: [
          item('cat', 'Kitten', tags: ['32x32'], collection: 'Imported'),
          item(
            'girls',
            'Powerpuff Girls',
            tags: ['32x32'],
            collection: 'Pixel Art',
          ),
        ],
      );
      expect(ids(c, 'kiten 32x32 collection:imported'), ['cat']);
      expect(ids(c, 'kiten 16x16 collection:imported'), isEmpty);
      expect(ids(c, 'kiten collection:pippllee'), isEmpty);
      expect(ids(c, 'kiten collection:imported collection:originals'), isEmpty);
      expect(c.searchResults('powefupp girls 16x16').suggestions, isEmpty);
      expect(
        c.searchResults('powefupp girls collection:imported').suggestions,
        isEmpty,
      );
      final suggestion = c
          .searchResults('powefupp girls 32x32 collection:"Pixel Art"')
          .suggestions
          .single;
      expect(ids(c, suggestion), ['girls']);
      expect(ids(c, 'collection:"Pixel Art" 32x32'), ['girls']);
    },
  );

  test(
    'duplicate clips collapse in content results but retain source-ID access',
    () {
      const asset = LibraryAsset(
        type: 'clip-gzip',
        url: 'shared.clip.gz',
        extra: {'sha256': 'same-hash'},
      );
      final c = Catalog(
        items: [
          item(
            'imported-100',
            'Imported 100',
            tags: ['red', '32x32'],
            category: 'Imported',
            asset: asset,
          ),
          item(
            'imported-101',
            'Imported 101',
            tags: ['red', '32x32'],
            category: 'Imported',
            asset: asset,
          ),
          item('other', 'Red Cat', tags: ['red']),
        ],
      );
      expect(ids(c, 'red'), ['other', 'imported-100']);
      expect(ids(c, '101'), ['imported-101']);
      expect(ids(c, 'Imported 101'), ['imported-101']);
      expect(ids(c, 'imported-101'), ['imported-101']);
      expect(ids(c, '101 16x16'), isEmpty);
      expect(
        ids(c, '1001'),
        isEmpty,
        reason: 'source IDs are never fuzzy matched',
      );
      expect(
        c.items.length,
        3,
        reason: 'deduplication only changes search presentation',
      );
    },
  );

  test(
    'reviewed names and franchise aliases find the actual clips',
    () {
      final c = parseImportedCollection(
        File(importedIndexAsset).readAsStringSync(),
      );
      for (final entry in {
        'mario': 'imported-2005',
        'super mario': 'imported-2005',
        'wolverine': 'imported-2032',
        'logan': 'imported-2032',
        'x men': 'imported-2032',
        'xmen': 'imported-2032',
        'blossom': 'imported-2264',
        'powerpuff girls': 'imported-2264',
        'fallout': 'imported-10134',
        'vault boy': 'imported-10134',
        'anya forger': 'imported-2524',
        'spy family': 'imported-2524',
        'sonic hedgehog': 'imported-13873',
        'hollow knight': 'imported-4563',
        'silksong': 'imported-4622',
        'futurama': 'imported-10182',
        'pokemon': 'imported-2838',
        'shinchan': 'imported-2323',
        'game boy': 'imported-7178',
        'robocop': 'imported-2186',
        'peashooter': 'imported-8755',
        'plants vs zombies': 'imported-8755',
        'bullet bill': 'imported-5754',
        'pokémon': 'imported-2241',
        'ken kaneki': 'imported-14467',
        'tokyo ghoul': 'imported-14467',
        'twitch': 'imported-6111',
        'game controller': 'imported-6840',
        'burger': 'imported-4714',
        'duck splashes': 'imported-2826',
        'playing card suits': 'imported-6975',
        'pink lettering': 'imported-5990',
        'fairy princess': 'imported-2087',
        'jet takeoff': 'imported-2321',
        'pug': 'imported-5011',
        'tiger sunglasses': 'imported-5083',
        'telephone': 'imported-6309',
        'duck knife': 'imported-11821',
        'maracas': 'imported-13898',
        'energy ball': 'imported-14304',
      }.entries) {
        expect(ids(c, entry.key), contains(entry.value), reason: entry.key);
      }
      for (final entry in {
        'imported-2005': 'Mario',
        'imported-2032': 'Wolverine',
        'imported-2264': 'Blossom',
      }.entries) {
        expect(c.byId(entry.key)!.title, contains(entry.value));
      }
      expect(
        ids(c, 'pikachu'),
        isNot(contains('imported-5319')),
        reason: 'an ordinary yellow duck is not Pikachu',
      );
      expect(
        ids(c, 'pikachu'),
        isNot(contains('imported-3565')),
        reason: 'a generic white skull is not Pikachu',
      );
      expect(
        ids(c, 'wolverine'),
        isNot(contains('imported-14887')),
        reason: 'the cat in a Christmas stocking is not Wolverine',
      );
      expect(
        ids(c, 'clothing'),
        isNot(contains('imported-7178')),
        reason: 'the rotating handheld is a game console, not clothing',
      );
      expect(
        ids(c, 'tree'),
        isNot(contains('imported-8755')),
        reason: 'the Peashooter is not a tree',
      );
      expect(
        ids(c, 'creature'),
        isNot(contains('imported-6309')),
        reason: 'the ringing telephone is not a grinning creature',
      );
      expect(
        c.byId('imported-2321')!.title,
        'Jet Taking Off',
      );
    },
  );

  test(
    'full collection searches use known metadata without false rainbow matches',
    () {
      final bundled = Catalog.parse(
        File('assets/catalog/catalog.json').readAsStringSync(),
      );
      final c = bundled.merge(
        parseImportedCollection(File(importedIndexAsset).readAsStringSync()),
      );
      final rainbows = c
          .search('rainbow')
          .where((i) => i.collection == 'Imported')
          .toList();
      expect(rainbows, isNotEmpty);
      expect(rainbows.length, lessThan(c.items.where((i) => i.collection == 'Imported').length));
      for (final item in rainbows) {
        expect(
          [item.title, ...item.subjects, ...item.aliases, ...item.tags].any(
            (t) => t
                .toLowerCase()
                .split(RegExp(r'[^a-z0-9]+'))
                .contains('rainbow'),
          ),
          isTrue,
        );
      }
      expect(c.search('imported red 32x32'), isNotEmpty);
      final duplicate = c.items.firstWhere((i) => i.id.startsWith('imported-'));
      expect(c.search(duplicate.id).single.id, duplicate.id);
      expect(c.search('zzzz-nothing'), isEmpty);
    },
  );
}
