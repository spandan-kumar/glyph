#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Create Glyph's release key and the proof that it replaces the old signing key.
Run this once, locally in a terminal. Passwords and certificate details are
requested interactively; passwords are never passed as command arguments.

Usage: tool/rotate_signing_key.sh [OLD_KEYSTORE [NEW_KEYSTORE [OLD_ALIAS]]]
       tool/rotate_signing_key.sh --help

Defaults:
  Old keystore: ~/.android/debug.keystore; alias: androiddebugkey
  New keystore: ~/glyph-release-keys/glyph-release.jks; alias: glyph-release
  Lineage: glyph-signing.lineage beside the new keystore

The Android debug keystore password is 'android' unless you changed it.
Choose a strong new password and your own certificate name (not Android Debug).
For a separate key password, keytool prompts after the certificate details;
press Return there to use the keystore password for the key too.
The script refuses to overwrite a keystore or lineage. If rotation fails after
key creation, keep that key and finish apksigner rotate manually; see docs/SIGNING.md.

Requires keytool and apksigner. APKSIGNER may name an executable; otherwise use
apksigner on PATH or ~/Library/Android/sdk/build-tools/36.0.0/apksigner.
Afterwards, run the printed gh commands to set the five new GitHub secrets.
Keep the four existing old-key secrets. Back up both keystores and the lineage
offline in two places; never put keys or passwords in the repository.
HELP
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -*) usage >&2; exit 1 ;;
esac
if (( $# > 3 )); then
  usage >&2
  exit 1
fi

command -v keytool >/dev/null || { echo 'keytool is required (install a JDK).' >&2; exit 1; }
apksigner=${APKSIGNER:-apksigner}
if ! command -v "$apksigner" >/dev/null; then
  if [[ -z ${APKSIGNER:-} ]]; then
    apksigner="$HOME/Library/Android/sdk/build-tools/36.0.0/apksigner"
  fi
  command -v "$apksigner" >/dev/null || { echo 'apksigner is required (install Android build-tools or set APKSIGNER).' >&2; exit 1; }
fi
if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'Run in an interactive terminal so password prompts can hide your input.' >&2
  exit 1
fi

old_keystore=${1:-"$HOME/.android/debug.keystore"}
new_keystore=${2:-"$HOME/glyph-release-keys/glyph-release.jks"}
old_alias=${3:-androiddebugkey}
new_alias=glyph-release
key_dir=$(dirname "$new_keystore")
lineage="$key_dir/glyph-signing.lineage"
[[ -f $old_keystore ]] || { echo 'The old keystore does not exist.' >&2; exit 1; }
if [[ -e $new_keystore || -L $new_keystore || -e $lineage || -L $lineage ]]; then
  echo 'The new keystore or lineage already exists; refusing to overwrite it.' >&2
  exit 1
fi

umask 077
mkdir -p "$key_dir"
keytool -genkeypair -storetype JKS -keystore "$new_keystore" \
  -alias "$new_alias" -keyalg RSA -keysize 4096 -validity 10000

"$apksigner" rotate --out "$lineage" \
  --old-signer --ks "$old_keystore" --ks-key-alias "$old_alias" \
  --set-installed-data true --set-rollback false \
  --new-signer --ks "$new_keystore" --ks-key-alias "$new_alias"

echo 'Certificate SHA-256 fingerprints: signer #1 is OLD; signer #2 is NEW.'
"$apksigner" lineage --in "$lineage" --print-certs

echo
echo 'Run these commands; gh prompts for the password and alias secret values.'
printf 'base64 < %q | gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 -R spandan-kumar/glyph\n' "$new_keystore"
echo 'gh secret set ANDROID_RELEASE_KEYSTORE_PASSWORD -R spandan-kumar/glyph'
echo 'gh secret set ANDROID_RELEASE_KEY_ALIAS -R spandan-kumar/glyph'
echo 'gh secret set ANDROID_RELEASE_KEY_PASSWORD -R spandan-kumar/glyph'
printf 'base64 < %q | gh secret set ANDROID_SIGNING_LINEAGE_BASE64 -R spandan-kumar/glyph\n' "$lineage"
echo 'Set ANDROID_RELEASE_KEY_ALIAS to glyph-release. Keep the existing ANDROID_KEYSTORE_BASE64,'
echo 'ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD secrets as the OLD signer.'
echo 'Back up ~/glyph-release-keys and ~/.android/debug.keystore offline in TWO places.'
echo 'If you chose other paths, back up those keystores and the lineage too. See docs/SIGNING.md.'
