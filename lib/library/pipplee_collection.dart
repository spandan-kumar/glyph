import 'dart:convert';

import '../engine/bake_limits.dart';
import '../engine/clip_asset.dart';
import 'catalog.dart';

const pippleeIndexAsset = 'assets/catalog/pipplee.json';
const pippleeNotice = 'Shared with permission by its creator.';

List<String> _descriptionWords(dynamic value, int maximum) {
  if (value is! List ||
      value.length > maximum ||
      value.any(
        (v) =>
            v is! String ||
            v.trim().isEmpty ||
            v.length > 64 ||
            RegExp(r'[\u0000-\u001f]').hasMatch(v),
      )) {
    throw const FormatException('Invalid collection search metadata');
  }
  return value.cast<String>();
}

/// Compact bundled metadata, with every upstream ID preserved.
Catalog parsePippleeCollection(String source) {
  final doc = jsonDecode(source) as Map<String, dynamic>;
  final rows = doc['rows'] as List;
  final categorized = doc['version'] == 3;
  final named = categorized || doc['version'] == 2;
  if ((!named && doc['version'] != 1) ||
      doc['count'] != rows.length ||
      rows.length > 20000 ||
      doc['permission'] != 'maintainer-confirmed-pipplee-consent-2026-10-13') {
    throw const FormatException('Invalid imported collection index');
  }
  final categories = categorized
      ? _descriptionWords(doc['categories'], 40)
      : const ['Pipplee'];
  if (categories.isEmpty || categories.toSet().length != categories.length) {
    throw const FormatException('Invalid collection categories');
  }
  final ids = <int>{}, assets = <ClipAsset>[], items = <LibraryItem>[];
  final hash = RegExp(r'^[0-9a-f]{64}$');
  for (final raw in rows) {
    final row = raw as List;
    if (row.length != (categorized ? 12 : named ? 11 : 7)) {
      throw const FormatException('Invalid collection entry');
    }
    final id = row[0] as int, sha = row[1] as String, size = row[2] as int;
    final w = row[3] as int, h = row[4] as int, frames = row[5] as int;
    final colours = (row[6] as List).cast<String>();
    if (id <= 0 ||
        !ids.add(id) ||
        !hash.hasMatch(sha) ||
        size <= 0 ||
        size > 2 * 1024 * 1024 ||
        w <= 0 ||
        h <= 0 ||
        w > 64 ||
        h > 64 ||
        colours.length > 3 ||
        colours.any(
          (c) => !const {
            'red',
            'green',
            'blue',
            'yellow',
            'purple',
            'cyan',
            'orange',
            'white',
          }.contains(c),
        )) {
      throw const FormatException('Invalid collection metadata');
    }
    checkBakeSize(w, h, frames);
    final key = 'pipplee-$id';
    final rawTitle = named ? row[7] : 'Pipplee $id';
    if (rawTitle is! String ||
        rawTitle.trim().isEmpty ||
        rawTitle.length > 80 ||
        RegExp(r'[\u0000-\u001f]').hasMatch(rawTitle)) {
      throw const FormatException('Invalid collection name');
    }
    final title = rawTitle.trim();
    final subjects = named ? _descriptionWords(row[8], 12) : const <String>[];
    final aliases = named ? _descriptionWords(row[9], 8) : const <String>[];
    final searchTags = named
        ? _descriptionWords(row[10], 24)
        : const <String>[];
    if (named && (subjects.isEmpty || searchTags.isEmpty)) {
      throw const FormatException('Missing collection search metadata');
    }
    final category = categorized ? row[11] : 'Pipplee';
    if (category is! String || !categories.contains(category)) {
      throw const FormatException('Invalid collection category');
    }
    assets.add(
      ClipAsset(
        id: 'clip:$key',
        title: title,
        sha256: sha,
        bytes: size,
        width: w,
        height: h,
        frames: frames,
      ),
    );
    items.add(
      LibraryItem(
        id: key,
        title: title,
        category: category,
        collection: 'Imported',
        generatorId: 'clip:$key',
        paletteId: 'rainbow',
        subjects: subjects,
        aliases: aliases,
        tags: ['imported', 'pixel art', '${w}x$h', ...colours, ...searchTags],
        added: 4,
        notice: pippleeNotice,
        asset: LibraryAsset(
          type: 'clip-gzip',
          url: 'collections/pipplee/$sha.clip.gz',
          license: 'shared-with-permission',
          extra: {'sha256': sha, 'bytes': size},
        ),
      ),
    );
  }
  // Only register after the complete index has validated.
  ClipAssetLibrary.register(assets);
  return Catalog(items: items, categories: categories);
}
