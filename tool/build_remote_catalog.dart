// Builds the Pages site from reviewed packs; never writes into docs/.
//
//   dart run tool/build_remote_catalog.dart [--published DIR] [--output DIR]
//       [--rollback] [--allow-unrevoke] [--public-key B64]
//
// --published is a directory laid out like the live site (see
// tool/fetch_published_catalog.sh). The output holds an UNSIGNED
// manifest-v1.json; tool/catalog_sign.dart signs it in the protected
// workflow job. Unchanged reruns keep the published signed manifest.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:glyph/engine/generators/sprite.dart';
import 'package:glyph/library/catalog_key.dart';
import 'package:glyph/library/catalog_manifest.dart';
import 'package:glyph/library/remote_catalog.dart';

/// Site layout: relative path -> bytes.
typedef Site = Map<String, Uint8List>;

const manifestPath = CatalogManifest.fileName;
const previousManifestPath = 'previous-$manifestPath';

String payloadPath(String sha) => 'payload/$sha.json';

Map<String, dynamic> buildRemoteDocument({
  required Map<String, dynamic> catalog,
  required List<Map<String, dynamic>> packs,
  required int revision,
}) => {...catalog, 'revision': revision, 'sprites': packs};

/// New items (ids absent from the published payload) carry the publishing
/// revision as `added`, which is what puts them on the app's "Just added"
/// shelf; items already published keep their published value so reruns are
/// byte-stable. With nothing published yet, items keep their own values.
Map<String, dynamic> stampAdded(
  Map<String, dynamic> doc,
  Map<String, dynamic>? published,
  int revision,
) {
  if (published == null) return doc;
  final known = {
    for (final i in published['items'] as List)
      (i as Map)['id'] as String: (i['added'] as num?)?.toInt() ?? 0,
  };
  return {
    ...doc,
    'items': [
      for (final raw in doc['items'] as List)
        () {
          final item = Map<String, dynamic>.from(raw as Map);
          final old = known[item['id']];
          item['added'] = old ?? revision;
          if (item['added'] == 0) item.remove('added');
          return item;
        }(),
    ],
  };
}

/// The currently published payload, if the mirror holds one.
Map<String, dynamic>? publishedDocument(Site site) {
  final manifest = site[manifestPath] == null
      ? null
      : CatalogManifest.parse(site[manifestPath]!);
  final payload = manifest == null ? null : site[manifest.payload];
  return payload == null
      ? null
      : jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
}

class Publication {
  Publication(this.files, this.manifest, this.needsSignature, this.notes);
  final Site files;
  final CatalogManifest manifest;

  /// False when the published, already signed manifest is reused.
  final bool needsSignature;
  final List<String> notes;
}

class _Published {
  _Published(this.manifestBytes, this.sig, this.manifest, this.payload);
  final Uint8List manifestBytes, sig, payload;
  final CatalogManifest manifest;
}

/// Verifies a published manifest + payload pair end to end.
Future<_Published?> _loadPublished(
  Site site,
  String manifestName,
  List<int>? key,
) async {
  final manifestBytes = site[manifestName];
  if (manifestBytes == null) return null;
  final sig = site['$manifestName.sig'];
  if (key == null) {
    throw const FormatException(
      'Published artifacts exist but the app key is still the placeholder',
    );
  }
  if (sig == null) throw FormatException('$manifestName has no signature');
  final manifest = CatalogManifest.parse(manifestBytes);
  final payload = manifest == null ? null : site[manifest.payload];
  if (manifest == null || payload == null) {
    throw FormatException('$manifestName is malformed or lacks its payload');
  }
  try {
    await RemoteCatalog.open(
      manifest: manifestBytes,
      signature: sig,
      payload: payload,
      publicKey: key,
    );
  } on CatalogRejected catch (e) {
    throw FormatException('Published $manifestName failed verification: $e');
  }
  return _Published(manifestBytes, sig, manifest, payload);
}

String _timestamp(DateTime t) =>
    '${t.toUtc().toIso8601String().split('.').first}Z';

/// Pure publication planning. Throws [FormatException] for anything that
/// must not ship. Signatures are added later by tool/catalog_sign.dart.
Future<Publication> planPublication({
  Uint8List? candidate,
  int revision = 0,
  String minApp = '1.0.0',
  List<String> revoked = const [],
  Site published = const {},
  List<int>? publicKey,
  DateTime? now,
  bool rollback = false,
  bool allowUnrevoke = false,
}) async {
  final stamp = _timestamp(now ?? DateTime.now());
  final current = await _loadPublished(published, manifestPath, publicKey);
  final previous = await _loadPublished(
    published,
    previousManifestPath,
    publicKey,
  );
  final notes = <String>[];
  final files = <String, Uint8List>{};
  void keep(String name, _Published p) {
    files[name] = p.manifestBytes;
    files['$name.sig'] = p.sig;
    files[p.manifest.payload] = p.payload;
  }

  if (rollback) {
    if (current == null || previous == null) {
      throw const FormatException(
        'Rollback needs current and previous artifacts',
      );
    }
    final c = current.manifest, p = previous.manifest;
    final next = CatalogManifest(
      revision: c.revision,
      epoch: c.epoch + 1,
      minApp: p.minApp,
      payload: p.payload,
      sha256: p.sha256,
      size: p.size,
      // A rollback never un-revokes anything.
      revoked: ({...c.revoked, ...p.revoked}.toList()..sort()),
      published: stamp,
    );
    files[manifestPath] = next.encode();
    files[next.payload] = previous.payload;
    keep(previousManifestPath, current);
    notes.add(
      'Rollback: revision ${c.revision} epoch ${c.epoch} -> epoch ${next.epoch}, '
      'serving the content of revision ${p.revision}',
    );
    return Publication(files, next, true, notes);
  }

  if (candidate == null) throw const FormatException('No candidate');
  if (previous != null && current == null) {
    throw const FormatException('Previous artifact without a current one');
  }
  final result = RemoteCatalog.parse(utf8.decode(candidate));
  if (result == null || result.dropped.isNotEmpty) {
    throw FormatException(
      'Invalid publication: ${result?.dropped.join('\n') ?? 'bad document'}',
    );
  }
  final sha = CatalogManifest.sha256Hex(candidate);
  final sortedRevoked = ({...revoked}.toList()..sort());
  var epoch = 0;
  if (current != null) {
    final c = current.manifest;
    epoch = c.epoch;
    final same =
        c.sha256 == sha &&
        c.minApp == minApp &&
        c.revision == revision &&
        _sameList(c.revoked, sortedRevoked);
    if (same) {
      keep(manifestPath, current);
      if (previous != null) keep(previousManifestPath, previous);
      notes.add('Unchanged: keeping the published signed manifest');
      return Publication(files, c, false, notes);
    }
    if (revision <= c.revision) {
      throw FormatException(
        'Bump content_revision.json above ${c.revision} for changed content '
        'or revocations',
      );
    }
    final lost = c.revoked.where((id) => !sortedRevoked.contains(id));
    if (lost.isNotEmpty && !allowUnrevoke) {
      throw FormatException(
        'Revoked ids were removed (${lost.join(', ')}); pass --allow-unrevoke '
        'only for a deliberate restore',
      );
    }
    _checkImmutable(utf8.decode(current.payload), utf8.decode(candidate));
  }
  final next = CatalogManifest(
    revision: revision,
    epoch: epoch,
    minApp: minApp,
    payload: payloadPath(sha),
    sha256: sha,
    size: candidate.length,
    revoked: sortedRevoked,
    published: stamp,
  );
  if (CatalogManifest.parse(next.encode()) == null) {
    throw const FormatException('Manifest fields are out of range');
  }
  final limit = RemoteCatalog.maxBytes;
  if (candidate.length > limit * 0.9) {
    throw FormatException(
      'Payload is ${candidate.length} bytes, over 90% of the $limit byte cap',
    );
  }
  if (candidate.length > limit * 0.7) {
    notes.add(
      'WARNING: payload is ${candidate.length} bytes, over 70% of the $limit '
      'byte cap; plan a split before it grows further',
    );
  }
  files[manifestPath] = next.encode();
  files[next.payload] = candidate;
  if (current != null) keep(previousManifestPath, current);
  return Publication(files, next, true, notes);
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A published ID never changes meaning: same sprite ID => same drawing,
/// same item ID => same generator. Changed art needs new IDs.
void _checkImmutable(String oldBody, String newBody) {
  Map<String, Sprite> sprites(Map<String, dynamic> doc) => {
    for (final pack in doc['sprites'] as List? ?? const [])
      for (final raw in (pack as Map)['sprites'] as List)
        for (final s in Sprite.parsePackJson({
          ...pack.cast<String, dynamic>(),
          'sprites': [raw],
        }))
          'sprite:${s.id}': s,
  };
  Map<String, String> items(Map<String, dynamic> doc) => {
    for (final i in doc['items'] as List)
      (i as Map)['id'] as String: i['generator'] as String,
  };
  final a = jsonDecode(oldBody) as Map<String, dynamic>;
  final b = jsonDecode(newBody) as Map<String, dynamic>;
  final oldSprites = sprites(a), newSprites = sprites(b);
  for (final e in oldSprites.entries) {
    final other = newSprites[e.key];
    if (other != null && !other.sameDrawing(e.value)) {
      throw FormatException('${e.key}: published drawing changed; use a new ID');
    }
  }
  final oldItems = items(a), newItems = items(b);
  for (final e in oldItems.entries) {
    final g = newItems[e.key];
    if (g != null && g != e.value) {
      throw FormatException('${e.key}: item generator changed; use a new ID');
    }
  }
}

String indexHtml(CatalogManifest m, int looks) =>
    '<!doctype html><html lang="en"><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width"><title>Glyph animations</title>'
    '<h1>Glyph animation catalog</h1><p>Content revision ${m.revision}. '
    '$looks looks, ready for offline playback in Glyph.</p></html>\n';

Site readSite(Directory dir) {
  final out = <String, Uint8List>{};
  if (!dir.existsSync()) return out;
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    if (f.lengthSync() > RemoteCatalog.maxBytes) {
      throw FormatException('$rel exceeds the size limit');
    }
    out[rel] = f.readAsBytesSync();
  }
  return out;
}

Future<void> main(List<String> args) async {
  String? option(String key) {
    final index = args.indexOf(key);
    if (index < 0) return null;
    if (index + 1 >= args.length) {
      throw FormatException('Missing value for $key');
    }
    return args[index + 1];
  }

  try {
    final meta =
        jsonDecode(File('assets/catalog/content_revision.json').readAsStringSync())
            as Map<String, dynamic>;
    final revoked = [
      for (final id
          in (jsonDecode(File('assets/catalog/revoked.json').readAsStringSync())
                  as Map)['revoked']
              as List)
        id as String,
    ];
    final files =
        Directory('assets/catalog/sprites')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final site = readSite(Directory(option('--published') ?? 'build/published'));
    final doc = buildRemoteDocument(
      catalog:
          jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
              as Map<String, dynamic>,
      packs: [
        for (final f in files)
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      ],
      revision: meta['revision'] as int,
    );
    final rollback = args.contains('--rollback');
    final publication = await planPublication(
      candidate: rollback
          ? null
          : Uint8List.fromList(
              utf8.encode(
                '${jsonEncode(stampAdded(doc, publishedDocument(site), meta['revision'] as int))}\n',
              ),
            ),
      revision: meta['revision'] as int,
      minApp: meta['minApp'] as String? ?? '1.0.0',
      revoked: revoked,
      published: site,
      publicKey: decodeCatalogKey(option('--public-key') ?? catalogPublicKey),
      rollback: rollback,
      allowUnrevoke: args.contains('--allow-unrevoke'),
    );
    final output = Directory(option('--output') ?? 'build/catalog-site');
    if (output.existsSync()) output.deleteSync(recursive: true);
    output.createSync(recursive: true);
    for (final e in publication.files.entries) {
      File('${output.path}/${e.key}')
        ..createSync(recursive: true)
        ..writeAsBytesSync(e.value);
    }
    final payload = publication.files[publication.manifest.payload]!;
    final result = RemoteCatalog.parse(utf8.decode(payload))!;
    File('${output.path}/index.html').writeAsStringSync(
      indexHtml(publication.manifest, result.catalog.items.length),
    );
    File('${output.path}/.nojekyll').writeAsStringSync('');
    for (final n in publication.notes) {
      stdout.writeln(n.startsWith('WARNING') ? '::warning::$n' : n);
    }
    final m = publication.manifest;
    stdout.writeln(
      'Catalog revision ${m.revision} epoch ${m.epoch}: '
      '${result.catalog.items.length} looks; ${payload.length} bytes → ${output.path}'
      '${publication.needsSignature ? ' (needs signing)' : ''}',
    );
  } on FormatException catch (e) {
    stderr.writeln('::error::${e.message}');
    exit(1);
  }
}
