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
    this.featured,
    this.added = 0,
    this.notice,
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
        'generator': generatorId,
        if (params.isNotEmpty) 'params': params,
        'palette': paletteId,
        if (speed != null) 'speed': speed,
        if (asset != null) 'asset': asset!.toJson(),
        if (featured != null) 'featured': featured,
        if (added != 0) 'added': added,
        if (notice != null) 'notice': notice,
      };

  bool get isPixelArt => generatorId.startsWith('sprite:');

  /// True when a takedown list names this item or its generator.
  bool revokedBy(Set<String> revoked) =>
      revoked.isNotEmpty &&
      (revoked.contains(id) || revoked.contains(generatorId));

  /// How well [token] matches, 0 for no match. Title hits beat tag hits beat
  /// category hits beat generator/palette hits.
  int _score(String token) {
    final t = title.toLowerCase();
    if (t == token) return 100;
    if (t.startsWith(token)) return 80;
    if (t.split(RegExp(r'[^a-z0-9]+')).any((w) => w.startsWith(token))) return 60;
    if (t.contains(token)) return 40;
    var best = 0;
    for (final tag in tags) {
      final l = tag.toLowerCase();
      final s = l == token ? 35 : (l.startsWith(token) ? 28 : (l.contains(token) ? 18 : 0));
      if (s > best) best = s;
    }
    if (best > 0) return best;
    final c = category.toLowerCase();
    if (c.contains(token)) return c.startsWith(token) ? 15 : 12;
    if (generatorId.contains(token) || paletteId.contains(token)) return 5;
    return 0;
  }
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

  /// Items matching every word of [q] in their title, tags, category,
  /// generator or palette, best matches first (catalog order breaks ties).
  List<LibraryItem> search(String q) {
    final tokens =
        q.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (tokens.isEmpty) return List.of(items);
    final phrase = tokens.join(' ');
    final scored = <(LibraryItem, int, int)>[];
    for (var k = 0; k < items.length; k++) {
      final i = items[k];
      var total = 0;
      for (final t in tokens) {
        final s = i._score(t);
        if (s == 0) {
          total = -1;
          break;
        }
        total += s;
      }
      if (total < 0) continue;
      // Whole-phrase title hits ("blue flame") beat scattered word hits.
      if (tokens.length > 1 && i.title.toLowerCase().contains(phrase)) total += 50;
      scored.add((i, total, k));
    }
    scored.sort((a, b) {
      final r = b.$2.compareTo(a.$2);
      return r != 0 ? r : a.$3.compareTo(b.$3);
    });
    return [for (final s in scored) s.$1];
  }

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
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
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
