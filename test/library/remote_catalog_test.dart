import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/registry.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _doc = {
  'version': 1,
  'categories': ['Remote Picks', 'Empty Category'],
  'sprites': [
    {
      'pack': 'remote',
      'category': 'Remote Picks',
      'colors': {'R': '#FF0000'},
      'sprites': [
        {'id': 'remote-dot', 'title': 'Remote Dot', 'tags': ['dot'], 'frames': [['.R.', 'RRR', '.R.']]}
      ],
    },
    {'pack': 'broken', 'sprites': [{'id': 'bad', 'frames': [['Z']]}]},
  ],
  'items': [
    {'id': 'remote-plasma', 'title': 'Remote Plasma', 'category': 'Remote Picks', 'tags': ['new'],
     'generator': 'plasma', 'palette': 'ocean', 'params': {'speed': 7, 'scale': 0.2, 'bogus': 1}, 'speed': 9},
    {'id': 'remote-dot-item', 'title': 'Dot', 'category': 'Remote Picks', 'generator': 'sprite:remote-dot', 'palette': 'neon'},
    {'id': 'future-effect', 'title': 'Future', 'category': 'Remote Picks', 'generator': 'quantum-foam', 'palette': 'ocean'},
    {'id': 'bad-palette', 'title': 'Bad', 'category': 'Remote Picks', 'generator': 'fire', 'palette': 'ultraviolet'},
    {'id': 'Bad Id', 'title': 'Bad id', 'category': 'Remote Picks', 'generator': 'fire', 'palette': 'lava'},
    {'title': 'no id'},
    {'id': 'ocean-plasma', 'title': 'Ocean Plasma Remastered', 'category': 'Chill', 'generator': 'plasma', 'palette': 'deepsea'},
    {'id': 'remote-plasma', 'title': 'Dupe', 'category': 'Remote Picks', 'generator': 'plasma', 'palette': 'ocean'},
  ],
};

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('glyph-remote'));
  tearDown(() => dir.delete(recursive: true));

  RemoteCatalog remote(http.Client client) => RemoteCatalog(
      url: Uri.parse('https://example.com/catalog.json'), client: client, cacheDir: () async => dir);

  test('no URL is configured yet', () {
    expect(RemoteCatalog.defaultUrl, isNull);
  });

  test('validation drops what this build cannot play and clamps the rest', () {
    final r = RemoteCatalog.parse(jsonEncode(_doc))!;
    final ids = r.catalog.items.map((i) => i.id).toList();
    expect(ids, ['remote-plasma', 'remote-dot-item', 'ocean-plasma']);
    final p = r.catalog.byId('remote-plasma')!;
    expect(p.params, {'speed': 1.0, 'scale': 0.2});
    expect(p.speed, 4);
    expect(findGenerator('sprite:remote-dot'), isNotNull, reason: 'remote sprite packs register');
    expect(r.catalog.categories, ['Remote Picks', 'Chill']);
    expect(r.dropped.length, greaterThanOrEqualTo(6));
    expect(r.dropped.join('\n'), contains('quantum-foam'));
    expect(RemoteCatalog.parse('not json'), isNull);
    expect(RemoteCatalog.parse('{"foo": 1}'), isNull);
  });

  test('fetch caches, merge overlays bundled items', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode(_doc), 200);
    });
    final rc = remote(client);
    expect(await rc.loadCached(), isNull);
    final fetched = await rc.fetch();
    expect(fetched, isNotNull);
    expect(calls, 1);
    expect(File('${dir.path}/${RemoteCatalog.cacheFile}').existsSync(), isTrue);

    final cached = await rc.loadCached();
    expect(cached!.catalog.items.length, 3);

    final bundled = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    final merged = bundled.merge(cached.catalog);
    expect(merged.items.length, bundled.items.length + 2);
    expect(merged.byId('ocean-plasma')!.title, 'Ocean Plasma Remastered');
    expect(merged.categories.take(bundled.categories.length), bundled.categories);
    expect(merged.categories, contains('Remote Picks'));
  });

  test('network failures and bad responses keep the last good cache', () async {
    final good = remote(MockClient((_) async => http.Response(jsonEncode(_doc), 200)));
    await good.fetch();
    for (final bad in [
      MockClient((_) async => http.Response('oops', 500)),
      MockClient((_) async => http.Response('<html>', 200)),
      MockClient((_) async => throw const SocketException('offline')),
    ]) {
      expect(await remote(bad).fetch(), isNull);
      expect((await remote(bad).loadCached())!.catalog.items.length, 3);
    }
  });

  test('overlay returns cached data immediately and reports fresh data later', () async {
    final rc = remote(MockClient((_) async => http.Response(jsonEncode(_doc), 200)));
    final bundled = Catalog.parse(File('assets/catalog/starter.json').readAsStringSync());
    final refreshed = Completer<Catalog>();
    final first = await rc.overlay(bundled, onUpdate: refreshed.complete);
    expect(first.items.length, bundled.items.length, reason: 'nothing cached yet');
    final updated = await refreshed.future.timeout(const Duration(seconds: 5));
    expect(updated.byId('remote-plasma'), isNotNull);
  });
}
