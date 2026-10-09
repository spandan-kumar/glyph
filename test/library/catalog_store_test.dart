import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_key.dart';
import 'package:glyph/library/catalog_store.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog_fixture.dart';
import 'remote_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DateTime now;
  late TestKey key;
  setUpAll(() async => key = await TestKey.create());
  final base = Catalog.parse(
    File('assets/catalog/starter.json').readAsStringSync(),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SpriteLibrary.replaceRemote([]);
    dir = await Directory.systemTemp.createTemp('glyph-catalog-store');
    now = DateTime(2026, 10, 7, 12);
  });
  tearDown(() async {
    SpriteLibrary.replaceRemote([]);
    await dir.delete(recursive: true);
  });
  RemoteCatalog remoteFor(http.Client client, {String? version}) =>
      RemoteCatalog(
        url: Uri.parse('https://example.com/glyph/'),
        client: client,
        cacheDir: () async => dir,
        publicKey: base64.encode(key.publicKey),
        appVersion: version == null ? null : () => version,
      );
  CatalogStore store(http.Client client, {String? version}) {
    final s = CatalogStore(
      bundled: base,
      now: () => now,
      remote: remoteFor(client, version: version),
    );
    addTearDown(s.dispose);
    return s;
  }

  Future<void> waitCheck(CatalogStore s) async {
    final deadline = Stopwatch()..start();
    while (s.lastAttempt == null || s.checking) {
      if (deadline.elapsed > const Duration(seconds: 5)) {
        fail('Check did not finish');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Map<String, dynamic> smaller(int revision) => {
    ...remoteDocument(revision: revision),
    'sprites': [],
    'items': [(remoteDocument()['items'] as List).first],
  };

  test('first paint is bundled, manual-only by default; cache restart is offline and keeps personal IDs', () async {
    final host = FakeHost(await signedFixture(key));
    final s = store(host.client);
    expect(identical(s.catalog, base), isTrue);
    await s.load();
    expect(host.requests, isEmpty);
    expect(s.automatic, isFalse);
    final library = UserLibrary();
    await library.toggleFavourite('remote-dot-item');
    await library.markPlayed('remote-dot-item');
    await s.check();
    expect(host.count('manifest-v1.json'), 1);
    expect(s.downloaded, 2);
    expect(s.revision, 4);
    expect(s.epoch, 0);
    expect(findGenerator('sprite:remote-dot'), isNotNull);
    final calls = host.requests.length;
    final offline = store(
      MockClient((_) async {
        throw const SocketException('offline');
      }),
    );
    await offline.load();
    expect(host.requests.length, calls);
    expect(offline.catalog.byId('remote-dot-item'), isNotNull);
    expect(library.favourites, contains('remote-dot-item'));
    expect(library.recents, ['remote-dot-item']);
    await offline.check();
    expect(offline.failed, isTrue);
    expect(offline.catalog.byId('remote-dot-item'), isNotNull);
    expect(findGenerator('sprite:remote-dot'), isNotNull);
    library.dispose();
  });

  test('manual checks share an in-flight request and retire unused downloads without changing held generators', () async {
    final host = FakeHost(await signedFixture(key), etag: null);
    final gate = Completer<void>();
    var first = true;
    final s = store(
      MockClient((req) async {
        if (first) {
          first = false;
          await gate.future;
        }
        return host.client.get(req.url);
      }),
    );
    await s.load();
    final a = s.check(), b = s.check();
    expect(identical(a, b), isTrue);
    gate.complete();
    await a;
    final held = findGenerator('sprite:remote-dot')!;
    host.set = await key.publish(smaller(5));
    await s.check();
    expect(s.revision, 5);
    expect(s.catalog.byId('remote-dot-item'), isNull);
    expect(findGenerator('sprite:remote-dot'), isNull);
    expect(held.id, 'sprite:remote-dot');
    expect(held.create(8, 8, 1), isNotNull);
  });

  test('daily checks are opt-in, persistent, foreground-only and wait a day after failure too', () async {
    var calls = 0;
    final s = store(
      MockClient((_) async {
        calls++;
        return http.Response('offline', 503);
      }),
    );
    await s.load();
    await s.setAutomatic(true);
    await waitCheck(s);
    expect(calls, 1);
    expect(s.failed, isTrue);
    now = now.add(const Duration(hours: 23));
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 1);
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 2));
    s.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 1);
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await waitCheck(s);
    expect(calls, 2);
    final restarted = store(
      MockClient((_) async {
        calls++;
        return http.Response('offline', 503);
      }),
    );
    await restarted.load();
    expect(restarted.automatic, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(calls, 2);
    await s.setAutomatic(false);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        CatalogStore.automaticKey,
      ),
      isFalse,
    );
    now = now.add(const Duration(days: 1));
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(calls, 2);
  });

  test('an epoch rollback refreshes the library without wiping favourites', () async {
    final host = FakeHost(await signedFixture(key), etag: null);
    final s = store(host.client);
    await s.check();
    final library = UserLibrary();
    await library.toggleFavourite('remote-dot-item');
    // Older content republished at the same revision under a higher epoch.
    host.set = await key.publish(smaller(3), revision: 4, epoch: 1);
    await s.check();
    expect((s.revision, s.epoch), (4, 1));
    expect(s.message, 'Your library has been updated.');
    expect(s.catalog.byId('remote-dot-item'), isNull);
    expect(library.favourites, contains('remote-dot-item'));
    // A replay of the original is ignored.
    host.set = await signedFixture(key);
    await s.check();
    expect(s.epoch, 1);
    expect(s.message, 'Your library is up to date.');
    library.dispose();
  });

  test('a signed takedown hides bundled and downloaded items, and survives restart', () async {
    final bundledId = base.items.firstWhere((i) => i.id != 'ocean-plasma').id;
    final host = FakeHost(await signedFixture(key), etag: null);
    final s = store(host.client);
    await s.check();
    expect(s.catalog.byId(bundledId), isNotNull);
    host.set = await key.publish(
      remoteDocument(),
      revision: 5,
      revoked: [bundledId, 'remote-plasma'],
    );
    await s.check();
    expect(s.revoked, {bundledId, 'remote-plasma'});
    expect(s.catalog.byId(bundledId), isNull);
    expect(s.catalog.byId('remote-plasma'), isNull);
    expect(s.catalog.byId('remote-dot-item'), isNotNull);
    final restarted = store(host.client);
    await restarted.load();
    expect(restarted.catalog.byId(bundledId), isNull);
    expect(restarted.catalog.byId('remote-plasma'), isNull);
    // The bundled catalog itself is untouched, only the overlay hides it.
    expect(base.byId(bundledId), isNotNull);
  });

  test('an unsigned or forged catalog never reaches the library', () async {
    final other = await TestKey.create();
    final s = store(FakeHost(await signedFixture(other)).client);
    await s.check();
    expect(s.failed, isTrue);
    expect(identical(s.catalog, base), isTrue);
    expect(findGenerator('sprite:remote-dot'), isNull);
  });

  test('a minApp gate is reported and leaves the library alone', () async {
    final s = store(
      FakeHost(await signedFixture(key, minApp: '9.0.0')).client,
      version: '1.3.3',
    );
    await s.check();
    expect(s.failed, isTrue);
    expect(s.needsNewerApp, isTrue);
    expect(s.message, contains('newer version'));
    expect(identical(s.catalog, base), isTrue);
  });

  test('disposing while downloading cannot adopt late content', () async {
    final host = FakeHost(await signedFixture(key));
    final gate = Completer<void>();
    final s = CatalogStore(
      bundled: base,
      remote: remoteFor(
        MockClient((req) async {
          await gate.future;
          return host.client.get(req.url);
        }),
      ),
    );
    await s.load();
    final checking = s.check();
    await Future<void>.delayed(Duration.zero);
    s.dispose();
    gate.complete();
    await checking;
    expect(identical(s.catalog, base), isTrue);
    expect(findGenerator('sprite:remote-dot'), isNull);
  });

  test('the production build enables Pages while a placeholder still makes no requests', () async {
    final s = CatalogStore.forApp(base);
    addTearDown(s.dispose);
    expect(decodeCatalogKey(catalogPublicKey), hasLength(32));
    expect(s.enabled, isTrue);
    expect(s.remote!.url, Uri.parse(RemoteCatalog.defaultUrl));
    expect(s.automatic, isFalse);
    // The placeholder key always means "no remote catalog".
    final placeholder = CatalogStore(
      bundled: base,
      remote: RemoteCatalog(
        url: Uri.parse('https://example.com/glyph/'),
        cacheDir: () async => dir,
        client: MockClient((_) async => fail('must not connect')),
        publicKey: catalogPublicKeyPlaceholder,
      ),
    );
    addTearDown(placeholder.dispose);
    await placeholder.check();
    expect(placeholder.enabled, isFalse);
    expect(placeholder.lastAttempt, isNull);
  });
}
