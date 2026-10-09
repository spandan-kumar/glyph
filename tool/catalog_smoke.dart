// Checks the production Pages artifact and app delivery path without a phone.
//   dart run tool/catalog_smoke.dart
import 'dart:convert';
import 'dart:io';

import 'package:glyph/library/catalog.dart';
import 'package:glyph/library/remote_catalog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Client extends http.BaseClient {
  final _inner = http.Client();
  final requests = <(String, int)>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    requests.add((request.url.path, response.statusCode));
    return response;
  }

  @override
  void close() => _inner.close();
}

Future<void> main() async {
  final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  final bundled = Catalog.parse(File('assets/catalog/catalog.json').readAsStringSync());
  final dir = await Directory.systemTemp.createTemp('glyph-catalog-smoke-');
  final client = _Client();
  final remote = RemoteCatalog(
    url: Uri.parse(RemoteCatalog.defaultUrl), cacheDir: () async => dir,
    client: client, appVersion: () => version,
  );
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }
  try {
    final first = await remote.fetch(bundled: bundled);
    require(first != null, 'Public fetch failed: ${remote.lastError}');
    require(first!.dropped.isEmpty, 'Rejected entries: ${first.dropped}');
    final merged = bundled.merge(first.catalog, revoked: first.revoked);
    require(merged.items.length == bundled.items.length, 'Initial catalog lost entries');
    stdout.writeln('Verified public signature, hash and ${merged.items.length} merged looks; '
        'revision ${first.revision}, epoch ${first.epoch}.');
    final payloadGets = client.requests.where((r) => r.$1.contains('/payload/')).length;
    final second = await remote.fetch(bundled: bundled);
    require(second != null && !second.changed, 'Repeat check did not retain the cached catalog');
    require(client.requests.where((r) => r.$1.contains('/payload/')).length == payloadGets,
        'Repeat check downloaded the payload again');
    stdout.writeln('Repeat check reused the verified payload: ${jsonEncode(client.requests.map((r) => [r.$1, r.$2]).toList())}');
    final offline = RemoteCatalog(
      url: remote.url, cacheDir: () async => dir,
      client: MockClient((_) async => throw const SocketException('offline')),
      appVersion: () => version,
    );
    try {
      final cached = await offline.loadCached(bundled: bundled);
      require(cached != null && cached.revision == first.revision &&
          bundled.merge(cached.catalog, revoked: cached.revoked).items.length == merged.items.length,
          'Offline restart did not recover the verified cache');
      require(await offline.fetch(bundled: bundled) == null, 'Offline check unexpectedly succeeded');
      require((await offline.loadCached(bundled: bundled))?.revision == first.revision,
          'Failed network check damaged the cache');
      stdout.writeln('Offline restart and failed check preserved the verified library.');
    } finally {
      offline.close();
    }
    final older = RemoteCatalog(
      url: remote.url, cacheDir: () async => dir, appVersion: () => '1.3.5',
    );
    try {
      require(await older.fetch(bundled: bundled) == null && older.needsNewerApp,
          'The first publication did not enforce minApp 1.3.6');
      stdout.writeln('Older app version refused the catalog without changing its library.');
    } finally {
      older.close();
    }
  } finally {
    remote.close();
    await dir.delete(recursive: true);
  }
}
