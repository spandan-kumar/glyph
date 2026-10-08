import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app/creations.dart';
import 'package:glyph/app/devices.dart';
import 'package:glyph/app/playback.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/library/bundled_catalog.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_store.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/actions.dart';
import 'package:glyph/ui/community/catalog_updates_screen.dart';
import 'package:glyph/ui/design/toggle.dart';
import 'package:glyph/ui/scope.dart';
import 'package:glyph/ui/theme.dart';
import 'package:glyph/ui/tune/pages.dart';
import 'package:glyph/ui/tune/channels.dart';
import 'package:glyph/ui/tune/tiles.dart';
import 'package:glyph/ui/tune/tune_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';

import '../features/device/fake_wled.dart';
import '../library/catalog_fixture.dart';
import '../library/remote_fixture.dart';

Future<void> _step(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Directory dir;
  late TestKey key;
  setUpAll(() async => key = await TestKey.create());
  final base = Catalog.parse(
    File('assets/catalog/catalog.json').readAsStringSync(),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      UserLibrary.favouritesKey: ['remote-dot-item'],
    });
    SpriteLibrary.replaceRemote([]);
    dir = await Directory.systemTemp.createTemp('glyph-catalog-ui');
  });
  tearDown(() async {
    SpriteLibrary.replaceRemote([]);
    bundledRevision = 0;
    await dir.delete(recursive: true);
  });

  CatalogStore makeStore(http.Client client) => CatalogStore(
    bundled: base,
    remote: RemoteCatalog(
      url: Uri.parse('https://example.com/glyph/'),
      cacheDir: () async => dir,
      client: client,
      publicKey: base64.encode(key.publicKey),
    ),
  );

  testWidgets(
    'refresh rebuilds open search and rails while retaining controller, channel, favourites and playback',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final doc = remoteDocument();
      (doc['items'] as List)[1]['title'] = 'Collector Dot';
      (doc['items'] as List)[1]['category'] = 'Chill';
      (doc['items'] as List)[1] = {
        ...(doc['items'] as List)[1] as Map,
        'added': 9,
      };
      bundledRevision = 3;
      final store = makeStore(FakeHost(await key.publish(doc)).client);
      final playback = PlaybackController(), devices = DeviceStore();
      addTearDown(store.dispose);
      addTearDown(playback.dispose);
      addTearDown(devices.dispose);
      playback.playItem(base.byId('ocean-plasma')!);
      await tester.runAsync(store.load);
      await tester.pumpWidget(
        GlyphApp(
          catalog: base,
          catalogStore: store,
          devices: devices,
          playback: playback,
          creations: CreationsStore(directory: () async => dir),
        ),
      );
      await _step(tester, 400);
      final context = tester.element(find.byType(LedTile).first);
      final tune = TuneScope.read(context);
      final calm = CatalogChannels(
        base,
        DateTime.now(),
      ).lead.singleWhere((c) => c.id == 'calm');
      tune.adopt(calm.expanded());
      final channel = tune.channel.id;
      unawaited(openChannelPage(context, calm));
      await _step(tester, 300);
      final generator = playback.generator,
          item = playback.item,
          revision = playback.revision;
      final params = playback.params.toMap(),
          palette = playback.palette,
          speed = playback.timeScale;
      unawaited(openSearch(context, tune));
      await _step(tester, 300);
      await tester.enterText(find.byType(TextField), 'Collector Dot');
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is LedTile && w.entry.title == 'Collector Dot',
        ),
        findsNothing,
      );
      await tester.runAsync(store.check);
      await _step(tester, 100);
      expect(
        find.byWidgetPredicate(
          (w) => w is LedTile && w.entry.title == 'Collector Dot',
        ),
        findsOneWidget,
      );
      final fresh = CatalogChannels(
        store.catalog,
        DateTime.now(),
      ).lead.firstWhere((c) => c.id == 'new');
      expect(fresh.name, 'Just added');
      expect(fresh.all.map((e) => e.title), ['Collector Dot']);
      expect(identical(playback.generator, generator), isTrue);
      expect(identical(playback.item, item), isTrue);
      expect(playback.revision, revision);
      expect(playback.params.toMap(), params);
      expect(identical(playback.palette, palette), isTrue);
      expect(playback.timeScale, speed);
      await tester.pageBack();
      await _step(tester, 300);
      expect(
        find.text('${calm.all.length + 1}'),
        findsOneWidget,
        reason: 'open channel page also refreshed',
      );
      await tester.pageBack();
      await _step(tester, 300);
      final after = TuneScope.read(tester.element(find.byType(LedTile).first));
      expect(identical(after, tune), isTrue);
      expect(after.channel.id, channel);
      expect(after.library.favourites, contains('remote-dot-item'));
      expect(
        AppScope.of(tester.element(find.byType(LedTile).first)).glance!.catalog
            .byId('remote-dot-item'),
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      playback.pause();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'manual update page discloses host, persists the opt-in and shows failed checks without losing content',
    (tester) async {
      var calls = 0;
      final host = FakeHost(await key.publish(remoteDocument()), etag: null);
      final store = makeStore(
        MockClient((req) async {
          if (req.url.path.endsWith('manifest-v1.json')) calls++;
          return calls == 1
              ? host.client.get(req.url)
              : http.Response('offline', 503);
        }),
      );
      final playback = PlaybackController(), devices = DeviceStore();
      addTearDown(store.dispose);
      addTearDown(playback.dispose);
      addTearDown(devices.dispose);
      await tester.runAsync(store.load);
      await tester.pumpWidget(
        AppScope(
          playback: playback,
          devices: devices,
          catalog: base,
          catalogStore: store,
          creations: CreationsStore(),
          child: MaterialApp(
            theme: buildTheme(),
            home: const CatalogUpdatesScreen(),
          ),
        ),
      );
      expect(find.textContaining('example.com'), findsOneWidget);
      expect(
        tester.widget<LbToggleTile>(find.byType(LbToggleTile)).value,
        isFalse,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Check now'));
        await store.check();
      });
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Your library has been updated.'), findsOneWidget);
      expect(find.textContaining('Up to date'), findsOneWidget);
      expect(store.revision, 4);
      expect(store.downloaded, 2);
      await tester.runAsync(() async {
        await tester.tap(find.text('Check once a day'));
        await Future<void>.delayed(Duration.zero);
      });
      await _step(tester, 100);
      expect(store.automatic, isTrue);
      expect(
        calls,
        1,
        reason: 'manual check already satisfied today’s cadence',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Check now'));
        await store.check();
      });
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Couldn’t check — are you online?'), findsOneWidget);
      expect(store.catalog.byId('remote-dot-item'), isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Send bakes the downloaded drawing in its worker isolate and uploads its actual pixels',
    (tester) async {
      final doc = RemoteCatalog.parse(jsonEncode(remoteDocument()))!;
      SpriteLibrary.replaceRemote(doc.sprites);
      final fake = FakeWled(), playback = PlaybackController();
      final devices = DeviceStore(clientFactory: fake.client);
      addTearDown(devices.dispose);
      addTearDown(playback.dispose);
      await tester.runAsync(() => devices.addAndSelect('fake', 'Fake'));
      playback.playItem(doc.catalog.byId('remote-dot-item')!);
      playback.setParam('motion', 0);
      playback.setParam('backdrop', 0);
      late BuildContext context;
      await tester.pumpWidget(
        AppScope(
          playback: playback,
          devices: devices,
          catalog: doc.catalog,
          creations: CreationsStore(),
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: Builder(
                builder: (c) {
                  context = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final result = await tester.runAsync(
        () => GlyphActions.saveToDevice(context),
      );
      expect(result, startsWith('Sent to your device'));
      final uploaded = fake.uploads.singleWhere((p) => p.endsWith('.gif'));
      final decoded = image.decodeGif(
        Uint8List.fromList(fake.gifs[uploaded]!),
      )!;
      var red = 0;
      for (final pixel in decoded) {
        if (pixel.r > 100) red++;
        expect(pixel.g, 0);
        expect(pixel.b, 0);
      }
      expect(
        red,
        greaterThan(0),
        reason: 'a red downloaded dot, not the worker’s fallback plasma',
      );
      playback.pause();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
