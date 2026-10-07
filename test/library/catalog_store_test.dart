import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/catalog_store.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:glyph/library/user_library.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DateTime now;
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
  CatalogStore store(http.Client client) {
    final s = CatalogStore(
      bundled: base,
      now: () => now,
      remote: RemoteCatalog(
        url: Uri.parse('https://example.com/catalog.json'),
        client: client,
        cacheDir: () async => dir,
      ),
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

  test('first paint is bundled, manual-only by default; cache restart is offline and keeps personal IDs', () async {
    var calls = 0;
    final s = store(
      MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(remoteDocument()), 200);
      }),
    );
    expect(identical(s.catalog, base), isTrue);
    await s.load();
    expect(calls, 0);
    expect(s.automatic, isFalse);
    final library = UserLibrary();
    await library.toggleFavourite('remote-dot-item');
    await library.markPlayed('remote-dot-item');
    await s.check();
    expect(calls, 1);
    expect(s.downloaded, 2);
    expect(s.revision, 4);
    expect(findGenerator('sprite:remote-dot'), isNotNull);
    final offline = store(
      MockClient((_) async {
        calls++;
        throw const SocketException('offline');
      }),
    );
    await offline.load();
    expect(calls, 1);
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
    var calls = 0;
    final gate = Completer<http.Response>();
    final s = store(
      MockClient((_) async {
        calls++;
        return calls == 1
            ? gate.future
            : http.Response(
                jsonEncode({
                  ...remoteDocument(revision: 5),
                  'sprites': [],
                  'items': [(remoteDocument()['items'] as List).first],
                }),
                200,
              );
      }),
    );
    await s.load();
    final a = s.check(), b = s.check();
    expect(identical(a, b), isTrue);
    gate.complete(http.Response(jsonEncode(remoteDocument()), 200));
    await a;
    final held = findGenerator('sprite:remote-dot')!;
    await s.check();
    expect(calls, 2);
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

  test(
    'lower revision rollback refreshes library without wiping favourites',
    () async {
      var body = jsonEncode(remoteDocument());
      final s = store(MockClient((_) async => http.Response(body, 200)));
      await s.check();
      final library = UserLibrary();
      await library.toggleFavourite('remote-dot-item');
      body = jsonEncode({
        ...remoteDocument(revision: 3),
        'sprites': [],
        'items': [(remoteDocument()['items'] as List).first],
      });
      await s.check();
      expect(s.revision, 3);
      expect(s.catalog.byId('remote-dot-item'), isNull);
      expect(library.favourites, contains('remote-dot-item'));
      library.dispose();
    },
  );

  test('disposing while downloading cannot adopt late content', () async {
    final gate = Completer<http.Response>();
    final s = CatalogStore(
      bundled: base,
      remote: RemoteCatalog(
        url: Uri.parse('https://example.com/catalog.json'),
        cacheDir: () async => dir,
        client: MockClient((_) => gate.future),
      ),
    );
    await s.load();
    final checking = s.check();
    await Future<void>.delayed(Duration.zero);
    s.dispose();
    gate.complete(http.Response(jsonEncode(remoteDocument()), 200));
    await checking;
    expect(identical(s.catalog, base), isTrue);
    expect(findGenerator('sprite:remote-dot'), isNull);
  });

  test('an unconfigured build loads without contacting a host', () async {
    final s = CatalogStore.forApp(base);
    addTearDown(s.dispose);
    await s.load();
    await s.check();
    expect(s.enabled, isFalse);
    expect(s.lastAttempt, isNull);
    expect(identical(s.catalog, base), isTrue);
  });
}
