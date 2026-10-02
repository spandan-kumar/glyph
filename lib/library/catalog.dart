import 'dart:convert';

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
    this.params = const {},
    this.speed,
    this.asset,
  });

  final String id;
  final String title;
  final String category;
  final List<String> tags;
  final String generatorId;
  final Map<String, double> params;
  final String paletteId;

  /// Playback-rate multiplier; null means 1.
  final double? speed;
  final LibraryAsset? asset;

  factory LibraryItem.fromJson(Map<String, dynamic> j) => LibraryItem(
        id: j['id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        tags: [for (final t in (j['tags'] as List? ?? const [])) t as String],
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        if (tags.isNotEmpty) 'tags': tags,
        'generator': generatorId,
        if (params.isNotEmpty) 'params': params,
        'palette': paletteId,
        if (speed != null) 'speed': speed,
        if (asset != null) 'asset': asset!.toJson(),
      };

  bool _matches(String token) =>
      title.toLowerCase().contains(token) ||
      category.toLowerCase().contains(token) ||
      generatorId.contains(token) ||
      paletteId.contains(token) ||
      tags.any((t) => t.toLowerCase().contains(token));
}

class Catalog {
  Catalog({this.version = currentVersion, required this.items, List<String>? categories})
      : categories = _categories(items, categories);

  static const currentVersion = 1;

  final int version;
  final List<LibraryItem> items;

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

  /// Items whose title, category, tags, generator or palette contain every
  /// word of [q]. Title matches sort first.
  List<LibraryItem> search(String q) {
    final tokens =
        q.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (tokens.isEmpty) return List.of(items);
    final hits = items.where((i) => tokens.every(i._matches)).toList();
    int rank(LibraryItem i) {
      final title = i.title.toLowerCase();
      if (title.startsWith(tokens.first)) return 0;
      if (tokens.every(title.contains)) return 1;
      return 2;
    }

    // Stable sort by rank, keeping catalog order within a rank.
    final order = {for (var k = 0; k < hits.length; k++) hits[k]: k};
    hits.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : order[a]!.compareTo(order[b]!);
    });
    return hits;
  }

  List<LibraryItem> inCategory(String c) =>
      items.where((i) => i.category == c).toList();

  LibraryItem? byId(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Overlays [other] (e.g. a server catalog) on this one; items with the same
  /// id are replaced, new ones appended.
  Catalog merge(Catalog other) {
    final merged = {for (final i in items) i.id: i, for (final i in other.items) i.id: i};
    return Catalog(
      version: other.version > version ? other.version : version,
      items: merged.values.toList(),
      categories: [...categories, ...other.categories.where((c) => !categories.contains(c))],
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
