import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/pipplee_collection.dart';

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
        Catalog(items: [item('unknown', 'Pipplee 99')])
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
          item('cat', 'Kitten', tags: ['32x32'], collection: 'Pipplee'),
          item(
            'girls',
            'Powerpuff Girls',
            tags: ['32x32'],
            collection: 'Pixel Art',
          ),
        ],
      );
      expect(ids(c, 'kiten 32x32 collection:pipplee'), ['cat']);
      expect(ids(c, 'kiten 16x16 collection:pipplee'), isEmpty);
      expect(ids(c, 'kiten collection:pippllee'), isEmpty);
      expect(ids(c, 'kiten collection:pipplee collection:originals'), isEmpty);
      expect(c.searchResults('powefupp girls 16x16').suggestions, isEmpty);
      expect(
        c.searchResults('powefupp girls collection:pipplee').suggestions,
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
            'pipplee-100',
            'Pipplee 100',
            tags: ['red', '32x32'],
            category: 'Pipplee',
            asset: asset,
          ),
          item(
            'pipplee-101',
            'Pipplee 101',
            tags: ['red', '32x32'],
            category: 'Pipplee',
            asset: asset,
          ),
          item('other', 'Red Cat', tags: ['red']),
        ],
      );
      expect(ids(c, 'red'), ['other', 'pipplee-100']);
      expect(ids(c, '101'), ['pipplee-101']);
      expect(ids(c, 'Pipplee 101'), ['pipplee-101']);
      expect(ids(c, 'pipplee-101'), ['pipplee-101']);
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
      final c = parsePippleeCollection(
        File(pippleeIndexAsset).readAsStringSync(),
      );
      for (final entry in {
        'mario': 'pipplee-2005',
        'super mario': 'pipplee-2005',
        'wolverine': 'pipplee-2032',
        'logan': 'pipplee-2032',
        'x men': 'pipplee-2032',
        'xmen': 'pipplee-2032',
        'blossom': 'pipplee-2264',
        'powerpuff girls': 'pipplee-2264',
        'fallout': 'pipplee-10134',
        'vault boy': 'pipplee-10134',
        'anya forger': 'pipplee-2524',
        'spy family': 'pipplee-2524',
        'sonic hedgehog': 'pipplee-13873',
        'hollow knight': 'pipplee-4563',
        'silksong': 'pipplee-4622',
        'futurama': 'pipplee-10182',
        'pokemon': 'pipplee-2838',
        'shinchan': 'pipplee-2323',
        'game boy': 'pipplee-7178',
        'robocop': 'pipplee-2186',
        'peashooter': 'pipplee-8755',
        'plants vs zombies': 'pipplee-8755',
        'bullet bill': 'pipplee-5754',
        'pokémon': 'pipplee-2241',
        'ken kaneki': 'pipplee-14467',
        'tokyo ghoul': 'pipplee-14467',
        'twitch': 'pipplee-6111',
        'game controller': 'pipplee-6840',
        'burger': 'pipplee-4714',
        'duck splashes': 'pipplee-2826',
        'playing card suits': 'pipplee-6975',
        'pink lettering': 'pipplee-5990',
        'fairy princess': 'pipplee-2087',
        'jet takeoff': 'pipplee-2321',
        'pug': 'pipplee-5011',
        'tiger sunglasses': 'pipplee-5083',
        'telephone': 'pipplee-6309',
        'duck knife': 'pipplee-11821',
        'maracas': 'pipplee-13898',
        'energy ball': 'pipplee-14304',
      }.entries) {
        expect(ids(c, entry.key), contains(entry.value), reason: entry.key);
      }
      for (final entry in {
        'pipplee-2005': 'Mario',
        'pipplee-2032': 'Wolverine',
        'pipplee-2264': 'Blossom',
      }.entries) {
        expect(c.byId(entry.key)!.title, contains(entry.value));
      }
      expect(
        ids(c, 'pikachu'),
        isNot(contains('pipplee-5319')),
        reason: 'an ordinary yellow duck is not Pikachu',
      );
      expect(
        ids(c, 'pikachu'),
        isNot(contains('pipplee-3565')),
        reason: 'a generic white skull is not Pikachu',
      );
      expect(
        ids(c, 'wolverine'),
        isNot(contains('pipplee-14887')),
        reason: 'the cat in a Christmas stocking is not Wolverine',
      );
      expect(
        ids(c, 'clothing'),
        isNot(contains('pipplee-7178')),
        reason: 'the rotating handheld is a game console, not clothing',
      );
      expect(
        ids(c, 'tree'),
        isNot(contains('pipplee-8755')),
        reason: 'the Peashooter is not a tree',
      );
      expect(
        ids(c, 'creature'),
        isNot(contains('pipplee-6309')),
        reason: 'the ringing telephone is not a grinning creature',
      );
      expect(
        c.byId('pipplee-2321')!.title,
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
        parsePippleeCollection(File(pippleeIndexAsset).readAsStringSync()),
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
      final duplicate = c.items.firstWhere((i) => i.id.startsWith('pipplee-'));
      expect(c.search(duplicate.id).single.id, duplicate.id);
      expect(c.search('zzzz-nothing'), isEmpty);
    },
  );
}
