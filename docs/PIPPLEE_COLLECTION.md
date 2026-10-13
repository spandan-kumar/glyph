# Pipplee collection

The import retains **all 12,361 IDs** from the Pipplee animation endpoint,
across 413 pages fetched on 13 October 2026. It adds them to Glyph's existing
1,236 entries, for **13,597 total entries**. Nothing is omitted or merged at
the catalogue level. Identical converted content shares a file: there are
12,273 distinct clips, totalling 31,447,891 compressed bytes (30.0 MiB).

## Permission and credit

On 13 October 2026, Glyph's maintainer confirmed that they asked the Pipplee
creator directly and have consent to use this collection. They retain the
Discord conversation privately. This import follows that explicit
authorization as an exception to Glyph's usual original/CC0 art policy.
It does not change that policy for other contributions.

These assets are labelled `shared-with-permission`, not CC0 or MIT. The API
does not provide original artist names, titles or per-work licences; the app
uses stable titles `Pipplee <id>` and the notice "From the Pipplee catalogue,
shared with permission." No private messages or account credentials are
included. `catalog_assets/pipplee/NOTICE` retains the collection credit.

## Source and conversion

The public endpoint is `https://pipplee.com/api/v1/animations?p=N`.
`page=N` does not advance pagination. The complete fetched archive contains
the original responses and GIFs, download verification, and a local review
gallery. It is separate from the repository because the GIFs total 718.9 MiB.

`tool/import_pipplee.py` verifies every original GIF against that archive's
manifest, decodes every composited frame with Pillow, and samples each LED
cell's centre at the API's `min_width` and `min_height`. This removes preview
magnification and thin grid lines. Source dimensions range from 8×8 to 64×64,
including rectangular strips. The largest animation has 151 frames.

Colours and frame order are retained. GIF waits of 0 or 10 ms become 100 ms,
matching Glyph's GIF-import convention; other waits are retained. No frames
are dropped. `provenance.json` records source and converted hashes, frame
counts and total durations for every ID. Display fitting uses Glyph's
existing nearest-neighbour scaling and centred letterboxing.

## Format and delivery

The app bundles the small `assets/catalog/pipplee.json` index. Each row holds
the upstream ID, clip SHA-256, compressed size, width, height, frame count and
up to three colour tags. Clips live outside the APK in
`catalog_assets/pipplee/<sha256>.clip.gz`.

Display gives the collection its own lead shelf. See all exposes every
entry; search supports source IDs, native dimensions and colour tags.

The gzip payload is a little-endian `GLC1` stream: four magic bytes, uint16
width, uint16 height, uint32 frame count; then for each frame a uint32 delay
in milliseconds followed by `width * height * 3` RGB bytes.

The existing GitHub Pages catalogue workflow copies hash-verified clips to
`collections/pipplee/<sha256>.clip.gz` for both publication and rollback.
The existing signed sprite catalogue stays separate. The bundled index pins
each clip's hash and size; decoding also checks its dimensions, frame count,
timings and exact expanded size in an isolate.

Only visible thumbnails request downloads, with at most four requests at
once. The disk cache holds up to 96 MiB, and the decoded LRU holds up to
4 million pixels. Active playback and Rotations retain their own decoded
clips. After the first download, a clip plays offline until its cached file
is evicted or app storage is cleared. The app makes no requests to Pipplee.

Picking a clip keeps the previous look playing while it loads. Failed or
stale downloads cannot replace that look. Send waits for loading to finish
and repeats long GIF holds in steps of at most one second, preserving the
duration while avoiding WLED's carried-over frame delay.

**Publication order:** deploy the Pages assets before distributing an app
build containing this index. Older app versions do not support this clip
collection. Adding the files locally does not publish the Pages URLs.

## Reproduce and verify

With the fetched archive, Python 3 + Pillow, and Flutter available:

```bash
python3 tool/import_pipplee.py --archive /path/to/catalogue-fetch --workers 4
python3 skills/glyph-animation/scripts/validate_sprite.py --all
bash tool/fetch_published_catalog.sh build/pipplee/published
dart run tool/build_remote_catalog.dart --published build/pipplee/published --output build/pipplee/site
dart run tool/pipplee_preview.dart
flutter analyze
flutter test
```

The importer regenerates both the compact index and provenance ledger. Tests
verify every source ID remains, hash and decode every distinct clip, and
cover download verification, offline caching, request limits, hidden
previews, stale playback/Rotation requests and device GIF timing.
