import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'remote_fixture.dart';

void main() {
  late Directory dir;
  setUp(() async {
    SpriteLibrary.replaceRemote([]);
    dir = await Directory.systemTemp.createTemp('glyph-remote');
  });
  tearDown(() async {
    SpriteLibrary.replaceRemote([]);
    await dir.delete(recursive: true);
  });
  RemoteCatalog remote(
    http.Client client, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    final r = RemoteCatalog(
      url: Uri.parse('https://example.com/catalog.json'),
      client: client,
      cacheDir: () async => dir,
      timeout: timeout,
    );
    addTearDown(r.close);
    return r;
  }

  test(
    'default URL stays disabled until a real deployment exists',
    () => expect(RemoteCatalog.defaultUrl, isNull),
  );

  test('staging validates compatibility, clamps params and preserves attribution without registration', () {
    final doc = remoteDocument();
    (doc['items'] as List).addAll([
      {
        'id': 'future-effect',
        'title': 'Future',
        'category': 'Remote Picks',
        'generator': 'quantum-foam',
        'palette': 'ocean',
      },
      {
        'id': 'bad-palette',
        'title': 'Bad',
        'category': 'Remote Picks',
        'generator': 'fire',
        'palette': 'ultraviolet',
      },
      {
        'id': 'Bad Id',
        'title': 'Bad',
        'category': 'Remote Picks',
        'generator': 'fire',
        'palette': 'lava',
      },
      {'title': 'no id'},
      {
        'id': 'remote-plasma',
        'title': 'Dupe',
        'category': 'Remote Picks',
        'generator': 'plasma',
        'palette': 'ocean',
      },
      {
        'id': 'future-asset',
        'title': 'Asset',
        'category': 'Remote Picks',
        'generator': 'plasma',
        'palette': 'ocean',
        'asset': {
          'type': 'gif',
          'url': 'https://example.com/a.gif',
          'author': 'Someone',
          'license': 'CC0',
        },
      },
    ]);
    final r = RemoteCatalog.parse(jsonEncode(doc))!;
    expect(r.revision, 4);
    expect(r.catalog.version, 1);
    expect(r.catalog.items.map((i) => i.id), [
      'remote-plasma',
      'remote-dot-item',
      'ocean-plasma',
    ]);
    final p = r.catalog.byId('remote-plasma')!;
    expect(p.params, {'speed': 1.0, 'scale': 0.2});
    expect(p.speed, 4);
    expect(p.notice, 'Credit retained.');
    expect(r.catalog.byId('remote-dot-item')!.notice, 'Original artwork.');
    expect(r.sprites.single.sprite.source!['creator'], 'Glyph contributors');
    expect(findGenerator('sprite:remote-dot'), isNull);
    expect(r.catalog.categories, ['Remote Picks', 'Chill']);
    expect(r.dropped.length, 6);
    expect(r.dropped.join('\n'), contains('quantum-foam'));
    expect(r.dropped.join('\n'), contains('asset type gif'));
  });

  test('a malformed tail cannot partially register valid sprites', () {
    final doc = remoteDocument()..['categories'] = [123];
    expect(RemoteCatalog.parse(jsonEncode(doc)), isNull);
    expect(findGenerator('sprite:remote-dot'), isNull);
  });

  test('schema, revision, bytes, nesting and counts are bounded', () {
    for (final body in [
      'not json',
      '{"foo":1}',
      ' ' * (RemoteCatalog.maxBytes + 1),
    ]) {
      expect(RemoteCatalog.parse(body), isNull);
    }
    for (final doc in [
      remoteDocument()..['version'] = 2,
      remoteDocument()..remove('revision'),
      remoteDocument(revision: 0),
      remoteDocument()..['items'] = List.filled(RemoteCatalog.maxItems + 1, {}),
      remoteDocument()..['sprites'] = List.filled(33, {}),
      remoteDocument()
        ..['extra'] = List.generate(
          20,
          (_) => [],
        ).fold<Object>(0, (v, _) => [v]),
    ]) {
      expect(RemoteCatalog.parse(jsonEncode(doc)), isNull);
    }
    final doc = remoteDocument();
    (doc['sprites'] as List).first['sprites'] = List.generate(
      513,
      (_) => {'id': 'x'},
    );
    expect(RemoteCatalog.parse(jsonEncode(doc)), isNull);
  });

  test(
    'decoded frame and pixel budgets reject compact expansion before adoption',
    () {
      for (final (count, rows) in [
        (129, ['R']),
        (9, List.filled(64, 'R' * 64)),
      ]) {
        final doc = remoteDocument();
        doc['sprites'] = [
          {
            'pack': 'bounded',
            'colors': {'R': '#FF0000'},
            'parts': {'base': rows},
            'sprites': [
              for (var i = 0; i < count; i++)
                {
                  'id': 'bounded-$i',
                  'frames': List.filled(64, {'base': 'base'}),
                },
            ],
          },
        ];
        expect(RemoteCatalog.parse(jsonEncode(doc)), isNull);
        expect(findGenerator('sprite:bounded-0'), isNull);
      }
    },
  );

  test('invalid frames, empty sequence, colors and unknown motion never become playable', () {
    for (final mutation in [
      {
        'frames': List.filled(65, ['R']),
      },
      {
        'frames': [
          ['R' * 257],
        ],
      },
      {'seq': []},
      {'ms': 0},
      {'motion': 'warp'},
      {
        'colors': {'R': 'p:1e999'},
      },
      {'backdrop': 9},
    ]) {
      final doc = remoteDocument();
      (doc['sprites'] as List).first['sprites'][0].addAll(mutation);
      final r = RemoteCatalog.parse(jsonEncode(doc))!;
      expect(r.catalog.byId('remote-dot-item'), isNull);
      expect(r.dropped, isNotEmpty);
      expect(findGenerator('sprite:remote-dot'), isNull);
    }
  });

  test('duplicate sprite IDs cannot silently serve an earlier drawing', () {
    final doc = remoteDocument();
    final sprites = (doc['sprites'] as List).first['sprites'] as List;
    sprites.add(cloneDocument(sprites.first as Map<String, dynamic>));
    final r = RemoteCatalog.parse(jsonEncode(doc))!;
    expect(r.catalog.byId('remote-dot-item'), isNull);
    expect(r.sprites, isEmpty);
  });

  test('bundled and downloaded drawings require new IDs when art changes', () {
    final accepted = RemoteCatalog.parse(jsonEncode(remoteDocument()))!;
    SpriteLibrary.replaceRemote(accepted.sprites);
    expect(
      RemoteCatalog.parse(jsonEncode(remoteDocument(color: '#00FF00'))),
      isNull,
    );
    expect(
      SpriteLibrary.byId('sprite:remote-dot')!.sprite
          .sameDrawing(accepted.sprites.single.sprite),
      isTrue,
    );
    final bundledId = SpriteLibrary.all
        .firstWhere((g) => SpriteLibrary.isBundled(g.id))
        .sprite
        .id;
    expect(
      RemoteCatalog.parse(jsonEncode(remoteDocument(spriteId: bundledId))),
      isNull,
    );
    final reusedItem = remoteDocument();
    (reusedItem['items'] as List).last['generator'] = 'fire';
    final base = Catalog(items: accepted.catalog.items);
    expect(RemoteCatalog.parse(jsonEncode(reusedItem), bundled: base), isNull);
  });

  test(
    'conflicting art cannot replace a good cache or reappear after restart',
    () async {
      final good = remote(
        MockClient(
          (_) async => http.Response(jsonEncode(remoteDocument()), 200),
        ),
      );
      final accepted = (await good.fetch())!;
      SpriteLibrary.replaceRemote(accepted.sprites);
      final cache = File('${dir.path}/${RemoteCatalog.cacheFile}');
      final bytes = await cache.readAsString();
      final changed = remote(
        MockClient(
          (_) async =>
              http.Response(jsonEncode(remoteDocument(color: '#00FF00')), 200),
        ),
      );
      expect(await changed.fetch(), isNull);
      expect(await cache.readAsString(), bytes);
      SpriteLibrary.replaceRemote([]);
      final restarted = (await good.loadCached())!;
      expect(
        restarted.sprites.single.sprite.sameDrawing(
          accepted.sprites.single.sprite,
        ),
        isTrue,
      );
    },
  );

  test(
    'fetch and cache are staged; offline reload overlays without network work',
    () async {
      var calls = 0;
      final rc = remote(
        MockClient((_) async {
          calls++;
          return http.Response(jsonEncode(remoteDocument()), 200);
        }),
      );
      expect(await rc.loadCached(), isNull);
      final result = (await rc.fetch())!;
      expect(calls, 1);
      expect(findGenerator('sprite:remote-dot'), isNull);
      expect(result.catalog.items.length, 3);
      final cached = (await rc.loadCached())!;
      expect(calls, 1);
      expect(cached.catalog.items.length, 3);
      final base = Catalog.parse(
        File('assets/catalog/starter.json').readAsStringSync(),
      );
      final merged = base.merge(cached.catalog);
      expect(merged.items.length, base.items.length + 2);
      expect(merged.byId('ocean-plasma')!.title, 'Ocean Plasma Remastered');
    },
  );

  test('HTTP, redirect, malformed, oversized and offline failures preserve exact cache bytes', () async {
    await remote(
      MockClient((_) async => http.Response(jsonEncode(remoteDocument()), 200)),
    ).fetch();
    final cache = File('${dir.path}/${RemoteCatalog.cacheFile}'),
        good = await File('${dir.path}/${RemoteCatalog.cacheFile}')
            .readAsString();
    for (final bad in [
      MockClient((_) async => http.Response('oops', 500)),
      MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/'},
        ),
      ),
      MockClient((_) async => http.Response('<html>', 200)),
      MockClient(
        (_) async => http.Response('x' * (RemoteCatalog.maxBytes + 1), 200),
      ),
      MockClient((_) async => throw const SocketException('offline')),
    ]) {
      expect(await remote(bad).fetch(), isNull);
      expect(await cache.readAsString(), good);
      expect(findGenerator('sprite:remote-dot'), isNull);
    }
  });

  test('streamed bodies are capped without content length and cancelled on timeout', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final rc = remote(
      MockClient.streaming(
        (req, body) async => http.StreamedResponse(stream.stream, 200),
      ),
      timeout: const Duration(milliseconds: 25),
    );
    expect(await rc.fetch(), isNull);
    expect(cancelled, isTrue);
    await stream.close();
    final oversized = remote(
      MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            List.filled(RemoteCatalog.maxBytes, 32),
            [32],
          ]),
          200,
        ),
      ),
    );
    expect(await oversized.fetch(), isNull);
  });

  test('cache is bounded and source-bound; a failed durable write installs nothing', () async {
    final rc = remote(
      MockClient((_) async => http.Response(jsonEncode(remoteDocument()), 200)),
    );
    await rc.fetch();
    final other = RemoteCatalog(
      url: Uri.parse('https://other.example/catalog.json'),
      cacheDir: () async => dir,
    );
    addTearDown(other.close);
    expect(await other.loadCached(), isNull);
    final cache = File('${dir.path}/${RemoteCatalog.cacheFile}');
    await cache.writeAsString(' ' * (RemoteCatalog.maxBytes + 1025));
    expect(await rc.loadCached(), isNull);
    final file = File('${dir.path}/blocked')..writeAsStringSync('file');
    final broken = RemoteCatalog(
      url: rc.url,
      client: MockClient(
        (_) async => http.Response(jsonEncode(remoteDocument()), 200),
      ),
      cacheDir: () async => Directory(file.path),
    );
    addTearDown(broken.close);
    expect(await broken.fetch(), isNull);
    expect(findGenerator('sprite:remote-dot'), isNull);
  });
}
