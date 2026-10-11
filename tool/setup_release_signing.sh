#!/usr/bin/env bash
# One command to move Glyph's releases to a proper signing key (see docs/SIGNING.md).
# Generates a random password that is never shown, keeps it in the macOS Keychain,
# creates the key and the rotation proof, sets the five GitHub secrets as the repo
# owner and leaves a backup folder. Passwords never appear on screen or in argv.
set -euo pipefail

repo=spandan-kumar/glyph
owner=spandan-kumar
old_keystore="$HOME/.android/debug.keystore"
old_alias=androiddebugkey
key_dir="$HOME/glyph-release-keys"
new_keystore="$key_dir/glyph-release.jks"
new_alias=glyph-release
lineage="$key_dir/glyph-signing.lineage"
keychain_service="Glyph release keystore"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

need() { command -v "$1" >/dev/null || { echo "Needs $1." >&2; exit 1; }; }
need keytool; need gh; need openssl; need security
apksigner=${APKSIGNER:-$(ls -d "$HOME"/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n 1)}
[[ -x ${apksigner:-} ]] || { echo 'Needs Android build-tools apksigner (or set APKSIGNER).' >&2; exit 1; }
[[ -f $old_keystore ]] || { echo "The current release key ($old_keystore) is missing." >&2; exit 1; }
if [[ -e $new_keystore || -e $lineage ]]; then
  echo "$key_dir already has a release key; refusing to overwrite it." >&2
  exit 1
fi
GH_TOKEN=$(gh auth token -u "$owner") || { echo "Log gh in as $owner first: gh auth login" >&2; exit 1; }
export GH_TOKEN

umask 077
mkdir -p "$key_dir"
# Keep a copy of the current (old) key next to the new one: both are needed forever.
cp -p "$old_keystore" "$key_dir/old-debug.keystore"

# Random 40-character password; it only lives in this process, the Keychain and GitHub.
STORE_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 40)
OLD_PASS=android
export STORE_PASS OLD_PASS
# security -i reads the command from stdin, so the password stays out of argv.
printf 'add-generic-password -U -a %s -s "%s" -w "%s"\n' "$new_alias" "$keychain_service" "$STORE_PASS" \
  | security -i >/dev/null

keytool -genkeypair -storetype PKCS12 -keystore "$new_keystore" \
  -alias "$new_alias" -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Glyph, O=Glyph" -storepass:env STORE_PASS -keypass:env STORE_PASS -noprompt

"$apksigner" rotate --out "$lineage" \
  --old-signer --ks "$old_keystore" --ks-key-alias "$old_alias" \
    --ks-pass env:OLD_PASS --key-pass env:OLD_PASS \
  --set-installed-data true --set-rollback false \
  --new-signer --ks "$new_keystore" --ks-key-alias "$new_alias" \
    --ks-pass env:STORE_PASS --key-pass env:STORE_PASS

echo 'Signing lineage (#1 old, #2 new):'
"$apksigner" lineage --in "$lineage" --print-certs | grep 'SHA-256'

base64 < "$new_keystore" | gh secret set ANDROID_RELEASE_KEYSTORE_BASE64 -R "$repo"
printf '%s' "$STORE_PASS" | gh secret set ANDROID_RELEASE_KEYSTORE_PASSWORD -R "$repo"
printf '%s' "$STORE_PASS" | gh secret set ANDROID_RELEASE_KEY_PASSWORD -R "$repo"
gh secret set ANDROID_RELEASE_KEY_ALIAS -R "$repo" --body "$new_alias"
base64 < "$lineage" | gh secret set ANDROID_SIGNING_LINEAGE_BASE64 -R "$repo"
unset STORE_PASS OLD_PASS GH_TOKEN

cat <<DONE

Done. GitHub secrets set: ANDROID_RELEASE_KEYSTORE_BASE64, ANDROID_RELEASE_KEYSTORE_PASSWORD,
ANDROID_RELEASE_KEY_PASSWORD, ANDROID_RELEASE_KEY_ALIAS, ANDROID_SIGNING_LINEAGE_BASE64.
The password is in Keychain Access under "$keychain_service".

Back up NOW, to two places you control offline (a USB drive, a password manager):
  $key_dir   (new key, old key copy, lineage)
  plus the Keychain password above.
If these are lost, Glyph can never be updated again.
DONE
