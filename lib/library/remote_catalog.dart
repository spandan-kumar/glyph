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

/// A staged document. Parsing never changes the runtime registry.
class RemoteCatalogResult {
  const RemoteCatalogResult(
    this.catalog,
    this.dropped,
    this.revision,
    this.sprites,
  );
  final Catalog catalog;
  final List<String> dropped;
  final int revision;
  final List<SpriteGenerator> sprites;
}

class RemoteCatalog {
  RemoteCatalog({
    required this.url,
    required this.cacheDir,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  // Enable only after the Pages artifact has been deployed and verified.
  static const String? defaultUrl = null;
  static const cacheFile = 'remote_catalog.json';
  static const maxBytes = 2 * 1024 * 1024;
  static const maxItems = 2000, maxSprites = 512, maxFrames = 8192;
  static const maxDecodedPixels = 2 * 1024 * 1024;
  final Uri url;
  final Future<Directory> Function() cacheDir;
  final Duration timeout;
  final http.Client _client;
  bool _closed = false;
  Future<RemoteCatalogResult?>? _pending;
  Completer<void>? _abort;

  /// Cache reads perform no network work and are bounded too. Binding the
  /// cache to its source prevents a host change from reusing another feed.
  Future<RemoteCatalogResult?> loadCached({Catalog? bundled}) async {
    try {
      final f = File('${(await cacheDir()).path}/$cacheFile');
      if (_closed || !await f.exists() || await f.length() > maxBytes + 1024) {
        return null;
      }
      final bytes = await f
          .openRead(0, maxBytes + 1025)
          .fold<List<int>>([], (a, b) => a..addAll(b));
      if (bytes.length > maxBytes + 1024 || _closed) return null;
      final doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (doc.remove('_origin') != url.toString()) return null;
      return await _decode(jsonEncode(doc), bundled, _runtimeSprites());
    } catch (_) {
      return null;
    }
  }

  /// Downloads, validates and atomically caches a staged document. Registry
  /// adoption belongs to CatalogStore, after a successful durable write.
  Future<RemoteCatalogResult?> fetch({Catalog? bundled}) {
    if (_closed) return Future.value();
    return _pending ??= _fetch(bundled).whenComplete(() => _pending = null);
  }

  Future<RemoteCatalogResult?> _fetch(Catalog? bundled) async {
    File? tmp;
    final abort = Completer<void>();
    _abort = abort;
    try {
      final clock = Stopwatch()..start();
      final request = http.AbortableRequest(
        'GET',
        url,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final res = await _client.send(request).timeout(timeout);
      if (res.statusCode != 200 || (res.contentLength ?? 0) > maxBytes) {
        await res.stream.listen((_) {}).cancel();
        return null;
      }
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) return null;
      final bytes = await _readBody(res.stream, remaining);
      if (_closed) return null;
      final body = utf8.decode(bytes);
      final result = await _decode(body, bundled, _runtimeSprites());
      if (result == null) return null;
      final dir = await cacheDir();
      if (_closed) return null;
      await dir.create(recursive: true);
      tmp = File('${dir.path}/$cacheFile.tmp');
      final cache = {
        ...jsonDecode(body) as Map<String, dynamic>,
        '_origin': url.toString(),
      };
      await tmp.writeAsString(jsonEncode(cache), flush: true);
      if (_closed) return null;
      await tmp.rename('${dir.path}/$cacheFile');
      return result;
    } catch (_) {
      return null;
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_abort, abort)) _abort = null;
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<Uint8List> _readBody(
    Stream<List<int>> stream,
    Duration remaining,
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
        if (bytes.length + chunk.length > maxBytes) {
          fail(const FormatException('Catalog is too large'));
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

  static RemoteCatalogResult? parse(
    String body, {
    Catalog? bundled,
    List<SpriteGenerator> existingSprites = const [],
  }) {
    try {
      if (body.length > maxBytes || utf8.encode(body).length > maxBytes) {
        return null;
      }
      final doc = jsonDecode(body);
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
      final staged = <String, SpriteGenerator>{};
      final blocked = <String>{};
      var spriteCount = 0, frameCount = 0, pixels = 0;
      for (final rawPack in packs) {
        final pack = (rawPack as Map).cast<String, dynamic>();
        final rawSprites = pack['sprites'] as List;
        spriteCount += rawSprites.length;
        if (spriteCount > maxSprites) return null;
        for (final raw in rawSprites) {
          final s = (raw as Map).cast<String, dynamic>();
          final id = 'sprite:${s['id']}';
          try {
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
            final g = SpriteGenerator(sprite),
                existing =
                    existingSprites.where((g) => g.id == id).firstOrNull ??
                    SpriteLibrary.byId(id);
            if (staged.containsKey(id) || blocked.contains(id)) {
              staged.remove(id);
              blocked.add(id);
              throw const FormatException('duplicate sprite ID');
            }
            if (existing != null && !sprite.sameDrawing(existing.sprite)) {
              // Retain the good cache too: a cold restart must not accept
              // conflicting art after losing the registry's older identity.
              return null;
            }
            staged[id] = g;
          } catch (e) {
            blocked.add(id);
            dropped.add('$id: $e');
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
          final old = bundled?.byId(item.id);
          if (old != null && old.generatorId != item.generatorId) {
            return null;
          }
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
          dropped.add('item: $e');
        }
      }
      if (items.isEmpty) return null;
      final categories = [
        for (final c in doc['categories'] as List? ?? const []) c as String,
      ];
      if (categories.length > 64 || categories.any((c) => c.length > 80)) {
        return null;
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

List<SpriteGenerator> _runtimeSprites() =>
    SpriteLibrary.all.where((g) => !SpriteLibrary.isBundled(g.id)).toList();

Future<RemoteCatalogResult?> _decode(
  String body,
  Catalog? bundled,
  List<SpriteGenerator> existing,
) => Isolate.run(
  () => RemoteCatalog.parse(body, bundled: bundled, existingSprites: existing),
);
