import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The small signed document that authenticates a catalog payload.
///
/// The signature covers `signingPrefix` plus the exact manifest bytes, so
/// the manifest must be parsed from those bytes and never re-encoded.
class CatalogManifest {
  const CatalogManifest({
    required this.revision,
    required this.epoch,
    required this.minApp,
    required this.payload,
    required this.sha256,
    required this.size,
    this.revoked = const [],
    this.published = '',
  });

  static const schema = 1;
  static const maxBytes = 64 * 1024;
  static const maxPayloadBytes = 2 * 1024 * 1024;
  static const maxRevoked = 2000;
  static const signingPrefix = 'glyph-catalog-manifest-v1\n';
  static const fileName = 'manifest-v1.json';

  /// Monotonic content revision.
  final int revision;

  /// Bumped by a rollback so an older payload can supersede a newer one at
  /// the same revision.
  final int epoch;

  /// Lowest app version (`X.Y.Z`) allowed to use this payload.
  final String minApp;

  /// Path of the payload relative to the manifest.
  final String payload;
  final String sha256;
  final int size;

  /// Item ids or generator ids (`sprite:x`) to hide, bundled or downloaded.
  final List<String> revoked;
  final String published;

  static final _idPattern = RegExp(r'^(sprite:)?[a-z0-9]+(-[a-z0-9]+)*$');
  static final _pathPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$');
  static final _versionPattern = RegExp(r'^\d{1,6}\.\d{1,6}\.\d{1,6}$');
  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$');

  /// Strict parse; null for anything unexpected (including unknown schema).
  static CatalogManifest? parse(Uint8List bytes) {
    try {
      if (bytes.length > maxBytes) return null;
      final doc = jsonDecode(utf8.decode(bytes));
      if (doc is! Map<String, dynamic> || doc['schema'] != schema) return null;
      final revision = doc['revision'], epoch = doc['epoch'];
      final minApp = doc['minApp'], payload = doc['payload'];
      final sha = doc['sha256'], size = doc['size'], revoked = doc['revoked'];
      if (revision is! int ||
          revision < 1 ||
          revision > 0x7fffffff ||
          epoch is! int ||
          epoch < 0 ||
          epoch > 0x7fffffff ||
          minApp is! String ||
          !_versionPattern.hasMatch(minApp) ||
          payload is! String ||
          !_pathPattern.hasMatch(payload) ||
          payload.contains('..') ||
          payload.contains('//') ||
          sha is! String ||
          !_shaPattern.hasMatch(sha) ||
          size is! int ||
          size < 1 ||
          size > maxPayloadBytes ||
          revoked is! List ||
          revoked.length > maxRevoked) {
        return null;
      }
      final ids = <String>[];
      for (final id in revoked) {
        if (id is! String || id.length > 120 || !_idPattern.hasMatch(id)) {
          return null;
        }
        ids.add(id);
      }
      final published = doc['published'];
      return CatalogManifest(
        revision: revision,
        epoch: epoch,
        minApp: minApp,
        payload: payload,
        sha256: sha,
        size: size,
        revoked: List.unmodifiable(ids),
        published: published is String && published.length <= 40
            ? published
            : '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Positive when this manifest supersedes [other]: higher revision, or the
  /// same revision with a higher epoch.
  int compareTo(CatalogManifest other) => revision != other.revision
      ? revision.compareTo(other.revision)
      : epoch.compareTo(other.epoch);

  Map<String, Object> toJson() => {
    'schema': schema,
    'revision': revision,
    'epoch': epoch,
    'minApp': minApp,
    'payload': payload,
    'sha256': sha256,
    'size': size,
    'revoked': revoked,
    'published': published,
  };

  /// Canonical bytes the maintainer tooling signs.
  Uint8List encode() => utf8.encode('${jsonEncode(toJson())}\n');

  static String sha256Hex(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();

  static Uint8List signingMessage(List<int> manifestBytes) =>
      Uint8List.fromList([...utf8.encode(signingPrefix), ...manifestBytes]);

  /// Pure-Dart Ed25519, so it behaves identically on every platform and
  /// inside isolates.
  static Future<bool> verify(
    List<int> manifestBytes,
    List<int> signature,
    List<int> publicKey,
  ) async {
    if (signature.length != 64 || publicKey.length != 32) return false;
    try {
      return await DartEd25519().verify(
        signingMessage(manifestBytes),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Decodes a `.sig` file (base64, whitespace tolerated).
  static Uint8List? decodeSignature(List<int> file) {
    try {
      if (file.length > 512) return null;
      final out = base64.decode(utf8.decode(file).trim());
      return out.length == 64 ? Uint8List.fromList(out) : null;
    } catch (_) {
      return null;
    }
  }

  /// Compares dotted `X.Y.Z` versions; build suffixes are ignored.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      final core = v.split(RegExp(r'[+\-]')).first.split('.');
      return [for (var i = 0; i < 3; i++) int.tryParse(i < core.length ? core[i] : '0') ?? 0];
    }

    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i].compareTo(y[i]);
    }
    return 0;
  }
}
