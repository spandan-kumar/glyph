import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_key.dart';
import 'package:glyph/library/catalog_manifest.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'catalog_fixture.dart';
import 'remote_fixture.dart';

void main() {
  late Directory dir;
  late TestKey key;
  setUpAll(() async => key = await TestKey.create());
  setUp(() async {
    SpriteLibrary.replaceRemote([]);
    dir = await Directory.systemTemp.createTemp('glyph-remote');
  });
  tearDown(() async {
    SpriteLibrary.replaceRemote([]);
    await dir.delete(recursive: true);
  });
  final starter = Catalog.parse(
    File('assets/catalog/starter.json').readAsStringSync(),
  );
  RemoteCatalog remote(
    http.Client client, {
    Duration timeout = const Duration(seconds: 8),
    String? version,
    Uri? url,
    String? publicKey,
  }) {
    final r = RemoteCatalog(
      url: url ?? Uri.parse('https://example.com/glyph/'),
      client: client,
      cacheDir: () async => dir,
      timeout: timeout,
      publicKey: publicKey ?? base64.encode(key.publicKey),
      appVersion: version == null ? null : () => version,
    );
    addTearDown(r.close);
    return r;
  }

  File meta() => File('${dir.path}/${RemoteCatalog.metaFile}');
  Uint8List flip(Uint8List b, int at) =>
      Uint8List.fromList(b)..[at] = b[at] ^ 1;

  group('activation', () {
    test('the default URL is the Pages site', () {
      expect(
        RemoteCatalog.defaultUrl,
        'https://spandan-kumar.github.io/glyph/',
      );
    });

    test('the placeholder key disables the client: no network, no cache trust', () async {
      expect(decodeCatalogKey(catalogPublicKeyPlaceholder), isNull);
      expect(decodeCatalogKey('not base64!'), isNull);
      expect(decodeCatalogKey(base64.encode(List.filled(31, 1))), isNull);
      final host = FakeHost(await signedFixture(key));
      await remote(host.client).fetch();
      expect(meta().existsSync(), isTrue);
      final r = RemoteCatalog(
        url: Uri.parse('https://example.com/glyph/'),
        client: host.client,
        cacheDir: () async => dir,
        publicKey: catalogPublicKeyPlaceholder,
      );
      addTearDown(r.close);
      final before = host.requests.length;
      expect(r.usable, isFalse);
      expect(await r.fetch(), isNull);
      expect(await r.loadCached(), isNull);
      expect(host.requests.length, before);
    });
  });

  group('payload parsing', () {
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


    test('a malformed category is dropped on its own; the rest still applies', () {
      final doc = remoteDocument()..['categories'] = [123, 'Remote Picks'];
      final r = RemoteCatalog.parse(jsonEncode(doc))!;
      expect(r.catalog.items.length, 3);
      expect(r.catalog.categories, ['Remote Picks', 'Chill']);
      expect(r.dropped.join(), contains('category'));
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


    test('a bad pack or sprite is rejected without losing the others', () {
      final doc = remoteDocument();
      (doc['sprites'] as List).insert(0, 'junk');
      ((doc['sprites'] as List)[1]['sprites'] as List).add('also junk');
      final r = RemoteCatalog.parse(jsonEncode(doc))!;
      expect(r.catalog.byId('remote-dot-item'), isNotNull);
      expect(r.dropped.length, 2);
    });

    test('a conflicting bundled drawing drops only that sprite and its items', () {
      final bundledId = SpriteLibrary.all
          .firstWhere((g) => SpriteLibrary.isBundled(g.id))
          .sprite
          .id;
      final r = RemoteCatalog.parse(
        jsonEncode(remoteDocument(spriteId: bundledId, color: '#123456')),
      )!;
      expect(r.catalog.byId('remote-dot-item'), isNull);
      expect(r.catalog.byId('remote-plasma'), isNotNull);
      expect(r.dropped.join(), contains('bundled drawing'));
      expect(r.sprites, isEmpty);
    });

    test('downloads cannot override bundled item metadata', () {
      final bundledItem = starter.items.firstWhere(
        (i) => i.id != 'ocean-plasma',
      );
      final doc = remoteDocument();
      (doc['items'] as List).add({
        'id': bundledItem.id,
        'title': 'Hijacked',
        'category': 'Remote Picks',
        'generator': 'fire',
        'palette': 'lava',
      });
      final r = RemoteCatalog.parse(jsonEncode(doc), bundled: starter)!;
      expect(r.catalog.byId(bundledItem.id), isNull);
      expect(r.dropped, isEmpty);
      final merged = starter.merge(r.catalog);
      expect(merged.byId(bundledItem.id)!.title, bundledItem.title);
      expect(merged.byId('remote-plasma'), isNotNull);
    });

    test('merge applies revocations to bundled and downloaded items alike', () {
      final r = RemoteCatalog.parse(jsonEncode(remoteDocument()))!;
      final gone = starter.items.first;
      final merged = starter.merge(
        r.catalog,
        revoked: {gone.id, 'sprite:remote-dot'},
      );
      expect(merged.byId(gone.id), isNull);
      expect(merged.byId('remote-dot-item'), isNull);
      expect(merged.byId('remote-plasma'), isNotNull);
    });
  });

  group('authenticity', () {
    test('a valid signature and hash open the catalog inside an isolate', () async {
      final set = await signedFixture(key, revoked: ['old-thing']);
      final r = (await remote(FakeHost(set).client).fetch())!;
      expect(r.revision, 4);
      expect(r.epoch, 0);
      expect(r.revoked, {'old-thing'});
      expect(r.catalog.items.length, 3);
      expect(r.changed, isTrue);
    });

    test('invalid signatures are refused before the payload is parsed', () async {
      final other = await TestKey.create();
      final set = await signedFixture(key);
      final cases = <String, FakeHost>{
        'wrong key': FakeHost(await signedFixture(other)),
        'tampered manifest': FakeHost(set)
          ..manifestOverride = Uint8List.fromList(
            utf8.encode(utf8.decode(set.manifest).replaceFirst('"revision":4', '"revision":9')),
          ),
        'bit-flipped signature': FakeHost(set)
          ..sigOverride = Uint8List.fromList(
            utf8.encode(base64.encode(flip(base64.decode(utf8.decode(set.sig).trim()), 3))),
          ),
        'garbage signature': FakeHost(set)..sigOverride = Uint8List.fromList(utf8.encode('???')),
        'empty signature': FakeHost(set)..sigOverride = Uint8List(0),
      };
      for (final e in cases.entries) {
        e.value.payloadOverride = Uint8List.fromList(utf8.encode('{not json'));
        final rc = remote(e.value.client);
        expect(await rc.fetch(), isNull, reason: e.key);
        expect(rc.lastError, contains('signature'), reason: e.key);
        expect(e.value.count('.json') , lessThan(3), reason: '${e.key}: payload never downloaded');
        expect(meta().existsSync(), isFalse);
      }
    });

    test('a payload whose hash differs from the signed manifest is refused', () async {
      final set = await signedFixture(key);
      final host = FakeHost(set)..payloadOverride = flip(set.payload, 10);
      final rc = remote(host.client);
      expect(await rc.fetch(), isNull);
      expect(rc.lastError, contains('hash'));
      host.payloadOverride = Uint8List.fromList([...set.payload, 32]);
      expect(await remote(host.client).fetch(), isNull);
      expect(meta().existsSync(), isFalse);
    });

    test('open() rejects payload size and hash mismatches directly', () async {
      final set = await signedFixture(key);
      Future<Object?> run(Uint8List payload) async {
        try {
          await RemoteCatalog.open(
            manifest: set.manifest,
            signature: set.sig,
            payload: payload,
            publicKey: key.publicKey,
          );
          return null;
        } on CatalogRejected catch (e) {
          return e.reason;
        }
      }

      expect(await run(set.payload), isNull);
      expect(await run(set.payload.sublist(1)), contains('size'));
      expect(await run(flip(set.payload, 0)), contains('hash'));
    });

    test('the cache is re-verified on load; tampering makes it unusable', () async {
      final host = FakeHost(await signedFixture(key));
      final rc = remote(host.client);
      await rc.fetch();
      expect(await remote(host.client).loadCached(), isNotNull);
      final payload = dir
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.payload'));
      payload.writeAsBytesSync(flip(payload.readAsBytesSync(), 5));
      expect(await remote(host.client).loadCached(), isNull);
    });

    test('the cache is bound to its source, bounded, and holds raw bytes', () async {
      final host = FakeHost(await signedFixture(key));
      final rc = remote(host.client);
      await rc.fetch();
      final doc = jsonDecode(meta().readAsStringSync()) as Map;
      expect(doc['origin'], 'https://example.com/glyph/');
      expect(
        remote(host.client, url: Uri.parse('https://other.example/glyph/')),
        isNotNull,
      );
      expect(
        await remote(host.client, url: Uri.parse('https://other.example/glyph/')).loadCached(),
        isNull,
      );
      meta().writeAsStringSync(' ' * (200 * 1024));
      expect(await remote(host.client).loadCached(), isNull);
    });
  });

  group('freshness', () {
    test('only a higher revision, or the same revision with a higher epoch, is accepted', () async {
      final v4 = await signedFixture(key);
      final host = FakeHost(v4, etag: null);
      final rc = remote(host.client);
      expect((await rc.fetch())!.revision, 4);

      // Replay of an older signed set: kept as is, reported, not adopted.
      host.set = await signedFixture(key, revision: 3);
      final replay = (await rc.fetch())!;
      expect(replay.changed, isFalse);
      expect(replay.revision, 4);
      expect(rc.lastError, contains('stale'));

      // Same revision and epoch, different bytes: no silent swap.
      final swapped = remoteDocument()
        ..['categories'] = ['Remote Picks'];
      host.set = await key.publish(swapped);
      expect((await rc.fetch())!.changed, isFalse);

      // Same revision, higher epoch: the rollback path.
      final rollback = await key.publish(
        remoteDocument(revision: 3),
        revision: 4,
        epoch: 1,
      );
      host.set = rollback;
      final rolled = (await rc.fetch())!;
      expect(rolled.changed, isTrue);
      expect((rolled.revision, rolled.epoch), (4, 1));
      expect(
        (await remote(host.client).loadCached())!.epoch,
        1,
        reason: 'persisted',
      );

      // A later epoch-0 publish with a higher revision still wins.
      host.set = await signedFixture(key, revision: 5);
      expect((await rc.fetch())!.revision, 5);

      // And an older epoch at the same revision is refused again.
      host.set = rollback;
      expect((await rc.fetch())!.changed, isFalse);
      expect((await rc.loadCached())!.revision, 5);
    });

    test('the same baseline applies on a cold start and in session', () async {
      final doc = remoteDocument();
      (doc['items'] as List).add({
        'id': starter.items.first.id,
        'title': 'Clash',
        'category': 'Chill',
        'generator': 'plasma',
        'palette': 'ocean',
      });
      final host = FakeHost(await key.publish(doc));
      final rc = remote(host.client);
      final live = (await rc.fetch(bundled: starter))!;
      final cold = (await remote(host.client).loadCached(bundled: starter))!;
      expect(
        live.catalog.items.map((i) => i.id),
        cold.catalog.items.map((i) => i.id),
      );
      expect(live.catalog.byId(starter.items.first.id), isNull);
    });

    test('minApp gates the catalog and reports it', () async {
      final host = FakeHost(await signedFixture(key, minApp: '2.0.0'));
      final old = remote(host.client, version: '1.9.9');
      expect(await old.fetch(), isNull);
      expect(old.needsNewerApp, isTrue);
      expect(meta().existsSync(), isFalse);
      final fresh = remote(host.client, version: '2.0.0+5');
      expect(await fresh.fetch(), isNotNull);
      expect(fresh.needsNewerApp, isFalse);
      expect(CatalogManifest.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    });
  });

  group('transport', () {
    test('ETag revalidation: 304 keeps the cache and downloads nothing', () async {
      final host = FakeHost(await signedFixture(key));
      final rc = remote(host.client);
      await rc.fetch();
      expect(host.count('.sig'), 1);
      final again = (await rc.fetch())!;
      expect(again.changed, isFalse);
      expect(host.count('.sig'), 1);
      expect(host.requests.where((r) => r.contains('/payload/')).length, 1);
      // A restart reuses the stored ETag too.
      final restarted = remote(host.client);
      expect((await restarted.fetch())!.changed, isFalse);
      expect(host.requests.where((r) => r.contains('/payload/')).length, 1);
    });

    test('the payload is fetched only when its hash changed', () async {
      final base = await signedFixture(key);
      final host = FakeHost(base, etag: null);
      final rc = remote(host.client);
      await rc.fetch();
      // New manifest (takedown) over the same payload.
      host.set = await key.publish(
        remoteDocument(),
        revision: 5,
        revoked: ['remote-plasma'],
      );
      host.payloadOverride = null;
      final updated = (await rc.fetch())!;
      expect(updated.revision, 5);
      expect(updated.revoked, {'remote-plasma'});
      expect(updated.catalog.byId('remote-plasma'), isNull);
      expect(host.requests.where((r) => r.contains('/payload/')).length, 1);
      // Revoked ids survive a restart.
      expect(
        (await remote(host.client).loadCached())!.catalog.byId('remote-plasma'),
        isNull,
      );
    });

    test('redirects stay on https and on the same host or github.io', () {
      final from = Uri.parse('https://example.com/glyph/manifest-v1.json');
      for (final ok in [
        'https://example.com/other/path',
        'https://spandan-kumar.github.io/glyph/manifest-v1.json',
        'https://github.io/x',
      ]) {
        expect(RemoteCatalog.allowedRedirect(from, Uri.parse(ok)), isTrue, reason: ok);
      }
      for (final bad in [
        'http://example.com/glyph/manifest-v1.json',
        'https://evil.example/glyph/manifest-v1.json',
        'https://github.io.evil.example/x',
        'https://notgithub.io/x',
        'https://user:pw@example.com/x',
        'ftp://example.com/x',
      ]) {
        expect(RemoteCatalog.allowedRedirect(from, Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('redirects are followed within policy and refused outside it', () async {
      final set = await signedFixture(key);
      final inner = FakeHost(set);
      http.Response? redirectTo(String to) =>
          http.Response('', 301, headers: {'location': to});
      final host = FakeHost(set)
        ..intercept = (req) => req.url.path.endsWith('manifest-v1.json')
            ? redirectTo('https://example.com/glyph/mirror/manifest-v1.json')
            : null;
      expect(await remote(MockClient((req) async {
        if (req.url.path.contains('/mirror/')) {
          return inner.client.get(req.url.replace(path: '/glyph/manifest-v1.json'));
        }
        return host.client.get(req.url);
      })).fetch(), isNotNull);

      for (final target in [
        'http://example.com/glyph/manifest-v1.json',
        'https://evil.example/glyph/manifest-v1.json',
      ]) {
        final seen = <String>[];
        final bad = MockClient((req) async {
          seen.add(req.url.toString());
          return http.Response('', 302, headers: {'location': target});
        });
        final rc = remote(bad);
        expect(await rc.fetch(), isNull);
        expect(rc.lastError, contains('Redirect'));
        expect(seen, ['https://example.com/glyph/manifest-v1.json']);
      }
      final loop = MockClient(
        (req) async => http.Response('', 302, headers: {'location': req.url.toString()}),
      );
      final rc = remote(loop);
      expect(await rc.fetch(), isNull);
      expect(rc.lastError, contains('redirects'));
    });

    test('failures keep the exact cached bytes', () async {
      final host = FakeHost(await signedFixture(key));
      await remote(host.client).fetch();
      final good = meta().readAsStringSync();
      for (final bad in [
        MockClient((_) async => http.Response('oops', 500)),
        MockClient((_) async => http.Response('<html>', 200)),
        MockClient((_) async => throw const SocketException('offline')),
        MockClient((_) async => http.Response('x' * 70000, 200)),
      ]) {
        expect(await remote(bad).fetch(), isNull);
        expect(meta().readAsStringSync(), good);
        expect(findGenerator('sprite:remote-dot'), isNull);
      }
    });

    test('size caps apply to Content-Length and to streamed bodies', () async {
      final set = await signedFixture(key);
      final tooBig = FakeHost(set)
        ..intercept = (req) => req.url.path.contains('/payload/')
            ? http.Response.bytes(
                Uint8List(set.payload.length + 1),
                200,
              )
            : null;
      expect(await remote(tooBig.client).fetch(), isNull);

      final lies = MockClient.streaming((req, _) async {
        if (req.url.path.endsWith('manifest-v1.json')) {
          return http.StreamedResponse(
            Stream.value(set.manifest),
            200,
          );
        }
        if (req.url.path.endsWith('.sig')) {
          return http.StreamedResponse(Stream.value(set.sig), 200);
        }
        return http.StreamedResponse(
          Stream.fromIterable([
            List.filled(set.payload.length, 32),
            [32],
          ]),
          200,
        );
      });
      expect(await remote(lies).fetch(), isNull);

      final huge = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            List.filled(CatalogManifest.maxBytes, 32),
            [32],
          ]),
          200,
        ),
      );
      expect(await remote(huge).fetch(), isNull);
      final declared = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          const Stream.empty(),
          200,
          contentLength: RemoteCatalog.maxBytes + 1,
        ),
      );
      expect(await remote(declared).fetch(), isNull);
      expect(
        CatalogManifest.parse(
          utf8.encode(
            jsonEncode({
              ...set.parsed.toJson(),
              'size': RemoteCatalog.maxBytes + 1,
            }),
          ),
        ),
        isNull,
      );
    });

    test('a gzip bomb behind Content-Encoding is cut off at the cap', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final bomb = GZipCodec().encode(Uint8List(48 * 1024 * 1024));
      expect(bomb.length, lessThan(200 * 1024));
      var served = 0;
      server.listen((req) {
        served++;
        req.response.headers.set('content-encoding', 'gzip');
        req.response.add(bomb);
        req.response.close().catchError((_) {});
      });
      final rc = remote(
        http.Client(),
        url: Uri.parse('http://127.0.0.1:${server.port}/glyph/'),
      );
      final clock = Stopwatch()..start();
      expect(await rc.fetch(), isNull);
      expect(served, 1);
      expect(clock.elapsed, lessThan(const Duration(seconds: 6)));
      expect(rc.lastError, isNotNull);
      expect(meta().existsSync(), isFalse);

      // The same bomb as a signed manifest's payload.
      final set = await signedFixture(key);
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server2.close(force: true));
      server2.listen((req) {
        final name = req.uri.path.split('/glyph/').last;
        final body = name == CatalogManifest.fileName
            ? set.manifest
            : name.endsWith('.sig')
            ? set.sig
            : null;
        if (body != null) {
          req.response.add(body);
        } else {
          req.response.headers.set('content-encoding', 'gzip');
          req.response.add(bomb);
        }
        req.response.close().catchError((_) {});
      });
      final rc2 = remote(
        http.Client(),
        url: Uri.parse('http://127.0.0.1:${server2.port}/glyph/'),
      );
      expect(await rc2.fetch(), isNull);
      expect(meta().existsSync(), isFalse);
    });

    test('streamed bodies are cancelled on timeout', () async {
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
    });

    test('a failed durable write installs nothing', () async {
      final host = FakeHost(await signedFixture(key));
      final file = File('${dir.path}/blocked')..writeAsStringSync('file');
      final broken = RemoteCatalog(
        url: Uri.parse('https://example.com/glyph/'),
        client: host.client,
        cacheDir: () async => Directory(file.path),
        publicKey: base64.encode(key.publicKey),
      );
      addTearDown(broken.close);
      expect(await broken.fetch(), isNull);
      expect(findGenerator('sprite:remote-dot'), isNull);
    });
  });
}
