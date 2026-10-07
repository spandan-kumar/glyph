// Generates the Ed25519 key pair that signs the animation catalog.
//   dart run tool/catalog_keygen.dart [--out ./catalog-signing-key.txt]
//
// The PUBLIC key is printed for lib/library/catalog_key.dart. The PRIVATE
// key (a base64 32-byte seed) is written only to the file you name; it is
// never printed. The file is created exclusively (an existing file is never
// overwritten) with owner-only permissions where the OS supports it.
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

Future<void> main(List<String> args) async {
  exit(await keygen(args, stdout, stderr));
}

/// Returns the process exit code. Only the public key goes to [out].
Future<int> keygen(List<String> args, StringSink out, StringSink err) async {
  final i = args.indexOf('--out');
  final file = File(
    i >= 0 && i + 1 < args.length ? args[i + 1] : 'catalog-signing-key.txt',
  );
  if (file.existsSync()) {
    err.writeln('${file.path} already exists; refusing to overwrite a key.');
    return 1;
  }
  final pair = await DartEd25519().newKeyPair();
  final seed = await pair.extractPrivateKeyBytes();
  final publicKey = (await pair.extractPublicKey()).bytes;
  file.createSync(recursive: true);
  if (!Platform.isWindows) Process.runSync('chmod', ['600', file.path]);
  file.writeAsStringSync('${base64.encode(seed)}\n', flush: true);
  out
    ..writeln('Public key (paste into lib/library/catalog_key.dart):')
    ..writeln()
    ..writeln("const catalogPublicKey = '${base64.encode(publicKey)}';")
    ..writeln()
    ..writeln('The private key was written to ${file.path} (git-ignored).')
    ..writeln('Next:')
    ..writeln('  1. Store its contents as the secret CATALOG_SIGNING_KEY in the')
    ..writeln('     protected "catalog" GitHub environment (required reviewers).')
    ..writeln('  2. Back it up in a password manager, then delete the file.')
    ..writeln('  3. Never commit it, paste it in chat, or put it in a repo secret')
    ..writeln('     outside that environment.');
  return 0;
}
