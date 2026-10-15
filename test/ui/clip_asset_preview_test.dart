import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/clip.dart';
import 'package:glyph/engine/clip_asset.dart';
import 'package:glyph/library/clip_asset_store.dart';
import 'package:glyph/ui/widgets/live_preview.dart';

import '../library/clip_asset_fixture.dart';

class _PreviewStore extends ClipAssetStore {
  _PreviewStore() : super(cacheDir: () async => Directory.systemTemp);
  final waiting = <String, Completer<FrameClip>>{};
  int requests = 0;
  @override
  Future<FrameClip> load(ClipAsset asset, {bool priority = false}) {
    requests++;
    return waiting.putIfAbsent(asset.id, Completer<FrameClip>.new).future;
  }
}

void main() {
  late _PreviewStore store;
  late ClipAssetStore previous;
  setUp(() {
    ClipAssetLibrary.clearCache();
    previous = ClipAssetStore.shared;
    ClipAssetStore.shared = store = _PreviewStore();
  });
  tearDown(() {
    ClipAssetStore.shared = previous;
    store.close();
    ClipAssetLibrary.clearCache();
  });

  testWidgets('hidden tiles fetch only after entering view', (tester) async {
    final (asset, _) = clipFixture();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 1200),
                SizedBox(
                  width: 100,
                  height: 100,
                  child: LivePreview.generator(
                    generator: AssetClipGenerator(asset),
                    previewKey: asset.id,
                  ),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.requests, 0);
    scroll.jumpTo(1100);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.requests, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.requests, 1);
    store.waiting[asset.id]!.completeError(const SocketException('offline'));
    await tester.pump();
    expect(find.byIcon(Icons.cloud_off_sharp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });

  testWidgets('late downloads cannot mark a replacement tile ready', (
    tester,
  ) async {
    final (a, ab) = clipFixture(id: 1);
    final (b, _) = clipFixture(id: 2, colours: [0x00ff00]);
    Widget screen(ClipAsset asset, bool enabled) => MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: enabled,
          child: SizedBox(
            width: 100,
            height: 100,
            child: LivePreview.generator(
              generator: AssetClipGenerator(asset),
              previewKey: asset.id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen(a, false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.requests, 0);
    await tester.pumpWidget(screen(a, true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.requests, 1);
    await tester.pumpWidget(screen(b, true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.requests, 2);
    store.waiting[a.id]!.complete(inflateClipAsset(ab, a));
    await tester.pump();
    expect(find.byIcon(Icons.download_sharp), findsNothing);
    store.waiting[b.id]!.completeError(const SocketException('offline'));
    await tester.pump();
    expect(find.byIcon(Icons.cloud_off_sharp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
