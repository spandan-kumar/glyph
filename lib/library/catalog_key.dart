import 'dart:convert';
import 'dart:typed_data';

/// Marker value meaning "no signing key has been generated yet".
const catalogPublicKeyPlaceholder =
    'PLACEHOLDER-run-dart-run-tool-catalog_keygen-and-paste-the-public-key-here';

/// Ed25519 public key (base64, 32 bytes) that verifies the catalog manifest.
///
/// While this is the placeholder the app treats the remote catalog as
/// unavailable: it never contacts the host and never trusts a cache. The
/// matching private key lives only in the `CATALOG_SIGNING_KEY` secret of the
/// protected `catalog` GitHub environment. See docs/CATALOG_DELIVERY.md.
const catalogPublicKey = catalogPublicKeyPlaceholder;

/// Decodes a base64 Ed25519 public key; null for the placeholder or any
/// malformed value, so a bad paste can never enable the feature.
Uint8List? decodeCatalogKey(String value) {
  if (value == catalogPublicKeyPlaceholder) return null;
  try {
    final bytes = base64.decode(value.trim());
    return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
  } catch (_) {
    return null;
  }
}
