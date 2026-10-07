// Builds the Pages site from reviewed packs; never writes into docs/.
// dart run tool/build_remote_catalog.dart [--current file] [--previous file] [--rollback]
import 'dart:convert';
import 'dart:io';

import 'package:glyph/library/remote_catalog.dart';
import 'package:glyph/library/catalog.dart';
import 'package:glyph/engine/generators/sprite.dart';

Map<String, dynamic> buildRemoteDocument({
  required Map<String, dynamic> catalog,
  required List<Map<String, dynamic>> packs,
  required int revision,
}) => {...catalog, 'revision': revision, 'sprites': packs};

/// Keep the exact prior bytes for rollback. A content revision is immutable;
/// rerunning an identical publication is allowed, silently editing it isn't.
({String current, String? previous}) preparePublication({
  required String candidate,
  String? current,
  String? previous,
  bool rollback = false,
}) {
  RemoteCatalogResult checked(
    String body, {
    Catalog? baseline,
    List<SpriteGenerator> existing = const [],
  }) {
    final result = RemoteCatalog.parse(
      body,
      bundled: baseline,
      existingSprites: existing,
    );
    if (result == null || result.dropped.isNotEmpty) {
      throw FormatException(
        'Invalid publication: ${result?.dropped.join('\n') ?? 'bad document'}',
      );
    }
    return result;
  }

  final old = current == null ? null : checked(current);
  final next = checked(
    candidate,
    baseline: old?.catalog,
    existing: old?.sprites ?? const [],
  );
  if (rollback) {
    if (current == null || previous == null) {
      throw const FormatException(
        'Rollback needs current and previous artifacts',
      );
    }
    checked(previous);
    return (current: previous, previous: current);
  }
  if (old != null) {
    if (next.revision == old.revision && candidate == current) {
      if (previous != null) checked(previous);
      return (current: candidate, previous: previous);
    }
    if (next.revision <= old.revision) {
      throw const FormatException(
        'Bump content_revision.json for changed content',
      );
    }
  }
  return (current: candidate, previous: current);
}

void main(List<String> args) {
  String? option(String key) {
    final index = args.indexOf(key);
    if (index < 0) return null;
    if (index + 1 >= args.length) {
      throw FormatException('Missing value for $key');
    }
    return args[index + 1];
  }

  String? read(String? path) {
    if (path == null) return null;
    final file = File(path);
    if (file.lengthSync() > RemoteCatalog.maxBytes) {
      throw const FormatException('Artifact exceeds size limit');
    }
    return file.readAsStringSync();
  }

  final revision =
      (jsonDecode(
            File('assets/catalog/content_revision.json').readAsStringSync(),
          ) as Map)['revision']
          as int;
  final files =
      Directory('assets/catalog/sprites')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final doc = buildRemoteDocument(
    catalog: jsonDecode(
      File('assets/catalog/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>,
    packs: [
      for (final f in files)
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    ],
    revision: revision,
  );
  final publication = preparePublication(
    candidate: '${jsonEncode(doc)}\n',
    current: read(option('--current')),
    previous: read(option('--previous')),
    rollback: args.contains('--rollback'),
  );
  final output = Directory(option('--output') ?? 'build/catalog-site')
    ..createSync(recursive: true);
  void write(String name, String body) =>
      File('${output.path}/$name').writeAsStringSync(body);
  write('catalog-v1.json', publication.current);
  if (publication.previous case final body?) {
    write('previous.json', body);
  } else {
    final file = File('${output.path}/previous.json');
    if (file.existsSync()) file.deleteSync();
  }
  Directory('${output.path}/revisions').createSync();
  for (final body in [publication.current, ?publication.previous]) {
    final revision = RemoteCatalog.parse(body)!.revision;
    write('revisions/$revision.json', body);
  }
  final result = RemoteCatalog.parse(publication.current)!;
  write(
    'index.html',
    '<!doctype html><html lang="en"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width"><title>Glyph animations</title>'
        '<h1>Glyph animation catalog</h1><p>Content revision ${result.revision}. '
        '${result.catalog.items.length} looks, ready for offline playback in Glyph.</p>'
        '<p><a href="catalog-v1.json">Current catalog</a>'
        '${publication.previous == null ? '' : ' · <a href="previous.json">Previous catalog</a>'}</p></html>\n',
  );
  write('.nojekyll', '');
  stdout.writeln(
    'Catalog revision ${result.revision}: ${result.catalog.items.length} looks; '
    '${utf8.encode(publication.current).length} bytes → ${output.path}',
  );
}
