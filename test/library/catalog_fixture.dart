import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:glyph/library/catalog_manifest.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../tool/catalog_sign.dart';
import 'remote_fixture.dart';

/// An ephemeral Ed25519 key pair for tests (never a production key).
class TestKey {
  TestKey(this.seed, this.publicKey);
  final Uint8List seed, publicKey;

  static Future<TestKey> create() async {
    final pair = await DartEd25519().newKeyPair();
    return TestKey(
      Uint8List.fromList(await pair.extractPrivateKeyBytes()),
      Uint8List.fromList((await pair.extractPublicKey()).bytes),
    );
  }

  /// A fully signed artifact set for [doc].
  Future<Signed> publish(
    Map<String, dynamic> doc, {
    int? revision,
    int epoch = 0,
    String minApp = '1.0.0',
    List<String> revoked = const [],
  }) async {
    final payload = Uint8List.fromList(utf8.encode('${jsonEncode(doc)}\n'));
    final sha = CatalogManifest.sha256Hex(payload);
    final manifest = CatalogManifest(
      revision: revision ?? doc['revision'] as int,
      epoch: epoch,
      minApp: minApp,
      payload: 'payload/$sha.json',
      sha256: sha,
      size: payload.length,
      revoked: revoked,
      published: '2026-10-07T12:00:00Z',
    );
    final bytes = manifest.encode();
    return Signed(
      bytes,
      Uint8List.fromList(
        utf8.encode('${base64.encode(await signManifest(bytes, seed))}\n'),
      ),
      payload,
      manifest,
    );
  }
}

class Signed {
  Signed(this.manifest, this.sig, this.payload, this.parsed);
  final Uint8List manifest, sig, payload;
  final CatalogManifest parsed;
}

/// A static host serving one signed set, with request accounting.
class FakeHost {
  FakeHost(this.set, {this.etag = '"v1"'});
  Signed set;
  String? etag;
  final requests = <String>[];
  Uint8List? manifestOverride, sigOverride, payloadOverride;
  http.Response? Function(http.Request)? intercept;

  int count(String suffix) => requests.where((r) => r.endsWith(suffix)).length;

  late final client = MockClient((req) async {
    requests.add(req.url.path);
    final custom = intercept?.call(req);
    if (custom != null) return custom;
    final name = req.url.path.split('/glyph/').last;
    if (name == CatalogManifest.fileName) {
      if (etag != null && req.headers['if-none-match'] == etag) {
        return http.Response('', 304);
      }
      return http.Response.bytes(
        manifestOverride ?? set.manifest,
        200,
        headers: {'etag': ?etag},
      );
    }
    if (name == '${CatalogManifest.fileName}.sig') {
      return http.Response.bytes(sigOverride ?? set.sig, 200);
    }
    if (name == set.parsed.payload) {
      return http.Response.bytes(payloadOverride ?? set.payload, 200);
    }
    return http.Response('missing', 404);
  });
}

Future<Signed> signedFixture(TestKey key, {int revision = 4, int epoch = 0, List<String> revoked = const [], String minApp = '1.0.0'}) =>
    key.publish(remoteDocument(revision: revision), epoch: epoch, revoked: revoked, minApp: minApp);
