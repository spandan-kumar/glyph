import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../engine/generator.dart';
import '../engine/generators/sprite.dart';
import '../engine/generators/sprite_library.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import 'catalog.dart';
import 'catalog_key.dart';
import 'catalog_manifest.dart';

/// A staged, verified document. Parsing never changes the runtime registry.
class RemoteCatalogResult {
  const RemoteCatalogResult(
    this.catalog,
    this.dropped,
    this.revision,
    this.sprites, {
    this.epoch = 0,
    this.revoked = const {},
    this.changed = true,
    this.published = '',
  });
  final Catalog catalog;

  /// Entries rejected one by one (the rest of the catalog still applies).
  final List<String> dropped;
  final int revision, epoch;
  final List<SpriteGenerator> sprites;

  /// Item or generator ids the manifest withdraws, bundled ones included.
  final Set<String> revoked;

  /// False when a check confirmed the cached content is still current.
  final bool changed;
  final String published;

  RemoteCatalogResult unchanged() => RemoteCatalogResult(
    catalog,
    dropped,
    revision,
    sprites,
    epoch: epoch,
    revoked: revoked,
    changed: false,
    published: published,
  );
}

/// Why a manifest or payload was refused.
class CatalogRejected implements Exception {
  const CatalogRejected(this.reason, {this.needsNewerApp = false});
  final String reason;
  final bool needsNewerApp;
  @override
  String toString() => reason;
}

/// Verified, cached delivery of the animation catalog.
///
/// A check fetches the small signed manifest first, verifies its Ed25519
/// signature, and downloads the payload only when its SHA-256 changed. The
/// payload is hashed and parsed only after the manifest verified.
class RemoteCatalog {
  RemoteCatalog({
    required Uri url,
    required this.cacheDir,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    String publicKey = catalogPublicKey,
    this.appVersion,
  }) : url = url.path.endsWith('/') ? url : url.replace(path: '${url.path}/'),
       _key = decodeCatalogKey(publicKey),
       _client = client ?? http.Client();

  /// Directory that serves manifest-v1.json, its .sig and the payload.
  static const String defaultUrl = 'https://spandan-kumar.github.io/glyph/';
  static const metaFile = 'remote_catalog.meta';
  static const maxBytes = CatalogManifest.maxPayloadBytes;
  static const maxItems = 2000, maxSprites = 512, maxFrames = 8192;
  static const maxDecodedPixels = 2 * 1024 * 1024;
  static const maxRedirects = 3;
  static const maxDropped = 500;
  static final _payloadCache = RegExp(r'^remote_catalog\.[0-9a-f]{64}\.payload$');

  /// Base directory URL (always ends with a slash).
  final Uri url;
  final Future<Directory> Function() cacheDir;
  final Duration timeout;

  /// The running app's `X.Y.Z`, compared with the manifest's `minApp`.
  /// Null skips the gate (tests, tools).
  final FutureOr<String?> Function()? appVersion;
  final Uint8List? _key;
  final http.Client _client;
  bool _closed = false, _loaded = false;
  Future<RemoteCatalogResult?>? _pending;
  Completer<void>? _abort;
  _Cached? _cached;

  /// Last reason a load or check failed, for diagnostics.
  String? lastError;

  /// True when the last failure was a `minApp` gate.
  bool needsNewerApp = false;

  /// False while the placeholder (or a malformed) key is compiled in: the
  /// client then neither contacts the host nor trusts any cache.
  bool get usable => _key != null;

  Uri get manifestUrl => url.resolve(CatalogManifest.fileName);

  /// Cache reads perform no network work and are bounded. The cached
  /// manifest signature and payload hash are re-verified every time, so a
  /// tampered or half-written cache is ignored instead of trusted.
  Future<RemoteCatalogResult?> loadCached({Catalog? bundled}) async {
    if (!usable || _closed) return null;
    try {
      final dir = await cacheDir();
      final meta = File('${dir.path}/$metaFile');
      if (!await meta.exists() || await meta.length() > 128 * 1024) {
        return null;
      }
      final m = jsonDecode(utf8.decode(await meta.readAsBytes()));
      if (m is! Map || m['origin'] != url.toString()) return null;
      final name = m['payload'];
      if (name is! String || !_payloadCache.hasMatch(name)) return null;
      final manifest = base64.decode(m['manifest'] as String);
      final sig = base64.decode(m['sig'] as String);
      final file = File('${dir.path}/$name');
      if (!await file.exists() || await file.length() > maxBytes) return null;
      final payload = await file.readAsBytes();
      if (_closed) return null;
      final result = await _open(manifest, sig, payload, bundled);
      if (result == null || _closed) return null;
      final parsed = CatalogManifest.parse(Uint8List.fromList(manifest))!;
      _cached = _Cached(parsed, m['etag'] as String?, result);
      return result;
    } catch (_) {
      return null;
    } finally {
      _loaded = true;
    }
  }

  /// Downloads, verifies and atomically caches a staged document. Registry
  /// adoption belongs to CatalogStore, after a successful durable write.
  /// Returns the cached content (`changed == false`) when nothing is newer.
  Future<RemoteCatalogResult?> fetch({Catalog? bundled}) {
    if (_closed || !usable) return Future.value();
    return _pending ??= _fetch(bundled).whenComplete(() => _pending = null);
  }

  Future<RemoteCatalogResult?> _fetch(Catalog? bundled) async {
    final abort = Completer<void>();
    _abort = abort;
    final created = <File>[];
    try {
      lastError = null;
      needsNewerApp = false;
      if (!_loaded) await loadCached(bundled: bundled);
      if (_closed) return null;
      final cached = _cached;
      final clock = Stopwatch()..start();

      final first = await _get(
        manifestUrl,
        limit: CatalogManifest.maxBytes,
        clock: clock,
        abort: abort,
        headers: {'if-none-match': ?cached?.etag},
      );
      if (first.status == 304) {
        if (cached != null) return cached.result.unchanged();
        throw const CatalogRejected('304 without a cached catalog');
      }
      final manifestBytes = first.body;
      final sigRes = await _get(
        url.resolve('${CatalogManifest.fileName}.sig'),
        limit: 512,
        clock: clock,
        abort: abort,
      );
      final manifest = await _verifyManifest(
        manifestBytes,
        sigRes.body,
        await _appVersion(),
      );
      if (cached != null) {
        final order = manifest.compareTo(cached.manifest);
        if (order < 0) {
          lastError = 'Ignored a stale catalog (revision ${manifest.revision})';
          return cached.result.unchanged();
        }
        if (order == 0) return cached.result.unchanged();
      }

      final dir = await cacheDir();
      Uint8List payload;
      if (cached != null && cached.manifest.sha256 == manifest.sha256) {
        payload = await File('${dir.path}/${_payloadName(manifest)}').readAsBytes();
      } else {
        payload = (await _get(
          url.resolve(manifest.payload),
          limit: manifest.size,
          clock: clock,
          abort: abort,
        )).body;
      }
      if (_closed) return null;
      final result = await _open(manifestBytes, sigRes.body, payload, bundled);
      if (result == null || _closed) return null;

      await dir.create(recursive: true);
      final payloadFile = File('${dir.path}/${_payloadName(manifest)}');
      if (!await payloadFile.exists()) {
        final tmp = File('${payloadFile.path}.tmp');
        created.add(tmp);
        await tmp.writeAsBytes(payload, flush: true);
        await tmp.rename(payloadFile.path);
      }
      final metaTmp = File('${dir.path}/$metaFile.tmp');
      created.add(metaTmp);
      await metaTmp.writeAsString(
        jsonEncode({
          'v': 1,
          'origin': url.toString(),
          'etag': first.etag,
          'manifest': base64.encode(manifestBytes),
          'sig': base64.encode(sigRes.body),
          'payload': _payloadName(manifest),
        }),
        flush: true,
      );
      if (_closed) return null;
      await metaTmp.rename('${dir.path}/$metaFile');
      _cached = _Cached(manifest, first.etag, result);
      unawaited(_prune(dir, _payloadName(manifest)));
      return result;
    } on CatalogRejected catch (e) {
      lastError = e.reason;
      needsNewerApp = e.needsNewerApp;
      return null;
    } catch (e) {
      lastError = '$e';
      return null;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
      for (final f in created) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  static String _payloadName(CatalogManifest m) =>
      'remote_catalog.${m.sha256}.payload';

  /// Removes superseded payloads (and the pre-signature cache file).
  Future<void> _prune(Directory dir, String keep) async {
    try {
      await for (final e in dir.list()) {
        final name = e.uri.pathSegments.last;
        if (e is File &&
            name != keep &&
            (_payloadCache.hasMatch(name) || name == 'remote_catalog.json')) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  Future<String?> _appVersion() async {
    final read = appVersion;
    if (read == null) return null;
    return await read() ?? '0.0.0';
  }

  Future<RemoteCatalogResult?> _open(
    List<int> manifest,
    List<int> sig,
    Uint8List payload,
    Catalog? bundled,
  ) async {
    final key = _key!, ids = _bundledIds(bundled);
    final version = await _appVersion();
    final m = Uint8List.fromList(manifest), s = Uint8List.fromList(sig);
    try {
      return await Isolate.run(
        () => open(
          manifest: m,
          signature: s,
          payload: payload,
          publicKey: key,
          bundledIds: ids,
          appVersion: version,
        ),
      );
    } on CatalogRejected catch (e) {
      lastError = e.reason;
      needsNewerApp = e.needsNewerApp;
      return null;
    }
  }

  Future<CatalogManifest> _verifyManifest(
    Uint8List manifest,
    Uint8List sig,
    String? version,
  ) {
    final key = _key!;
    return Isolate.run(
      () => checkManifest(manifest, sig, key, appVersion: version),
    );
  }

  /// Signature, structure and `minApp` gate. Throws [CatalogRejected].
  static Future<CatalogManifest> checkManifest(
    Uint8List manifestBytes,
    List<int> signatureFile,
    List<int> publicKey, {
    String? appVersion,
  }) async {
    final sig = CatalogManifest.decodeSignature(signatureFile);
    if (sig == null ||
        !await CatalogManifest.verify(manifestBytes, sig, publicKey)) {
      throw const CatalogRejected('Manifest signature is not valid');
    }
    final m = CatalogManifest.parse(manifestBytes);
    if (m == null) throw const CatalogRejected('Manifest is malformed');
    if (appVersion != null &&
        CatalogManifest.compareVersions(appVersion, m.minApp) < 0) {
      throw CatalogRejected(
        'Catalog needs Glyph ${m.minApp} or newer',
        needsNewerApp: true,
      );
    }
    return m;
  }

  /// The only path from downloaded bytes to a catalog: verify the manifest
  /// signature, then the payload size and SHA-256, and only then parse.
  /// Pure and isolate-safe. Throws [CatalogRejected].
  static Future<RemoteCatalogResult> open({
    required Uint8List manifest,
    required List<int> signature,
    required Uint8List payload,
    required List<int> publicKey,
    Set<String> bundledIds = const {},
    String? appVersion,
  }) async {
    final m = await checkManifest(
      manifest,
      signature,
      publicKey,
      appVersion: appVersion,
    );
    if (payload.length != m.size) {
      throw const CatalogRejected('Payload size does not match the manifest');
    }
    if (CatalogManifest.sha256Hex(payload) != m.sha256) {
      throw const CatalogRejected('Payload hash does not match the manifest');
    }
    final r = _parse(payload, bundledIds, m.revoked.toSet());
    if (r == null) throw const CatalogRejected('Payload is not a valid catalog');
    return RemoteCatalog._stamp(r, m);
  }

  static RemoteCatalogResult _stamp(RemoteCatalogResult r, CatalogManifest m) =>
      RemoteCatalogResult(
        r.catalog,
        r.dropped,
        m.revision,
        r.sprites,
        epoch: m.epoch,
        revoked: m.revoked.toSet(),
        published: m.published,
      );

  static Set<String> _bundledIds(Catalog? bundled) =>
      bundled == null ? const {} : {for (final i in bundled.items) i.id};

  /// Capped, redirect-checked GET. Redirects stay on https and on the same
  /// host or GitHub Pages; the body is cut off at [limit] decoded bytes, so
  /// a compressed bomb cannot expand past it.
  Future<_Response> _get(
    Uri uri, {
    required int limit,
    required Stopwatch clock,
    required Completer<void> abort,
    Map<String, String> headers = const {},
  }) async {
    final origin = uri;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      var remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('Catalog timed out');
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers.addAll(headers);
      final res = await _client.send(request).timeout(remaining);
      Future<void> drop() => res.stream.listen((_) {}).cancel();
      if (const {301, 302, 303, 307, 308}.contains(res.statusCode)) {
        await drop();
        final location = res.headers['location'];
        final next = location == null ? null : origin.resolve(location);
        if (next == null || !allowedRedirect(origin, next)) {
          throw CatalogRejected('Redirect to ${next ?? 'nowhere'} refused');
        }
        uri = next;
        continue;
      }
      if (res.statusCode == 304) {
        await drop();
        return _Response(304, Uint8List(0), res.headers['etag']);
      }
      if (res.statusCode != 200) {
        await drop();
        throw CatalogRejected('HTTP ${res.statusCode} from ${uri.host}');
      }
      if ((res.contentLength ?? 0) > limit) {
        await drop();
        throw const CatalogRejected('Response is too large');
      }
      remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        await drop();
        throw TimeoutException('Catalog timed out');
      }
      return _Response(200, await _readBody(res.stream, remaining, limit), res.headers['etag']);
    }
    throw const CatalogRejected('Too many redirects');
  }

  /// Redirect policy: https only, no credentials, same host as the original
  /// request or a GitHub Pages host.
  static bool allowedRedirect(Uri from, Uri to) =>
      to.scheme == 'https' &&
      to.userInfo.isEmpty &&
      to.host.isNotEmpty &&
      (to.host == from.host ||
          to.host == 'github.io' ||
          to.host.endsWith('.github.io'));

  Future<Uint8List> _readBody(
    Stream<List<int>> stream,
    Duration remaining,
    int limit,
  ) async {
    final done = Completer<Uint8List>(), bytes = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> sub;
    void fail(Object e) {
      if (done.isCompleted) return;
      done.completeError(e);
      unawaited(sub.cancel());
    }

    sub = stream.listen(
      (chunk) {
        if (bytes.length + chunk.length > limit) {
          fail(const CatalogRejected('Response is too large'));
        } else {
          bytes.add(chunk);
        }
      },
      onError: fail,
      onDone: () {
        if (!done.isCompleted) done.complete(bytes.takeBytes());
      },
    );
    final timer = Timer(
      remaining,
      () => fail(TimeoutException('Catalog timed out')),
    );
    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  void close() {
    _closed = true;
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _client.close();
  }

  static final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static final _colour = RegExp(
    r'^(?:#|t:#)[0-9a-fA-F]{6}$|^[pc]:[0-9]+(?:\.[0-9]+)?(?:\*[0-9]+(?:\.[0-9]+)?)?!?$',
  );

  /// Parses an UNVERIFIED payload (build tooling and tests). The app only
  /// reaches a catalog through [open]. Entries are accepted or dropped one
  /// by one; only schema and resource-limit violations reject the document.
  ///
  /// Items whose id already exists in [bundled] are ignored (a download
  /// cannot change bundled metadata), and anything in [revoked] is hidden.
  static RemoteCatalogResult? parse(
    String body, {
    Catalog? bundled,
    Set<String> revoked = const {},
  }) {
    if (body.length > maxBytes) return null;
    final bytes = utf8.encode(body);
    if (bytes.length > maxBytes) return null;
    return _parse(Uint8List.fromList(bytes), _bundledIds(bundled), revoked);
  }

  static RemoteCatalogResult? _parse(
    Uint8List bytes,
    Set<String> bundledIds,
    Set<String> revoked,
  ) {
    try {
      if (bytes.length > maxBytes) return null;
      final doc = jsonDecode(utf8.decode(bytes));
      if (doc is! Map<String, dynamic> ||
          doc['version'] != Catalog.currentVersion ||
          doc['revision'] is! int ||
          doc['revision'] < 1 ||
          doc['revision'] > 0x7fffffff ||
          doc['items'] is! List ||
          (doc['items'] as List).length > maxItems) {
        return null;
      }
      // Prevent deeply nested extension data and oversized collection casts.
      var nodes = 0;
      void tree(Object? v, int depth) {
        if (++nodes > 250000 || depth > 16) {
          throw const FormatException('Document complexity');
        }
        if (v is String && v.length > 8192) {
          throw const FormatException('String too long');
        }
        if (v is List) {
          if (v.length > maxItems) throw const FormatException('List too long');
          for (final e in v) {
            tree(e, depth + 1);
          }
        } else if (v is Map) {
          if (v.length > maxItems) throw const FormatException('Map too large');
          for (final e in v.entries) {
            tree(e.key, depth + 1);
            tree(e.value, depth + 1);
          }
        }
      }

      tree(doc, 0);
      final packs = doc['sprites'] as List? ?? const [];
      if (packs.length > 32) return null;
      final dropped = <String>[];
      void drop(String why) {
        if (dropped.length < maxDropped) dropped.add(why);
      }

      final staged = <String, SpriteGenerator>{};
      final blocked = <String>{};
      var spriteCount = 0, frameCount = 0, pixels = 0;
      for (final rawPack in packs) {
        if (rawPack is! Map || rawPack['sprites'] is! List) {
          drop('pack: malformed');
          continue;
        }
        final pack = rawPack.cast<String, dynamic>();
        final rawSprites = pack['sprites'] as List;
        spriteCount += rawSprites.length;
        if (spriteCount > maxSprites) return null;
        for (final raw in rawSprites) {
          final s = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
          final id = 'sprite:${s['id']}';
          try {
            if (raw is! Map) throw const FormatException('malformed sprite');
            final count = _checkSprite(pack, s);
            frameCount += count.$1;
            pixels += count.$2;
            if (frameCount > maxFrames || pixels > maxDecodedPixels) {
              return null;
            }
            final sprite = Sprite.parsePackJson({
              ...pack,
              'sprites': [s],
            }).single;
            final g = SpriteGenerator(sprite);
            if (staged.containsKey(id) || blocked.contains(id)) {
              staged.remove(id);
              blocked.add(id);
              throw const FormatException('duplicate sprite ID');
            }
            if (revoked.contains(id)) continue;
            final existing = SpriteLibrary.isBundled(id)
                ? SpriteLibrary.byId(id)
                : null;
            if (existing != null && !sprite.sameDrawing(existing.sprite)) {
              throw const FormatException('conflicts with a bundled drawing');
            }
            staged[id] = g;
          } catch (e) {
            blocked.add(id);
            drop('$id: $e');
          }
        }
      }
      final items = <LibraryItem>[], seen = <String>{};
      for (final raw in doc['items'] as List) {
        try {
          final item = LibraryItem.fromJson(
            (raw as Map).cast<String, dynamic>(),
          );
          if (!seen.add(item.id)) {
            throw FormatException('${item.id}: duplicate id');
          }
          // Bundled metadata is authoritative; takedowns go via `revoked`.
          if (bundledIds.contains(item.id) || item.revokedBy(revoked)) continue;
          final g = blocked.contains(item.generatorId)
              ? null
              : staged[item.generatorId] ??
                    (item.isPixelArt &&
                            !SpriteLibrary.isBundled(item.generatorId)
                        ? null
                        : findGenerator(item.generatorId));
          final checked = validate(item, dropped, generator: g);
          if (checked != null) items.add(checked);
        } catch (e) {
          drop('item: $e');
        }
      }
      final categories = <String>[];
      for (final c in doc['categories'] as List? ?? const []) {
        if (c is String && c.length <= 80 && categories.length < 64) {
          categories.add(c);
        } else {
          drop('category: invalid');
        }
      }
      final used = items.map((i) => i.generatorId).toSet();
      return RemoteCatalogResult(
        Catalog(
          items: List.unmodifiable(items),
          categories: [
            for (final c in categories.toSet())
              if (items.any((i) => i.category == c)) c,
          ],
        ),
        List.unmodifiable(dropped),
        doc['revision'] as int,
        List.unmodifiable(
          staged.values.where(
            (g) => used.contains(g.id) && !SpriteLibrary.isBundled(g.id),
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static (int, int) _checkSprite(
    Map<String, dynamic> pack,
    Map<String, dynamic> s,
  ) {
    if (s['id'] is! String ||
        !_idPattern.hasMatch(s['id'] as String) ||
        (s['id'] as String).length > 100) {
      throw const FormatException('bad sprite ID');
    }
    int grid(Object? value) {
      final rows = value as List;
      if (rows.isEmpty || rows.length > 64) {
        throw const FormatException('bad sprite height');
      }
      final width = (rows.first as String).length;
      if (width == 0 ||
          width > 256 ||
          width * rows.length > 8192 ||
          rows.any((r) => r is! String || r.length != width)) {
        throw const FormatException('bad sprite rows');
      }
      return width * rows.length;
    }

    final parts = pack['parts'] as Map? ?? const {};
    if (parts.length > 128) throw const FormatException('too many parts');
    final partSizes = {for (final e in parts.entries) e.key: grid(e.value)};
    final sizes = <int>[];
    final frames = s['frames'] as List;
    if (frames.isEmpty || frames.length > 64) {
      throw const FormatException('bad frame count');
    }
    for (final f in frames) {
      if (f is List) {
        sizes.add(grid(f));
      } else {
        final spec = f as Map;
        final size = switch (spec['base']) {
          int i when i >= 0 && i < sizes.length => sizes[i],
          String name when partSizes.containsKey(name) => partSizes[name]!,
          _ => throw const FormatException('unknown frame base'),
        };
        sizes.add(size);
        if (spec['flip'] != null &&
            spec['flip'] != 'h' &&
            spec['flip'] != 'v') {
          throw const FormatException('unsupported flip');
        }
        final patches = spec['patch'] as List? ?? const [];
        if (patches.length > 64) {
          throw const FormatException('too many patches');
        }
        for (final p in patches) {
          final rows = (p as Map)['rows'] as List;
          if (rows.length > 64 ||
              rows.any((r) => r is! String || r.length > 256)) {
            throw const FormatException('patch too large');
          }
        }
      }
    }
    final seq = s['seq'] as List?;
    if (seq != null && (seq.isEmpty || seq.length > 256)) {
      throw const FormatException('bad sequence');
    }
    final ms = s['ms'];
    for (final m in ms is List ? ms : [ms ?? 200]) {
      if (m is! num || !m.isFinite || m < 20 || m > 10000) {
        throw const FormatException('bad frame duration');
      }
    }
    final colors = {...?pack['colors'] as Map?, ...?s['colors'] as Map?};
    if (colors.length > 128) throw const FormatException('too many colours');
    for (final e in colors.entries) {
      if (e.key is! String ||
          (e.key as String).length != 1 ||
          e.value is! String ||
          !_colour.hasMatch(e.value as String)) {
        throw const FormatException('unsupported colour');
      }
      final v = e.value as String;
      if (v.startsWith('p:') || v.startsWith('c:')) {
        final terms = v
            .substring(2)
            .replaceAll('!', '')
            .split('*')
            .map(double.parse);
        if (terms.any((n) => !n.isFinite || n > 10)) {
          throw const FormatException('colour range');
        }
      }
    }
    if (!spriteMotionNames.contains(s['motion'] ?? 'still')) {
      throw const FormatException('unsupported motion');
    }
    final backdrop = s['backdrop'] ?? 0;
    if (backdrop is! num ||
        !backdrop.isFinite ||
        backdrop < 0 ||
        backdrop > 1) {
      throw const FormatException('bad backdrop');
    }
    if (s['source'] != null) {
      final source = s['source'] as Map;
      if (source.length > 32 ||
          source.entries.any(
            (e) => e.key == 'year'
                ? e.value != null && e.value is! int
                : e.value is! String || (e.value as String).length > 4096,
          )) {
        throw const FormatException('bad attribution');
      }
    }
    return (frames.length, sizes.fold(0, (a, b) => a + b));
  }

  static LibraryItem? validate(
    LibraryItem item,
    List<String> dropped, {
    Generator? generator,
  }) {
    String? problem;
    if (!_idPattern.hasMatch(item.id) || item.id.length > 100) {
      problem = 'bad id';
    }
    if (item.title.trim().isEmpty ||
        item.title.length > 160 ||
        item.category.trim().isEmpty ||
        item.category.length > 80 ||
        item.tags.length > 32 ||
        item.tags.any((t) => t.length > 160) ||
        (item.notice?.length ?? 0) > 4096) {
      problem = 'bad metadata';
    }
    if (generator == null) {
      problem = 'unknown or incompatible generator ${item.generatorId}';
    }
    if (item.asset != null) {
      problem = 'asset type ${item.asset!.type} is not supported by this build';
    }
    if (!palettes.any((p) => p.id == item.paletteId)) {
      problem = 'unknown palette ${item.paletteId}';
    }
    if (item.params.values.any((v) => !v.isFinite) ||
        (item.speed != null && !item.speed!.isFinite)) {
      problem = 'non-finite parameters';
    }
    if (problem != null) {
      dropped.add('${item.id}: $problem');
      return null;
    }
    final specs = {for (final s in generator!.params) s.key: s};
    return LibraryItem(
      id: item.id,
      title: item.title.trim(),
      category: item.category.trim(),
      generatorId: item.generatorId,
      paletteId: item.paletteId,
      tags: item.tags,
      params: {
        for (final MapEntry(:key, :value) in item.params.entries)
          if (specs[key] case final s?)
            key: value.clamp(s.min, s.max).toDouble(),
      },
      speed: item.speed?.clamp(0.1, 4).toDouble(),
      featured: item.featured,
      added: item.added,
      notice:
          item.notice ??
          (generator is SpriteGenerator ? generator.sprite.notice : null),
    );
  }
}

class _Response {
  const _Response(this.status, this.body, this.etag);
  final int status;
  final Uint8List body;
  final String? etag;
}

class _Cached {
  const _Cached(this.manifest, this.etag, this.result);
  final CatalogManifest manifest;
  final String? etag;
  final RemoteCatalogResult result;
}
