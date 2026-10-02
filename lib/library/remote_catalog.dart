import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../engine/generators/sprite_library.dart';
import '../engine/palette.dart';
import '../engine/registry.dart';
import 'catalog.dart';

/// Result of checking a downloaded catalog against what this build knows.
class RemoteCatalogResult {
  const RemoteCatalogResult(this.catalog, this.dropped);

  final Catalog catalog;

  /// Human-readable reasons for every entry that was skipped.
  final List<String> dropped;
}

/// Fetches extra library items from a server so the library can grow without
/// an app update, caches the last good copy on disk, and overlays it on the
/// bundled catalog.
///
/// The JSON is the normal catalog format, plus an optional `"sprites"` list of
/// sprite packs (same format as assets/catalog/sprites/*.json) that the items
/// may reference as `sprite:<id>`. Items pointing at generators, palettes or
/// sprites this build doesn't have are dropped; params are clamped.
///
/// No server exists yet: [defaultUrl] is null, and callers should skip remote
/// loading entirely while it is.
class RemoteCatalog {
  RemoteCatalog({
    required this.url,
    required this.cacheDir,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  /// Where the hosted catalog will live, e.g.
  /// `https://example.com/glyph/catalog-v1.json`. Leave null until hosting
  /// exists.
  static const String? defaultUrl = null;

  static const cacheFile = 'remote_catalog.json';

  final Uri url;
  final Future<Directory> Function() cacheDir;
  final Duration timeout;
  final http.Client _client;

  /// The last successfully fetched catalog, if any. Never throws.
  Future<RemoteCatalogResult?> loadCached() async {
    try {
      final f = File('${(await cacheDir()).path}/$cacheFile');
      if (!await f.exists()) return null;
      return parse(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Downloads, validates and caches the catalog. Returns null on any network
  /// or format failure, leaving the cache untouched.
  Future<RemoteCatalogResult?> fetch() async {
    try {
      final res = await _client.get(url).timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = utf8.decode(res.bodyBytes);
      final result = parse(body);
      if (result == null) return null;
      final dir = await cacheDir();
      await dir.create(recursive: true);
      // Write then rename so a crash never leaves a half-written cache.
      final tmp = File('${dir.path}/$cacheFile.tmp');
      await tmp.writeAsString(body, flush: true);
      await tmp.rename('${dir.path}/$cacheFile');
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Bundled catalog with the cached remote one on top; then refreshes in the
  /// background and calls [onUpdate] if a newer copy arrives.
  Future<Catalog> overlay(Catalog bundled, {void Function(Catalog)? onUpdate}) async {
    final cached = await loadCached();
    final base = cached == null ? bundled : bundled.merge(cached.catalog);
    unawaited(fetch().then((fresh) {
      if (fresh != null && onUpdate != null) onUpdate(bundled.merge(fresh.catalog));
    }));
    return base;
  }

  void close() => _client.close();

  static final _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// Validates a catalog document. Returns null if it isn't a catalog at all.
  static RemoteCatalogResult? parse(String body) {
    final Object? doc;
    try {
      doc = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (doc is! Map<String, dynamic> || doc['items'] is! List) return null;
    final dropped = <String>[];

    // Sprite packs first, so items can reference them.
    for (final pack in (doc['sprites'] as List? ?? const [])) {
      try {
        SpriteLibrary.register((pack as Map).cast<String, dynamic>());
      } catch (e) {
        dropped.add('sprite pack: $e');
      }
    }

    final items = <LibraryItem>[];
    final seen = <String>{};
    for (final raw in doc['items'] as List) {
      final LibraryItem item;
      try {
        item = LibraryItem.fromJson((raw as Map).cast<String, dynamic>());
      } catch (e) {
        dropped.add('malformed item: $e');
        continue;
      }
      final checked = validate(item, dropped);
      if (checked == null) continue;
      if (!seen.add(checked.id)) {
        dropped.add('${checked.id}: duplicate id');
        continue;
      }
      items.add(checked);
    }
    final declared = [for (final c in (doc['categories'] as List? ?? const [])) if (c is String) c];
    return RemoteCatalogResult(
      Catalog(
        version: (doc['version'] as num?)?.toInt() ?? Catalog.currentVersion,
        items: items,
        // Only keep declared categories that still have items.
        categories: [for (final c in declared) if (items.any((i) => i.category == c)) c],
      ),
      dropped,
    );
  }

  /// Returns [item] with params clamped to the generator's ranges, or null
  /// (with a reason added to [dropped]) if this build can't play it.
  static LibraryItem? validate(LibraryItem item, List<String> dropped) {
    if (!_idPattern.hasMatch(item.id)) {
      dropped.add('${item.id}: bad id');
      return null;
    }
    if (item.title.trim().isEmpty || item.category.trim().isEmpty) {
      dropped.add('${item.id}: missing title or category');
      return null;
    }
    final g = findGenerator(item.generatorId);
    if (g == null) {
      dropped.add('${item.id}: unknown generator ${item.generatorId}');
      return null;
    }
    if (!palettes.any((p) => p.id == item.paletteId)) {
      dropped.add('${item.id}: unknown palette ${item.paletteId}');
      return null;
    }
    final specs = {for (final s in g.params) s.key: s};
    final params = <String, double>{
      for (final MapEntry(:key, :value) in item.params.entries)
        if (specs[key] case final s?) key: value.clamp(s.min, s.max).toDouble(),
    };
    return LibraryItem(
      id: item.id,
      title: item.title.trim(),
      category: item.category.trim(),
      generatorId: item.generatorId,
      paletteId: item.paletteId,
      tags: item.tags,
      params: params,
      speed: item.speed?.clamp(0.1, 4).toDouble(),
      asset: item.asset,
      featured: item.featured,
      added: item.added,
    );
  }
}
