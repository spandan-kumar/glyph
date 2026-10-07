#!/usr/bin/env bash
# Mirrors the live catalog site into $1 (default build/published): current and
# previous manifests, their signatures and payloads. A 404 on the manifest
# means "nothing published yet"; any other failure aborts so a hosting
# problem can never make the workflow discard the previous artifact.
set -euo pipefail
base="${BASE_URL:-https://spandan-kumar.github.io/glyph}"
out="${1:-build/published}"
mkdir -p "$out/payload"

fetch() { # path -> returns 0 if fetched, 1 on 404
  local code
  code=$(curl --silent --show-error --max-time 20 --max-filesize 2097152 \
    --output "$out/$1" --write-out '%{http_code}' "$base/$1?run=${GITHUB_RUN_ID:-0}")
  if [ "$code" = 404 ]; then rm -f "$out/$1"; return 1; fi
  if [ "$code" != 200 ]; then echo "::error::Cannot retain $1 (HTTP $code)"; exit 1; fi
}

for name in manifest-v1.json previous-manifest-v1.json; do
  if fetch "$name"; then
    fetch "$name.sig" || { echo "::error::$name has no signature"; exit 1; }
    payload=$(jq -r '.payload' "$out/$name")
    case "$payload" in payload/[0-9a-f]*.json) ;; *) echo "::error::Unexpected payload path"; exit 1;; esac
    fetch "$payload" || { echo "::error::$name lacks its payload"; exit 1; }
  fi
done
