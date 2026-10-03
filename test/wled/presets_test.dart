import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/wled/presets.dart';
import 'package:glyph/wled/wled_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'manage_fixtures.dart';

void main() {
  group('WledPreset', () {
    final presets = WledPreset.parseAll(jsonDecode(presetsV16));

    test('parses the real presets.json, skipping id 0', () {
      expect(presets.map((p) => p.id), [1, 101, 102]);
      expect(presets.map((p) => p.name), ['Ocean Plasma', 'WLED Turn Off', 'Pipplee']);
    });

    test('kinds, GIFs, effects and the off preset', () {
      final [ocean, off, pipplee] = presets;
      expect(ocean.kind, PresetKind.state);
      expect(ocean.gifName, 'ocean-plasma.gif');
      expect(ocean.effectId, 53);
      expect(ocean.segments, hasLength(1), reason: '{"stop":0} placeholders dropped');
      expect(ocean.turnsOff, isFalse);
      expect(off.turnsOff, isTrue);
      expect(off.gifName, isNull);
      expect(pipplee.gifName, 'pipplee.gif');
      expect(pipplee.segments, hasLength(1));
      expect(pipplee.primaryColor, 0);
    });

    test('stored playlist is recognised', () {
      final p = WledPreset.parseAll({'201': jsonDecode(storedPlaylistV16)}).single;
      expect(p.kind, PresetKind.playlist);
      expect(p.name, 'glyph_test_list');
      expect(p.gifName, isNull);
    });
  });

  group('WledPlaylist', () {
    test('parses what the device stored', () {
      final pl = WledPlaylist.fromJson(
        (jsonDecode(storedPlaylistV16)['playlist'] as Map).cast<String, dynamic>(),
      );
      expect(pl.entries, const [
        PlaylistEntry(presetId: 200, durationDs: 50, transitionDs: 0),
        PlaylistEntry(presetId: 102, durationDs: 70, transitionDs: 5),
      ]);
      expect(pl.repeat, 2);
      expect(pl.shuffle, isFalse, reason: '"r":0');
      expect(pl.endPreset, 0);
      expect(pl.passDuration, const Duration(seconds: 12));
    });

    test('toJson matches the WLED UI format and round-trips', () {
      const pl = WledPlaylist(
        entries: [
          PlaylistEntry(presetId: 1, durationDs: 300, transitionDs: 7),
          PlaylistEntry(presetId: 102, durationDs: 0, transitionDs: 0),
        ],
        repeat: 0,
        shuffle: true,
        endPreset: WledPlaylist.restorePrevious,
      );
      expect(pl.toJson(), {
        'ps': [1, 102],
        'dur': [300, 0],
        'transition': [7, 0],
        'repeat': 0,
        'r': true,
        'end': 255,
      });
      final back = WledPlaylist.fromJson(jsonDecode(jsonEncode(pl.toJson())));
      expect(back.entries, pl.entries);
      expect((back.repeat, back.shuffle, back.endPreset), (0, true, 255));
      expect(back.passDuration, isNull, reason: 'an entry lasts forever');
    });

    test('scalar dur/transition and short arrays expand like loadPlaylist', () {
      final a = WledPlaylist.fromJson({
        'ps': [1, 2, 3],
        'dur': 50,
        'transition': [4],
      });
      expect(a.entries.map((e) => e.durationDs), [50, 50, 50]);
      expect(a.entries.map((e) => e.transitionDs), [4, 4, 4]);
      final b = WledPlaylist.fromJson({
        'ps': [1, 2, 3],
        'dur': [10, 20],
      });
      expect(b.entries.map((e) => e.durationDs), [10, 20, 20]);
      expect(b.entries.map((e) => e.transitionDs), [7, 7, 7]);
    });

    test('negative repeat means forever + shuffle; bad end is dropped', () {
      final pl = WledPlaylist.fromJson({
        'ps': [1],
        'repeat': -1,
        'end': 251,
      });
      expect((pl.repeat, pl.shuffle, pl.endPreset), (0, true, 0));
    });

    test('caps at 100 entries', () {
      final pl = WledPlaylist.fromJson({'ps': List.generate(120, (i) => i + 1)});
      expect(pl.entries, hasLength(WledPlaylist.maxEntries));
    });
  });

  group('WledClient presets', () {
    late List<http.Request> posts;
    late Map<String, Object?> presetsJson;

    WledClient client() => WledClient(
      '192.168.29.6',
      client: MockClient((r) async {
        if (r.method == 'POST') posts.add(r);
        return switch (r.url.path) {
          '/presets.json' => http.Response(jsonEncode(presetsJson), 200),
          '/json/state' => http.Response('{"success":true}', 200),
          '/duck.gif' => http.Response.bytes([71, 73, 70, 56, 57, 97], 200),
          _ => http.Response('Not found', 404),
        };
      }),
    );

    setUp(() {
      posts = [];
      presetsJson = {
        ...jsonDecode(presetsV16) as Map<String, dynamic>,
        '201': jsonDecode(storedPlaylistV16),
      };
    });

    Map<String, dynamic> body(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

    test('savePlaylist sends psave + playlist + o like the WLED UI', () async {
      await client().savePlaylist(
        id: 202,
        name: 'Evening',
        playlist: const WledPlaylist(
          entries: [PlaylistEntry(presetId: 1), PlaylistEntry(presetId: 102)],
          repeat: 3,
        ),
      );
      expect(body(posts.single), {
        'psave': 202,
        'n': 'Evening',
        'playlist': {
          'ps': [1, 102],
          'dur': [100, 100],
          'transition': [7, 7],
          'repeat': 3,
          'r': false,
          'end': 0,
        },
        'on': true,
        'o': true,
      });
    });

    test('savePlaylist rejects empty, self-referencing and bad ids', () async {
      final c = client();
      const one = WledPlaylist(entries: [PlaylistEntry(presetId: 1)]);
      expect(
        () => c.savePlaylist(
          id: 5,
          name: 'x',
          playlist: const WledPlaylist(entries: []),
        ),
        throwsA(isA<WledException>()),
      );
      expect(() => c.savePlaylist(id: 1, name: 'x', playlist: one), throwsA(isA<WledException>()));
      expect(
        () => c.savePlaylist(id: 251, name: 'x', playlist: one),
        throwsA(isA<WledException>()),
      );
      expect(posts, isEmpty);
    });

    test('renaming a state preset re-saves its body verbatim with "o"', () async {
      await client().renamePreset(1, '  Ocean  ');
      final b = body(posts.single);
      final original = (jsonDecode(presetsV16) as Map)['1'] as Map;
      expect(b['psave'], 1);
      expect(b['n'], 'Ocean');
      expect(b['o'], isTrue);
      expect(b['seg'], original['seg']);
      expect(b['bri'], original['bri']);
    });

    test('renaming a playlist re-saves it as a playlist', () async {
      await client().renamePreset(201, 'Renamed');
      final b = body(posts.single);
      expect(b['playlist']['ps'], [200, 102]);
      expect(b['n'], 'Renamed');
      expect(b.containsKey('seg'), isFalse);
    });

    test('rename of a missing preset fails without writing', () async {
      expect(() => client().renamePreset(77, 'x'), throwsA(isA<WledException>()));
      await Future<void>.delayed(Duration.zero);
      expect(posts, isEmpty);
    });

    test('presetList, nightlight, next and file bytes', () async {
      final c = client();
      expect((await c.presetList()).map((p) => p.id), [1, 101, 102, 201]);
      await c.setNightlight(on: true, minutes: 300, mode: 1, targetBri: 0);
      await c.nextInPlaylist();
      expect(body(posts[0]), {
        'nl': {'on': true, 'dur': 255, 'mode': 1, 'tbri': 0},
      });
      expect(body(posts[1]), {'np': true});
      expect(await c.fileBytes('duck.gif'), [71, 73, 70, 56, 57, 97]);
    });
  });
}
