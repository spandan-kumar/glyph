import 'dart:convert';

import 'catalog_search.dart';

/// Pre-rendered content attached to a library item (future GIF / pixel-art
/// packs). Unknown keys are kept so newer catalogs round-trip intact.
class LibraryAsset {
  const LibraryAsset({
    required this.type,
    required this.url,
    this.license,
    this.author,
    this.extra = const {},
  });

  final String type; // e.g. "gif", "pixels"
  final String url;
  final String? license;
  final String? author;
  final Map<String, dynamic> extra;

  factory LibraryAsset.fromJson(Map<String, dynamic> j) => LibraryAsset(
        type: j['type'] as String,
        url: j['url'] as String,
        license: j['license'] as String?,
        author: j['author'] as String?,
        extra: {
          for (final e in j.entries)
            if (!const {'type', 'url', 'license', 'author'}.contains(e.key))
              e.key: e.value,
        },
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'type': type,
        'url': url,
        if (license != null) 'license': license,
        if (author != null) 'author': author,
      };
}

/// One entry in the animation library: a named, tuned generator setup.
class LibraryItem {
  const LibraryItem({
    required this.id,
    required this.title,
    required this.category,
    required this.generatorId,
    required this.paletteId,
    this.tags = const [],
    this.aliases = const [],
    this.subjects = const [],
    this.collection,
    this.params = const {},
    this.speed,
    this.asset,
    this.featured,
    this.added = 0,
    this.notice,
  });

  final String id;
  final String title;
  final String category;
  final List<String> tags;
  /// Reviewed alternate names and concrete subjects, separate from mood tags.
  final List<String> aliases, subjects;
  final String? collection;
  final String generatorId;
  final Map<String, double> params;
  final String paletteId;

  /// Playback-rate multiplier; null means 1.
  final double? speed;
  final LibraryAsset? asset;

  /// Editorial rank for the Featured shelf (lower first); null = not featured.
  final int? featured;

  /// Catalog revision the item arrived in; drives "New" sorting.
  final int added;

  /// Attribution / non-affiliation text for items based on public-domain
  /// works, shown with the item.
  final String? notice;

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        tags: [for (final t in (j['tags'] as List? ?? const [])) t as String],
        aliases: [for (final t in (j['aliases'] as List? ?? const [])) t as String],
        subjects: [for (final t in (j['subjects'] as List? ?? const [])) t as String],
        collection: j['collection'] as String?,
        generatorId: j['generator'] as String,
        params: {
          for (final e in (j['params'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toDouble(),
        },
        paletteId: j['palette'] as String,
        speed: (j['speed'] as num?)?.toDouble(),
        asset: j['asset'] == null
            ? null
            : LibraryAsset.fromJson(j['asset'] as Map<String, dynamic>),
        featured: (j['featured'] as num?)?.toInt(),
        added: (j['added'] as num?)?.toInt() ?? 0,
        notice: j['notice'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        if (tags.isNotEmpty) 'tags': tags,
        if (aliases.isNotEmpty) 'aliases': aliases,
        if (subjects.isNotEmpty) 'subjects': subjects,
        if (collection != null) 'collection': collection,
        'generator': generatorId,
        if (params.isNotEmpty) 'params': params,
        'palette': paletteId,
        if (speed != null) 'speed': speed,
        if (asset != null) 'asset': asset!.toJson(),
        if (featured != null) 'featured': featured,
        if (added != 0) 'added': added,
        if (notice != null) 'notice': notice,
      };

  bool get isPixelArt => generatorId.startsWith('sprite:') || asset?.type == 'clip-gzip';

  /// Imported clip descriptions can change while their device filename stays
  /// compatible with looks sent before the catalogue was named.
  String get deviceFileTitle => asset?.type == 'clip-gzip' &&
          RegExp(r'^imported-\d+$').hasMatch(id)
      ? 'imported ${id.substring('imported-'.length)}' : title;

  /// True when a takedown list names this item or its generator.
  bool revokedBy(Set<String> revoked) =>
      revoked.isNotEmpty &&
      (revoked.contains(id) || revoked.contains(generatorId));
}

class Catalog {
  Catalog({this.version = currentVersion, required this.items, List<String>? categories})
      : categories = _categories(items, categories);

  static const currentVersion = 1;

  final int version;
  final List<LibraryItem> items;
  late final _byId = {for (final item in items) item.id: item};
  late final _search = CatalogSearch(items);

  /// Display order: the catalog's explicit list, then any category that only
  /// appears on items, in first-seen order.
  final List<String> categories;

  static List<String> _categories(List<LibraryItem> items, List<String>? declared) {
    final out = <String>[...?declared];
    for (final i in items) {
      if (!out.contains(i.category)) out.add(i.category);
    }
    return out;
  }

  /// Local content search; every word and explicit constraint must match.
  List<LibraryItem> search(String q) => searchResults(q).items;

  CatalogSearchResult searchResults(String q) => _search.search(q);

  /// Featured items in editorial order.
  List<LibraryItem> get featured =>
      items.where((i) => i.featured != null).toList()..sort((a, b) => a.featured!.compareTo(b.featured!));

  /// Items carrying any of [tags] (case-insensitive), in catalog order.
  List<LibraryItem> tagged(Iterable<String> tags) {
    final want = {for (final t in tags) t.toLowerCase()};
    return items.where((i) => i.tags.any((t) => want.contains(t.toLowerCase()))).toList();
  }

  List<LibraryItem> inCategory(String c) =>
      items.where((i) => i.category == c).toList();

  LibraryItem? byId(String id) {
    return _byId[id];
  }

  /// Overlays [other] (the downloaded catalog) on this bundled one.
  ///
  /// Bundled items always win: a download may add items but never changes an
  /// existing item's metadata. The only way to remove or replace bundled
  /// content is [revoked] (item ids or generator ids), which hides matching
  /// items from both sides, e.g. art withdrawn after release.
  Catalog merge(Catalog other, {Set<String> revoked = const {}}) {
    final merged = <String, LibraryItem>{};
    for (final i in items) {
      if (!i.revokedBy(revoked)) merged[i.id] = i;
    }
    for (final i in other.items) {
      if (!i.revokedBy(revoked)) merged.putIfAbsent(i.id, () => i);
    }
    final live = {for (final i in merged.values) i.category};
    return Catalog(
      version: other.version > version ? other.version : version,
      items: merged.values.toList(),
      categories: [
        for (final c in [
          ...categories,
          ...other.categories.where((c) => !categories.contains(c)),
        ])
          if (revoked.isEmpty || live.contains(c)) c,
      ],
    );
  }

  static Catalog fromJson(Map<String, dynamic> j) => Catalog(
        version: (j['version'] as num?)?.toInt() ?? currentVersion,
        categories: [for (final c in (j['categories'] as List? ?? const [])) c as String],
        items: [
          for (final i in (j['items'] as List? ?? const []))
            LibraryItem.fromJson(i as Map<String, dynamic>),
        ],
      );

  static Catalog parse(String json) =>
      fromJson(jsonDecode(json) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'version': version,
        'categories': categories,
        'items': [for (final i in items) i.toJson()],
      };
}
