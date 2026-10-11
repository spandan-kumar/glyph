#!/usr/bin/env bash
# Back up every secret Glyph depends on into ONE encrypted disk image you can keep
# in Google Drive: both Android signing keys, the rotation lineage, the release key
# password, the catalog signing key and (if you paste it) the Discord webhook.
# The image is AES-256 encrypted with a passphrase you choose and must remember;
# without it a Drive leak would let someone ship fake Glyph updates and catalogs.
# Usage: tool/backup_secrets.sh [OUTPUT_DIR]   (default: ~/Desktop)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
[[ -t 0 ]] || { echo 'Run in a terminal: it asks for a passphrase.' >&2; exit 1; }

out_dir=${1:-"$HOME/Desktop"}
keys="$HOME/glyph-release-keys"
stamp=$(date +%Y-%m-%d)
image="$out_dir/glyph-secrets-$stamp.dmg"
[[ -e $image ]] && { echo "$image already exists." >&2; exit 1; }
[[ -f $keys/glyph-release.jks && -f $keys/glyph-signing.lineage ]] \
  || { echo "Missing $keys (run tool/setup_release_signing.sh first)." >&2; exit 1; }

umask 077
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dir="$work/glyph-secrets"
mkdir -p "$dir"
cp -p "$keys"/glyph-release.jks "$keys"/glyph-signing.lineage "$dir/"
cp -p "$HOME/.android/debug.keystore" "$dir/old-debug.keystore"

release_pass=$(security find-generic-password -s 'Glyph release keystore' -a glyph-release -w)
catalog_key=$(security find-generic-password -s dev.spandankumar.glyph.catalog-signing -a spandan-kumar -w 2>/dev/null || true)
read -r -s -p 'Paste the Discord webhook URL to include it (or press Return to skip): ' discord
echo

{
  echo "Glyph secrets backup, $stamp. Keep this image encrypted."
  echo
  echo "== Android signing (GitHub repo secrets) =="
  echo "New key file:      glyph-release.jks (PKCS12)"
  echo "New key alias:     glyph-release"
  echo "New key password:  $release_pass   (store and key password are the same)"
  echo "  -> ANDROID_RELEASE_KEYSTORE_BASE64 = base64 of glyph-release.jks"
  echo "  -> ANDROID_RELEASE_KEYSTORE_PASSWORD / ANDROID_RELEASE_KEY_PASSWORD = the password"
  echo "  -> ANDROID_RELEASE_KEY_ALIAS = glyph-release"
  echo "Lineage file:      glyph-signing.lineage -> ANDROID_SIGNING_LINEAGE_BASE64 (base64)"
  echo "Old key file:      old-debug.keystore (alias androiddebugkey, password android)"
  echo "  -> ANDROID_KEYSTORE_BASE64 / _PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD"
  echo "Fingerprints: old 8f7a1d1830d401866985253d480eb7f4748c4c1144a8eb77f0e11448c28f9b68"
  echo "              new d9f51a1f873db96bfec0be9c230e5ec2ead72660aa42abaf04389291ad84441e"
  echo
  echo "== Catalog signing (GitHub environment 'catalog' secret CATALOG_SIGNING_KEY) =="
  if [[ -n $catalog_key ]]; then echo "$catalog_key"; else echo "(not found in Keychain on this Mac)"; fi
  echo
  echo "== Discord release announcements (repo secret DISCORD_WEBHOOK_URL) =="
  if [[ -n $discord ]]; then echo "$discord"; else echo "(not included; recreate in Discord: channel settings > Integrations > Webhooks)"; fi
  echo
  echo "Restore: set the secrets above with 'gh secret set NAME -R spandan-kumar/glyph'"
  echo "(catalog: add '--env catalog'), and see docs/SIGNING.md and docs/CATALOG_DELIVERY.md."
} > "$dir/SECRETS.txt"
unset release_pass catalog_key discord

echo 'Choose a passphrase for the backup image (you will need it to open the backup).'
hdiutil create -quiet -fs HFS+ -encryption AES-256 -volname glyph-secrets -srcfolder "$dir" "$image"
chmod 600 "$image"
echo
echo "Created $image (AES-256). Upload it to Google Drive, then delete the local copy."
echo 'Keep the passphrase somewhere other than Drive (your memory or password manager).'
