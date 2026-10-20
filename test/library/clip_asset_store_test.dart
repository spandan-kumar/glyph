import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/library/imported_collection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'clip_asset_fixture.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}

void main() {
  late Directory dir;
  final base = Uri.parse('https://example.com/glyph/');
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('glyph-clip-test-');
    ClipAssetLibrary.clearCache();
  });
  tearDown(() async {
    ClipAssetLibrary.clearCache();
    await dir.delete(recursive: true);
  });

  test('bundled clips work offline without a disk cache or download', () async {
    final (asset, bytes) = clipFixture(delays: [120, 350]);
    final store = ClipAssetStore(
      bundle: _Bundle({
        privateClipAsset(asset.sha256): bytes,
      }),
      cacheDir: () async => throw StateError('No disk cache'),
      client: MockClient((_) async => throw StateError('Unexpected download')),
    );
    addTearDown(store.close);
    final clip = await store.load(asset);
    expect(clip.delaysMs, [120, 350]);
    expect(clip.frames.map((f) => f.get(0, 0)), [0xff0000, 0x0000ff]);
    expect(ClipAssetLibrary.cached(asset.sha256), same(clip));
    // A cold decoded cache still loads entirely from the application bundle.
    ClipAssetLibrary.clearCache();
    expect((await store.load(asset)).delaysMs, [120, 350]);
  });

  test(
    'an unbundled clip still downloads and caches for offline use',
    () async {
      final (asset, bytes) = clipFixture();
      var requests = 0;
      final store = ClipAssetStore(
        bundle: _Bundle({}),
        cacheDir: () async => dir,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      addTearDown(store.close);
      await store.load(asset);
      expect(requests, 1);
      expect(
        await File('${dir.path}/animation-clips/${asset.sha256}.clip.gz')
            .exists(),
        isTrue,
      );
      ClipAssetLibrary.clearCache();
      await store.load(asset);
      expect(requests, 1);
    },
  );

  for (final promote in [false, true]) {
    test('bundled decodes use four slots and prioritize playback (promote: $promote)', () async {
      final fixtures = List.generate(21, (i) => clipFixture(id: i, colours: [i + 1]));
      final started = <String>[];
      final busy = Completer<void>(), release = Completer<void>();
      var active = 0, peak = 0;
      final store = ClipAssetStore(
        bundle: _Bundle({for (final (asset, bytes) in fixtures)
          privateClipAsset(asset.sha256): bytes}),
        cacheDir: () async => throw StateError('No disk cache'),
        decode: (bytes, asset) async {
          active++;
          if (active > peak) peak = active;
          started.add(asset.id);
          if (started.length == 4) busy.complete();
          try {
            await release.future;
            return inflateClipAsset(bytes, asset);
          } finally {
            active--;
          }
        },
      );
      addTearDown(store.close);
      final previews = Future.wait(fixtures.take(20).map((f) => store.load(f.$1)));
      await busy.future;
      expect(started, hasLength(4));
      final pick = fixtures[promote ? 19 : 20].$1;
      final playback = store.load(pick, priority: true);
      expect(started, hasLength(4));
      release.complete();
      await Future.wait([previews, playback]);
      expect(peak, 4);
      expect(started[4], pick.id, reason: 'playback jumps ahead of queued previews');
      expect(started.toSet().length, promote ? 20 : 21);
    });
  }

  test(
    'corrupt bundled clips are rejected without a network fallback',
    () async {
      final (asset, bytes) = clipFixture();
      final broken = Uint8List.fromList(bytes)..[15] ^= 1;
      final store = ClipAssetStore(
        bundle: _Bundle({
          privateClipAsset(asset.sha256): broken,
        }),
        cacheDir: () async => throw StateError('No disk cache'),
        client: MockClient(
          (_) async => throw StateError('Unexpected download'),
        ),
      );
      addTearDown(store.close);
      await expectLater(store.load(asset), throwsFormatException);
      expect(ClipAssetLibrary.cached(asset.sha256), isNull);
    },
  );

  test(
    'concurrent loads share one request; colours and timing survive',
    () async {
      final (asset, bytes) = clipFixture(delays: [120, 350]);
      var requests = 0;
      final gate = Completer<void>();
      final store = ClipAssetStore(
        cacheDir: () async => dir,
        baseUrl: base,
        client: MockClient((request) async {
          requests++;
          expect(request.url, base.resolve(asset.path));
          await gate.future;
          return http.Response.bytes(bytes, 200);
        }),
      );
      addTearDown(store.close);
      final first = store.load(asset), second = store.load(asset);
      gate.complete();
      final clips = await Future.wait([first, second]);
      expect(requests, 1);
      expect(identical(clips[0], clips[1]), isTrue);
      expect(clips.first.delaysMs, [120, 350]);
      expect(clips.first.frames.map((f) => f.get(0, 0)), [0xff0000, 0x0000ff]);
    },
  );

  test('distinct downloads are capped at four concurrent requests', () async {
    final fixtures = List.generate(
      9,
      (i) => clipFixture(id: 100 + i, colours: [i + 1]),
    );
    final gate = Completer<void>(), entered = Completer<void>();
    var active = 0, peak = 0, requests = 0;
    final store = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: base,
      client: MockClient((request) async {
        requests++;
        active++;
        if (active > peak) peak = active;
        if (active == 4 && !entered.isCompleted) entered.complete();
        await gate.future;
        active--;
        return http.Response.bytes(
          fixtures.firstWhere((f) => request.url.path.contains(f.$1.sha256)).$2,
          200,
        );
      }),
    );
    addTearDown(store.close);
    final loading = Future.wait(fixtures.map((f) => store.load(f.$1)));
    await entered.future;
    expect(requests, 4);
    gate.complete();
    expect((await loading).length, 9);
    expect(peak, lessThanOrEqualTo(4));
  });

  test('offline restart uses only a verified cached file', () async {
    final (asset, bytes) = clipFixture();
    final online = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: base,
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    await online.load(asset);
    online.close();
    ClipAssetLibrary.clearCache();
    final offline = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: base,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    addTearDown(offline.close);
    expect((await offline.load(asset)).frames.length, 2);
    ClipAssetLibrary.clearCache();
    final file = File('${dir.path}/animation-clips/${asset.sha256}.clip.gz');
    final corrupted = await file.readAsBytes();
    corrupted[15] ^= 1;
    await file.writeAsBytes(corrupted);
    await expectLater(offline.load(asset), throwsA(isA<SocketException>()));
    expect(ClipAssetLibrary.cached(asset.sha256), isNull);
  });

  test(
    'wrong hash and oversized/truncated responses never enter the cache',
    () async {
      final (asset, bytes) = clipFixture();
      for (final body in [
        bytes.sublist(0, bytes.length - 1),
        [...bytes, 0],
        List<int>.filled(bytes.length, 0),
      ]) {
        final store = ClipAssetStore(
          cacheDir: () async => dir,
          baseUrl: base,
          client: MockClient((_) async => http.Response.bytes(body, 200)),
        );
        await expectLater(store.load(asset), throwsFormatException);
        expect(ClipAssetLibrary.cached(asset.sha256), isNull);
        store.close();
      }
      expect(
        await Directory('${dir.path}/animation-clips').list().toList(),
        isEmpty,
      );
    },
  );

  test('redirects cannot move requests to another host', () async {
    final (asset, _) = clipFixture();
    var requests = 0;
    final store = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: base,
      client: MockClient((_) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': 'https://other.example/clip.gz'},
        );
      }),
    );
    addTearDown(store.close);
    await expectLater(store.load(asset), throwsFormatException);
    expect(requests, 1);
  });

  test('decoded size, dimensions and delays must match the index', () {
    final (asset, bytes) = clipFixture();
    expect(
      () => inflateClipAsset(
        bytes,
        ClipAsset(
          id: asset.id,
          title: asset.title,
          sha256: asset.sha256,
          bytes: asset.bytes,
          width: 1,
          height: 1,
          frames: 2,
        ),
      ),
      throwsFormatException,
    );
    final (zero, zeroBytes) = clipFixture(delays: [0, 100]);
    expect(() => inflateClipAsset(zeroBytes, zero), throwsFormatException);
  });

  test(
    'disk cache evicts older clips without affecting current playback',
    () async {
      final (a, ab) = clipFixture(id: 1);
      final (b, bb) = clipFixture(id: 2, colours: [0x00ff00]);
      final store = ClipAssetStore(
        cacheDir: () async => dir,
        baseUrl: base,
        maxDiskBytes: bb.length,
        client: MockClient(
          (r) async =>
              http.Response.bytes(r.url.path.contains(a.sha256) ? ab : bb, 200),
        ),
      );
      addTearDown(store.close);
      final clip = await store.load(a);
      await store.load(b);
      expect(
        await File('${dir.path}/animation-clips/${a.sha256}.clip.gz').exists(),
        isFalse,
      );
      expect(
        await File('${dir.path}/animation-clips/${b.sha256}.clip.gz').exists(),
        isTrue,
      );
      expect(clip.frames.first.get(0, 0), 0xff0000);
    },
  );
}
