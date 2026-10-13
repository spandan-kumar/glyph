import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../library/clip_asset_fixture.dart';

LibraryItem item(ClipAsset asset) => LibraryItem(
  id: asset.id.substring(5),
  title: asset.title,
  category: 'Pipplee',
  generatorId: asset.id,
  paletteId: 'rainbow',
);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('glyph-clip-play-');
    ClipAssetLibrary.clearCache();
  });
  tearDown(() async {
    ClipAssetLibrary.clearCache();
    await dir.delete(recursive: true);
  });

  test('a late download never replaces a newer selection', () async {
    final (asset, bytes) = clipFixture();
    ClipAssetLibrary.register([asset]);
    final gate = Completer<void>();
    final store = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: Uri.parse('https://example.com/'),
      client: MockClient((_) async {
        await gate.future;
        return http.Response.bytes(bytes, 200);
      }),
    );
    final playback = PlaybackController(clipAssets: store)
      ..playGenerator(generators.first);
    addTearDown(() {
      playback.dispose();
      store.close();
    });
    final previous = playback.generator;
    final pending = playback.playItem(item(asset));
    expect(playback.generator, same(previous));
    expect(playback.loadingTitle, asset.title);
    playback.playGenerator(generators[1]);
    gate.complete();
    expect(await pending, isFalse);
    expect(playback.generator, same(generators[1]));
    expect(playback.loadingTitle, isNull);
    playback.pause();
  });

  test('a changed device or power request cancels a pending pick', () async {
    final (asset, bytes) = clipFixture();
    ClipAssetLibrary.register([asset]);
    final gate = Completer<void>();
    final store = ClipAssetStore(cacheDir: () async => dir,
      baseUrl: Uri.parse('https://example.com/'),
      client: MockClient((_) async { await gate.future; return http.Response.bytes(bytes, 200); }));
    final playback = PlaybackController(clipAssets: store)..playGenerator(generators.first);
    addTearDown(() { playback.dispose(); store.close(); });
    var currentDevice = true;
    final pending = playback.playItem(item(asset), canPlay: () => currentDevice);
    currentDevice = false;
    gate.complete();
    expect(await pending, false);
    expect(playback.generator, same(generators.first));
    expect(playback.loadingTitle, isNull);
    expect(playback.loadError, isNull);
    playback.pause();
  });

  test(
    'verified clip plays immediately and keeps the catalogue identity for Send',
    () async {
      final (asset, bytes) = clipFixture();
      ClipAssetLibrary.register([asset]);
      final store = ClipAssetStore(
        cacheDir: () async => dir,
        baseUrl: Uri.parse('https://example.com/'),
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      final playback = PlaybackController(clipAssets: store);
      addTearDown(() {
        playback.dispose();
        store.close();
      });
      expect(await playback.playItem(item(asset)), isTrue);
      expect(playback.generator, isA<ClipGenerator>());
      expect(playback.generator!.id, asset.id);
      expect(playback.item!.id, 'pipplee-42');
      expect(playback.frame.get(0, 4), 0xff0000);
      playback.pause();
    },
  );

  test('failed loading and pause leave the old look untouched', () async {
    final (asset, _) = clipFixture();
    ClipAssetLibrary.register([asset]);
    final store = ClipAssetStore(
      cacheDir: () async => dir,
      baseUrl: Uri.parse('https://example.com/'),
      client: MockClient((_) async => http.Response('', 404)),
    );
    final playback = PlaybackController(clipAssets: store)
      ..playGenerator(generators.first);
    addTearDown(() {
      playback.dispose();
      store.close();
    });
    expect(await playback.playItem(item(asset)), isFalse);
    expect(playback.generator, same(generators.first));
    expect(playback.loadError, contains('try again'));
    playback.pause();
  });
}
