import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/library/remote_catalog.dart';

import '../../tool/build_remote_catalog.dart';
import '../library/remote_fixture.dart';

void main() {
  test('reviewed full artifact meets client bounds with every notice and source retained', () {
    final catalog = jsonDecode(
      File('assets/catalog/catalog.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final files =
        Directory('assets/catalog/sprites')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final packs = [
      for (final f in files)
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    ];
    final revision =
        (jsonDecode(
              File('assets/catalog/content_revision.json').readAsStringSync(),
            ) as Map)['revision']
            as int;
    final doc = buildRemoteDocument(
      catalog: catalog,
      packs: packs,
      revision: revision,
    );
    final body = jsonEncode(doc), result = RemoteCatalog.parse(body)!;
    expect(utf8.encode(body).length, lessThan(RemoteCatalog.maxBytes));
    expect(result.catalog.items.length, (catalog['items'] as List).length);
    expect(result.dropped, isEmpty);
    expect(
      result.revision,
      greaterThanOrEqualTo(
        result.catalog.items
            .map((i) => i.added)
            .reduce((a, b) => a > b ? a : b),
      ),
    );
    for (final raw in catalog['items'] as List) {
      expect(result.catalog.byId(raw['id'] as String)!.notice, raw['notice']);
    }
    expect(doc['sprites'], packs);
    expect(
      SpriteLibrary.all.every((g) => SpriteLibrary.isBundled(g.id)),
      isTrue,
    );
  });

  test(
    'publication keeps exact previous bytes and rollback swaps the artifacts',
    () {
      final old = '${jsonEncode(remoteDocument(revision: 3))}\n';
      final next = '${jsonEncode(remoteDocument(revision: 4))}\n';
      final first = preparePublication(candidate: old);
      expect(first.previous, isNull);
      final update = preparePublication(
        candidate: next,
        current: first.current,
      );
      expect(update.current, next);
      expect(update.previous, old);
      final rerun = preparePublication(
        candidate: next,
        current: next,
        previous: old,
      );
      expect(rerun.previous, old);
      final rollback = preparePublication(
        candidate: next,
        current: next,
        previous: old,
        rollback: true,
      );
      expect(rollback.current, old);
      expect(rollback.previous, next);
      expect(
        preparePublication(candidate: next, current: rollback.current).previous,
        old,
      );
    },
  );

  test(
    'invalid content and edits to a published revision fail before publication',
    () {
      final old = jsonEncode(remoteDocument(revision: 3));
      final edited = remoteDocument(revision: 3);
      (edited['items'] as List).first['title'] = 'Changed';
      expect(
        () => preparePublication(candidate: jsonEncode(edited), current: old),
        throwsFormatException,
      );
      expect(
        () => preparePublication(
          candidate: jsonEncode(remoteDocument(revision: 2)),
          current: old,
        ),
        throwsFormatException,
      );
      expect(
        () => preparePublication(candidate: '<html>'),
        throwsFormatException,
      );
      expect(
        () => preparePublication(candidate: old, current: old, rollback: true),
        throwsFormatException,
      );
      final invalid = remoteDocument();
      (invalid['items'] as List).first['generator'] = 'future';
      expect(
        () => preparePublication(candidate: jsonEncode(invalid)),
        throwsFormatException,
      );
    },
  );
  test('publication rejects changing a drawing or item identity despite a revision bump', () {
    final old = jsonEncode(remoteDocument(revision: 3));
    expect(
      () => preparePublication(
        candidate: jsonEncode(remoteDocument(color: '#00FF00')),
        current: old,
      ),
      throwsFormatException,
    );
    final changedItem = remoteDocument();
    (changedItem['items'] as List).last['generator'] = 'fire';
    expect(
      () =>
          preparePublication(candidate: jsonEncode(changedItem), current: old),
      throwsFormatException,
    );
  });
}
