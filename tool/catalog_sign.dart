// Signs (or checks) the catalog manifest in a built site directory.
//   CATALOG_SIGNING_KEY=<base64 seed> dart run tool/catalog_sign.dart --site build/catalog-site
//   dart run tool/catalog_sign.dart --site build/catalog-site --key-file ./catalog-signing-key.txt
// The key is read from the environment or a file, never from argv, and is
// never printed. The result is verified against the public key compiled
// into the app (lib/library/catalog_key.dart) before the tool succeeds.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:glyph/library/catalog_key.dart';
import 'package:glyph/library/catalog_manifest.dart';

Future<Uint8List> signManifest(List<int> manifest, List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  final sig = await DartEd25519().sign(
    CatalogManifest.signingMessage(manifest),
    keyPair: pair,
  );
  return Uint8List.fromList(sig.bytes);
}

Future<Uint8List> publicKeyOf(List<int> seed) async {
  final pair = await DartEd25519().newKeyPairFromSeed(seed);
  return Uint8List.fromList((await pair.extractPublicKey()).bytes);
}

Uint8List? decodeSeed(String text) {
  try {
    final bytes = base64.decode(text.trim());
    return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
  } catch (_) {
    return null;
  }
}

Future<void> main(List<String> args) async {
  String? option(String key) {
    final i = args.indexOf(key);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  Never fail(String message) {
    stderr.writeln('::error::$message');
    exit(1);
  }

  final site = Directory(option('--site') ?? 'build/catalog-site');
  final manifestFile = File('${site.path}/${CatalogManifest.fileName}');
  final sigFile = File('${manifestFile.path}.sig');
  if (!manifestFile.existsSync()) fail('No manifest in ${site.path}');
  final publicKey =
      decodeCatalogKey(option('--public-key') ?? catalogPublicKey);
  if (publicKey == null) {
    fail(
      'lib/library/catalog_key.dart still holds the placeholder public key. '
      'Run tool/catalog_keygen.dart and paste the public key first.',
    );
  }
  final manifest = manifestFile.readAsBytesSync();
  if (!sigFile.existsSync()) {
    final keyFile = option('--key-file');
    final secret = keyFile != null
        ? File(keyFile).readAsStringSync()
        : Platform.environment['CATALOG_SIGNING_KEY'];
    final seed = secret == null ? null : decodeSeed(secret);
    if (seed == null) {
      fail('CATALOG_SIGNING_KEY is missing or not a base64 32-byte seed');
    }
    if (!_same(await publicKeyOf(seed), publicKey)) {
      fail('The signing key does not match the public key in the app');
    }
    sigFile.writeAsStringSync('${base64.encode(await signManifest(manifest, seed))}\n');
  }
  final sig = CatalogManifest.decodeSignature(sigFile.readAsBytesSync());
  if (sig == null || !await CatalogManifest.verify(manifest, sig, publicKey)) {
    fail('Manifest signature does not verify against the app key');
  }
  stdout.writeln('Manifest signature verified.');
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
