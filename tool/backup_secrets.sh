#!/usr/bin/env bash
# Back up every secret Glyph depends on into ONE zip for your Google Drive: both
# Android signing keys, the rotation lineage, the release key password, the catalog
# signing key and (if you paste it) the Discord webhook, plus restore steps.
# The zip is plain (anyone who can open it can sign Glyph updates and catalogs);
# pass --encrypt for an AES-256 disk image with a passphrase instead.
# Usage: tool/backup_secrets.sh [--encrypt] [OUTPUT_DIR]   (default: ~/Desktop)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
encrypt=false
if [[ ${1:-} == --encrypt ]]; then encrypt=true; shift; fi
[[ -t 0 ]] || { echo 'Run in a terminal: it asks for the Discord webhook.' >&2; exit 1; }

out_dir=${1:-"$HOME/Desktop"}
keys="$HOME/glyph-release-keys"
stamp=$(date +%Y-%m-%d)
if $encrypt; then image="$out_dir/glyph-secrets-$stamp.dmg"; else image="$out_dir/glyph-secrets-$stamp.zip"; fi
[[ -e $image ]] && { echo "$image already exists." >&2; exit 1; }
[[ -f $keys/glyph-release.jks && -f $keys/glyph-signing.lineage ]] \
  || { echo "Missing $keys (restore it from your backup first)." >&2; exit 1; }

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
  echo "Glyph secrets backup, $stamp. Anyone with these can sign Glyph releases and catalogs."
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

if $encrypt; then
  echo 'Choose a passphrase for the backup image (you will need it to open the backup).'
  hdiutil create -quiet -fs HFS+ -encryption AES-256 -volname glyph-secrets -srcfolder "$dir" "$image"
else
  (cd "$work" && zip -qr -X "$image" glyph-secrets)
fi
chmod 600 "$image"
echo
echo "Created $image. Upload it to Google Drive, then delete the local copy."
