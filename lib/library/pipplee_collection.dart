import 'dart:convert';

import '../engine/bake_limits.dart';
import '../engine/clip_asset.dart';
import 'catalog.dart';

const pippleeIndexAsset = 'assets/catalog/pipplee.json';
const pippleeNotice = 'From the Pipplee catalogue, shared with permission.';

/// Compact bundled metadata, with every upstream ID preserved.
Catalog parsePippleeCollection(String source) {
  final doc = jsonDecode(source) as Map<String, dynamic>;
  final rows = doc['rows'] as List;
  if (doc['version'] != 1 ||
      doc['count'] != rows.length ||
      rows.length > 20000 ||
      doc['permission'] != 'maintainer-confirmed-pipplee-consent-2026-10-13') {
    throw const FormatException('Invalid Pipplee collection index');
  }
  final ids = <int>{}, assets = <ClipAsset>[], items = <LibraryItem>[];
  final hash = RegExp(r'^[0-9a-f]{64}$');
  for (final raw in rows) {
    final row = raw as List;
    if (row.length != 7) {
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
    final key = 'pipplee-$id', title = 'Pipplee $id';
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
        category: 'Pipplee',
        generatorId: 'clip:$key',
        paletteId: 'rainbow',
        tags: ['pipplee', 'pixel art', '${w}x$h', ...colours],
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
  return Catalog(items: items, categories: const ['Pipplee']);
}
