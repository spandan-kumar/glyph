# Pipplee collection

The import retains **all 12,361 IDs returned by the frozen crawl** of the
Pipplee animation endpoint, across 413 pages fetched on 13 October 2026.
This is a snapshot, not a claim that the endpoint exposed every animation
available in Pipplee’s app. It adds them to Glyph's existing
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
does not provide original artist names, titles or per-work licences. Glyph
authors descriptive names and search words from the visible clips; these are
not original artist titles. The notice remains "From the Pipplee catalogue,
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

The app bundles the `assets/catalog/pipplee.json` index and all 12,273 distinct
compressed clips, so the complete collection works offline from first launch.
Each row holds the upstream ID, clip SHA-256, compressed size, width, height,
frame count, up to three colour tags, and authored title, subjects, aliases and tags
(schema version 3 also appends a browsing category). The parser also accepts
version 1 and 2 rows. Clips live in
`catalog_assets/pipplee/<sha256>.clip.gz`, included as Flutter assets.

Display starts with All, including the whole library and your creations.
Imported animations join subject shelves such as Animals, Nature, Holidays,
Gaming and Abstract, while Pipplee remains their collection and credit.
`tool/pipplee_categories.py` derives categories from the reviewed subjects,
names and tags, matching whole words. Occasion and game context take priority;
otherwise concrete subjects take priority over accessories. Geometric waves
do not become ocean scenes, and colours never infer a subject. An authored
`category` in the description can override the rule for an individual clip.
There is no separate Pipplee shelf: imports appear in the same subject groups
as the rest of the library. See all exposes every entry; search supports
descriptive names, subjects, aliases, source IDs,
native dimensions and colour tags.
Explicit flag subjects have a Flags group. Abstract grids, stripes, mosaics
and repeated patterns move to Patterns; clearly described spirals and tunnels
join Hypnotic. Concrete subjects and occasion context keep priority, so a
striped cat remains in Animals and a Halloween flag stays in Holidays.
Search now matches words rather than arbitrary substrings, collapses identical
clips in its results, and excludes the placeholder `rainbow` palette. Use
`collection:pipplee red 32x32` to constrain collection, colour and native size.
Exact source-ID queries retain access to every record. The search algorithm
does not infer subjects from the GIFs; it indexes the authored metadata.

The gzip payload is a little-endian `GLC1` stream: four magic bytes, uint16
width, uint16 height, uint32 frame count; then for each frame a uint32 delay
in milliseconds followed by `width * height * 3` RGB bytes.

The existing GitHub Pages catalogue workflow copies hash-verified clips to
`collections/pipplee/<sha256>.clip.gz` for both publication and rollback.
The existing signed sprite catalogue stays separate. The bundled index pins
each clip's hash and size; decoding also checks its dimensions, frame count,
timings and exact expanded size in an isolate.

Only visible thumbnails load clips. Bundled clips are hash-verified and decoded
directly from the app assets without network requests, disk-cache scans or
waiting for a download slot. The decoded LRU holds up to 4 million pixels;
active playback and Rotations retain their own decoded clips. A decoded-cache
eviction still reloads from the bundle offline. Unbundled clips retain the
verified download fallback, with at most four downloads at once and a 96 MiB
disk cache. The app makes no requests to Pipplee.

Picking a clip keeps the previous look playing while it loads. Failed or
stale downloads cannot replace that look. Send waits for loading to finish
and repeats long GIF holds in steps of at most one second, preserving the
duration while avoiding WLED's carried-over frame delay.

The Pages copies remain available to older app versions that download clips.
New app builds include the full collection and do not depend on Pages for it.
New, unbundled clips must still be published before their index is distributed.

## Names and search words

`catalog_assets/pipplee/descriptions.json` records a description for every
unique clip SHA-256. Names are short visible descriptions; subjects name
objects, aliases hold alternate names, and tags describe colour, motion or
style. Recognisable fictional characters use their canonical names, with
franchise and alternate names in aliases. Generic descriptions are reserved
for unclear identities or unreadable text.
Useful old descriptions remain searchable; incorrect character identities
and their franchise aliases are removed. Common subject nouns include singular
and plural forms so “cat” and “cats” both work.

Parallel Luna agents drafted names from multi-frame previews. Audits caught
labels shifted between neighbouring thumbnails and misidentified objects, so
stronger visual agents checked larger, numbered previews against the names,
subjects, aliases and authored tags. The parent agent corrected selected
entries and inspected full frame sequences where needed. Every unique clip
received a visual review, but this is not a claim that every frame was
individually inspected; the ledger retains confidence and review information
for future corrections.

The targeted character audit on 15 October 2026 covered 6,285 unique clips
selected from character, people, face, animal, game, holiday and related
metadata, correcting 118 unique clips (119 source records). Parallel drafts
were followed by independent stronger visual QA,
including enlarged sequences for each accepted correction and parent review.
Accepted changes retain the identifying evidence and date in the description
ledger's `identity_review` field. Ambiguous lookalikes remain descriptive;
this is a targeted audit, not a guarantee that every character in the full
collection has been identified.

The follow-up pass covered the other 5,988 unique clips and revisited all
113 uncertain clips from the targeted audit in enlarged sequences. Together,
the two passes overviewed all 12,273 unique clips. The follow-up corrected
another 107 unique clips (109 source records), including fictional identities,
object names, search terms and categories. Each correction received an
exact-hash enlarged-sequence check and independent parent review. A full-frame
text check kept a truncated scrolling word descriptive instead of completing
it from a guess.

The ledger's `catalogue_audit` records coverage counts and a digest of the
reviewed hashes. Its 106 unresolved identities retain descriptive names and
an `identity_uncertainty` reason. Overview coverage means sampled frames from
every clip; it does not claim inspection of every frame or resolution of every
fictional identity. Pixels, timings and source IDs remain unchanged.

The maintainer supplied visual hints for 97 of the 106 uncertain entries,
then chose generic naming for this group. A further enlarged-sequence review
checked all 106, refining 68 entries and keeping 38 accurate generic names.
The ledger records this choice in `naming_review` and
`catalogue_audit.human_guided_generic_review`. These names describe visible
objects and actions; the identity uncertainty notes remain internal evidence.
No new character or franchise identity was inferred from the hints.

`tool/build_pipplee_names.py` requires complete hash coverage, validates the
metadata, and regenerates the bundled index. It gives colliding titles
stable numeric suffixes while retaining their natural name as an alias.
Existing item IDs, content hashes, pixels and timings are unchanged, so
favourites and saved references continue to work. Send retains each imported
clip’s original device filename, and the Stage uses that identity to recognise
a Saved look after reconnecting. The importer reapplies
this ledger when rebuilding the same frozen archive.

## Reproduce and verify

With the fetched archive, Python 3 + Pillow, and Flutter available:

```bash
python3 tool/import_pipplee.py --archive /path/to/catalogue-fetch --workers 4
python3 tool/build_pipplee_names.py
python3 skills/glyph-animation/scripts/validate_sprite.py --all
bash tool/fetch_published_catalog.sh build/pipplee/published
dart run tool/build_remote_catalog.dart --published build/pipplee/published --output build/pipplee/site
dart run tool/pipplee_preview.dart
flutter analyze
flutter test
```

The importer regenerates both the compact index and provenance ledger. The
name builder needs only Python’s standard library; a metadata correction
does not require downloading or converting GIFs again. Tests verify that the
named index is reproducible, every source ID remains, hash and decode every
distinct clip, and
cover download verification, offline caching, request limits, hidden
previews, stale playback/Rotation requests and device GIF timing.
