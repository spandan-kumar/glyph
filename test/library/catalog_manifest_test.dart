import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/library/catalog_manifest.dart';

import 'catalog_fixture.dart';

void main() {
  late TestKey key;
  setUpAll(() async => key = await TestKey.create());
  Uint8List bytes(Map<String, Object?> m) => Uint8List.fromList(utf8.encode(jsonEncode(m)));
  Map<String, Object?> good() => {
    'schema': 1,
    'revision': 2,
    'epoch': 0,
    'minApp': '1.3.3',
    'payload': 'payload/${'a' * 64}.json',
    'sha256': 'a' * 64,
    'size': 10,
    'revoked': ['one', 'sprite:two'],
    'published': '2026-10-07T00:00:00Z',
  };

  test('strict parsing accepts a good manifest and refuses everything else', () {
    expect(CatalogManifest.parse(bytes(good()))!.revoked, ['one', 'sprite:two']);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (m) => m['schema'] = 2,
      (m) => m['revision'] = 0,
      (m) => m['revision'] = '2',
      (m) => m['epoch'] = -1,
      (m) => m['minApp'] = '1.3',
      (m) => m['payload'] = '../x.json',
      (m) => m['payload'] = '/abs.json',
      (m) => m['payload'] = 'https://evil.example/x.json',
      (m) => m['sha256'] = 'A' * 64,
      (m) => m['size'] = 0,
      (m) => m['size'] = 3 * 1024 * 1024,
      (m) => m['revoked'] = ['Bad Id'],
      (m) => m['revoked'] = List.filled(2001, 'x'),
      (m) => m.remove('revoked'),
    ]) {
      final m = good();
      mutate(m);
      expect(CatalogManifest.parse(bytes(m)), isNull, reason: '$m');
    }
    expect(CatalogManifest.parse(Uint8List(0)), isNull);
    expect(CatalogManifest.parse(Uint8List(CatalogManifest.maxBytes + 1)), isNull);
  });

  test('signatures bind the exact bytes and the signing domain', () async {
    final set = await signedFixture(key);
    final sig = CatalogManifest.decodeSignature(set.sig)!;
    expect(await CatalogManifest.verify(set.manifest, sig, key.publicKey), isTrue);
    expect(
      await CatalogManifest.verify(
        Uint8List.fromList([...set.manifest, 10]),
        sig,
        key.publicKey,
      ),
      isFalse,
    );
    final other = await TestKey.create();
    expect(await CatalogManifest.verify(set.manifest, sig, other.publicKey), isFalse);
    expect(await CatalogManifest.verify(set.manifest, Uint8List(10), key.publicKey), isFalse);
    // A signature over the bare bytes (no domain prefix) must not verify.
    final pair = await DartEd25519().newKeyPairFromSeed(key.seed);
    final bare = await DartEd25519().sign(set.manifest, keyPair: pair);
    expect(
      await CatalogManifest.verify(set.manifest, bare.bytes, key.publicKey),
      isFalse,
    );
  });

  test('ordering is by revision, then epoch', () async {
    CatalogManifest m(int r, int e) => CatalogManifest(
      revision: r, epoch: e, minApp: '1.0.0', payload: 'p', sha256: 'a' * 64, size: 1,
    );
    expect(m(5, 0).compareTo(m(4, 9)), greaterThan(0));
    expect(m(4, 1).compareTo(m(4, 0)), greaterThan(0));
    expect(m(4, 1).compareTo(m(4, 1)), 0);
    expect(m(3, 9).compareTo(m(4, 0)), lessThan(0));
  });
}
