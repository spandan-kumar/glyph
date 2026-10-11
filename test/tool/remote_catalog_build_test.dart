import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/engine/generators/sprite_library.dart';
import 'package:glyph/library/catalog_manifest.dart';
import 'package:glyph/library/remote_catalog.dart';

import '../../tool/build_remote_catalog.dart';
import '../../tool/catalog_keygen.dart';
import '../../tool/catalog_sign.dart';
import '../library/catalog_fixture.dart';
import '../library/remote_fixture.dart';

void main() {
  late TestKey key;
  final when = DateTime.utc(2026, 10, 7, 12);
  setUpAll(() async => key = await TestKey.create());

  Uint8List body(Map<String, dynamic> doc) =>
      Uint8List.fromList(utf8.encode('${jsonEncode(doc)}\n'));

  /// Plans, signs (as the protected job does) and returns the live site.
  Future<Site> publish({
    required Map<String, dynamic> doc,
    int? revision,
    Site published = const {},
    List<String> revoked = const [],
    bool rollback = false,
    bool allowUnrevoke = false,
  }) async {
    final plan = await planPublication(
      candidate: rollback ? null : body(doc),
      revision: revision ?? (doc['revision'] as int? ?? 0),
      minApp: '1.3.3',
      revoked: revoked,
      published: published,
      publicKey: key.publicKey,
      now: when,
      rollback: rollback,
      allowUnrevoke: allowUnrevoke,
    );
    final site = {...plan.files};
    if (plan.needsSignature) {
      site['$manifestPath.sig'] = Uint8List.fromList(
        utf8.encode(
          '${base64.encode(await signManifest(site[manifestPath]!, key.seed))}\n',
        ),
      );
    }
    return site;
  }

  CatalogManifest current(Site s) => CatalogManifest.parse(s[manifestPath]!)!;

  test('the reviewed full artifact meets client bounds with every notice and source retained', () {
    final catalog =
        jsonDecode(File('assets/catalog/catalog.json').readAsStringSync())
            as Map<String, dynamic>;
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
    final meta =
        jsonDecode(File('assets/catalog/content_revision.json').readAsStringSync())
            as Map<String, dynamic>;
    final doc = buildRemoteDocument(
      catalog: catalog,
      packs: packs,
      revision: meta['revision'] as int,
    );
    final text = jsonEncode(doc), result = RemoteCatalog.parse(text)!;
    expect(utf8.encode(text).length, lessThan(RemoteCatalog.maxBytes * 0.7));
    expect(result.catalog.items.length, (catalog['items'] as List).length);
    expect(result.dropped, isEmpty);
    expect(
      result.revision,
      greaterThanOrEqualTo(
        result.catalog.items.map((i) => i.added).reduce((a, b) => a > b ? a : b),
      ),
    );
    for (final raw in catalog['items'] as List) {
      expect(result.catalog.byId(raw['id'] as String)!.notice, raw['notice']);
    }
    expect(doc['sprites'], packs);
    expect(SpriteLibrary.all.every((g) => SpriteLibrary.isBundled(g.id)), isTrue);
    expect(
      CatalogManifest.parse(
        (CatalogManifest(
          revision: meta['revision'] as int,
          epoch: 0,
          minApp: meta['minApp'] as String,
          payload: 'payload/${'a' * 64}.json',
          sha256: 'a' * 64,
          size: 1,
          revoked: [
            for (final id in (jsonDecode(File('assets/catalog/revoked.json').readAsStringSync()) as Map)['revoked'] as List)
              id as String,
          ],
        )).encode(),
      ),
      isNotNull,
    );
  });

  test('first publication is signed, verifiable by the client and has no previous', () async {
    final site = await publish(doc: remoteDocument(revision: 3));
    expect(site.keys, containsAll([manifestPath, '$manifestPath.sig']));
    expect(site.keys.where((k) => k.startsWith('previous')), isEmpty);
    final m = current(site);
    expect(m.payload, 'payload/${m.sha256}.json');
    final r = await RemoteCatalog.open(
      manifest: site[manifestPath]!,
      signature: site['$manifestPath.sig']!,
      payload: site[m.payload]!,
      publicKey: key.publicKey,
    );
    expect((r.revision, r.epoch), (3, 0));
  });

  test('an update keeps the previous signed set; an identical rerun changes nothing', () async {
    final v3 = await publish(doc: remoteDocument(revision: 3));
    final v4 = await publish(doc: remoteDocument(revision: 4), published: v3);
    expect(current(v4).revision, 4);
    expect(v4[previousManifestPath], v3[manifestPath]);
    expect(v4['$previousManifestPath.sig'], v3['$manifestPath.sig']);
    expect(v4.containsKey(current(v3).payload), isTrue);
    final plan = await planPublication(
      candidate: body(remoteDocument(revision: 4)),
      revision: 4,
      minApp: '1.3.3',
      published: v4,
      publicKey: key.publicKey,
      now: when.add(const Duration(days: 1)),
    );
    expect(plan.needsSignature, isFalse);
    expect(plan.files[manifestPath], v4[manifestPath]);
    expect(plan.files['$manifestPath.sig'], v4['$manifestPath.sig']);
    expect(plan.files[previousManifestPath], v3[manifestPath]);
  });

  test('changes need a higher revision; revocations need one too and are never silently dropped', () async {
    final v3 = await publish(doc: remoteDocument(revision: 3));
    final edited = remoteDocument(revision: 3)..['categories'] = ['Remote Picks'];
    expect(() => publish(doc: edited, published: v3), throwsFormatException);
    expect(() => publish(doc: remoteDocument(revision: 2), published: v3), throwsFormatException);
    expect(
      () => publish(doc: remoteDocument(revision: 3), published: v3, revoked: ['x']),
      throwsFormatException,
    );
    final taken = await publish(
      doc: remoteDocument(revision: 4),
      published: v3,
      revoked: ['old-art'],
    );
    expect(current(taken).revoked, ['old-art']);
    expect(
      () => publish(doc: remoteDocument(revision: 5), published: taken),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('--allow-unrevoke'))),
    );
    final restored = await publish(
      doc: remoteDocument(revision: 5),
      published: taken,
      allowUnrevoke: true,
    );
    expect(current(restored).revoked, isEmpty);
  });

  test('invalid content, changed art and changed item identity fail before publication', () async {
    expect(
      () => planPublication(candidate: Uint8List.fromList(utf8.encode('<html>')), revision: 1),
      throwsFormatException,
    );
    final invalid = remoteDocument();
    (invalid['items'] as List).first['generator'] = 'future';
    expect(() => publish(doc: invalid), throwsFormatException);
    final v3 = await publish(doc: remoteDocument(revision: 3));
    expect(
      () => publish(doc: remoteDocument(revision: 4, color: '#00FF00'), published: v3),
      throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('drawing changed'))),
    );
    final changed = remoteDocument(revision: 4);
    (changed['items'] as List).last['generator'] = 'fire';
    expect(
      () => publish(doc: changed, published: v3),
      throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('generator changed'))),
    );
  });

  test('a published set that fails verification blocks the build', () async {
    final v3 = await publish(doc: remoteDocument(revision: 3));
    final forged = {...v3}
      ..[manifestPath] = Uint8List.fromList(
        utf8.encode(utf8.decode(v3[manifestPath]!).replaceFirst('"revision":3', '"revision":8')),
      );
    expect(() => publish(doc: remoteDocument(revision: 9), published: forged), throwsFormatException);
    final stripped = {...v3}..remove('$manifestPath.sig');
    expect(() => publish(doc: remoteDocument(revision: 9), published: stripped), throwsFormatException);
    final noPayload = {...v3}..remove(current(v3).payload);
    expect(() => publish(doc: remoteDocument(revision: 9), published: noPayload), throwsFormatException);
    // With the placeholder key nothing published can be trusted.
    expect(
      () => planPublication(
        candidate: body(remoteDocument(revision: 9)),
        revision: 9,
        published: v3,
      ),
      throwsFormatException,
    );
  });

  test('rollback re-signs the previous content under a higher epoch and swaps the sets', () async {
    final v3 = await publish(doc: remoteDocument(revision: 3));
    final v4 = await publish(
      doc: remoteDocument(revision: 4),
      published: v3,
      revoked: ['takedown'],
    );
    final back = await publish(doc: const {}, published: v4, rollback: true);
    final m = current(back);
    expect((m.revision, m.epoch), (4, 1));
    expect(m.sha256, current(v3).sha256, reason: 'serves revision 3 content');
    expect(m.revoked, ['takedown'], reason: 'a rollback never un-revokes');
    expect(back[previousManifestPath], v4[manifestPath]);
    expect(back.containsKey(current(v4).payload), isTrue);
    final opened = await RemoteCatalog.open(
      manifest: back[manifestPath]!,
      signature: back['$manifestPath.sig']!,
      payload: back[m.payload]!,
      publicKey: key.publicKey,
    );
    expect((opened.revision, opened.epoch), (4, 1));
    // It supersedes the rolled-back manifest for clients, never the reverse.
    expect(m.compareTo(current(v4)), greaterThan(0));
    // A second rollback restores the other content at a still higher epoch.
    final forward = await publish(doc: const {}, published: back, rollback: true);
    expect(current(forward).epoch, 2);
    expect(current(forward).sha256, current(v4).sha256);
    // A normal publish afterwards needs a revision above the rolled-back one.
    expect(
      () => publish(
        doc: remoteDocument(revision: 4, spriteId: 'other-dot'),
        published: back,
        revoked: ['takedown'],
      ),
      throwsFormatException,
    );
    final next = await publish(
      doc: remoteDocument(revision: 5),
      published: back,
      revoked: ['takedown'],
    );
    expect((current(next).revision, current(next).epoch), (5, 1));
    // Nothing to roll back to.
    expect(() => publish(doc: const {}, published: v3, rollback: true), throwsFormatException);
    expect(() => publish(doc: const {}, rollback: true), throwsFormatException);
  });

  test('payload size gates: warn at 70% of the cap, fail at 90%', () async {
    Map<String, dynamic> padded(int strings) => {
      ...remoteDocument(revision: 3),
      'pad': List.filled(strings, 'x' * 8000),
    };
    final plan = await planPublication(
      candidate: body(padded(190)),
      revision: 3,
      publicKey: key.publicKey,
    );
    expect(plan.notes.join(), contains('70%'));
    expect(
      () => planPublication(
        candidate: body(padded(245)),
        revision: 3,
        publicKey: key.publicKey,
      ),
      throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('90%'))),
    );
    final small = await planPublication(
      candidate: body(remoteDocument(revision: 3)),
      revision: 3,
      publicKey: key.publicKey,
    );
    expect(small.notes, isEmpty);
  });

  test('keygen writes the private key only to the file, never to the output', () async {
    final dir = await Directory.systemTemp.createTemp('glyph-keygen');
    addTearDown(() => dir.delete(recursive: true));
    final out = StringBuffer(), err = StringBuffer();
    final file = File('${dir.path}/key.txt');
    expect(await keygen(['--out', file.path], out, err), 0);
    final seed = file.readAsStringSync().trim();
    expect(base64.decode(seed), hasLength(32));
    expect(out.toString(), isNot(contains(seed)));
    expect(err.toString(), isEmpty);
    final printed = RegExp(r"catalogPublicKey = '([^']+)'").firstMatch(out.toString())!.group(1)!;
    expect(base64.decode(printed), hasLength(32));
    expect(base64.encode(await publicKeyOf(base64.decode(seed))), printed);
    final before = file.readAsStringSync();
    expect(await keygen(['--out', file.path], out, err), 1);
    expect(file.readAsStringSync(), before, reason: 'never overwritten');
    expect(
      File('.gitignore').readAsStringSync(),
      contains('catalog-signing-key'),
    );
  });

  test('new items carry the publishing revision; published items keep theirs', () {
    Map<String, dynamic> doc(int revision, List<String> ids) => {
      'items': [
        for (final id in ids) {'id': id, 'added': 2},
      ],
      'revision': revision,
    };
    final published = doc(3, ['a', 'b']);
    final out = stampAdded(doc(4, ['a', 'b', 'c']), published, 4);
    expect(
      {for (final i in out['items'] as List) i['id']: i['added']},
      {'a': 2, 'b': 2, 'c': 4},
    );
    expect(stampAdded(doc(3, ['a']), null, 3)['items'], [
      {'id': 'a', 'added': 2},
    ]);
  });
}
