# Artist collection

The CC0 records below apply to these four creator-published packs.

Content revision 4 adds 27 animations from four creator-published CC0 packs.
Each animation gets one catalogue entry and an artist credit in its details.
The imports preserve original colours; they do not add palette variants or
whole-image movement to inflate the catalogue.

| Collection | Creator and source | Glyph entries | Native size |
|---|---|---:|---|
| Emotion bubbles | [Gabriel "tiopalada" Lima — Tiny RPG Emoji Pack I](https://opengameart.org/content/tiny-rpg-emoji-pack-i) | 20 | 32×32 |
| Living, frost and witchlight flames | [Stealthix — Animated Fires](https://opengameart.org/content/animated-fires) | 3 | 32×32 canvas |
| Jelly creatures | [Stealthix — Animated Slimes](https://opengameart.org/content/16x16-animated-slimes) | 2 | 16×16 |
| Condor and parrot | [MoikMellah — Animated Birds](https://opengameart.org/content/animated-birds-32x32) | 2 | 32×32 |

The source pages were reviewed on 11 October 2026 and identify these downloads
as CC0. The dedication is
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). The JSON
`source` blocks retain the work, creator, source page, licence, original
download URL and SHA-256, image/archive member, and adaptation notes.

## Adaptations

- Bubbles use the 16 populated cells in sheet order, at 100 ms per step.
  Four empty padding cells are omitted. Identical drawings share a stored
  frame while retaining their place in the play sequence.
- Flames retain every second frame of the 60-frame source, at 100 ms per
  step, for a three-second loop. Fixed positioning on a 32×32 canvas avoids
  jitter; the resulting 30 frames fit Glyph's sprite limits.
- Jellies use the front-facing idle row at 150 ms per step: four frames for
  green and two for blue. Both have an asserted 16×16 crop of unused margins
  from their 32×32 sheet cells.
- Birds retain their five-frame wing cycles at 100 ms per step. Their
  magenta background key becomes transparent; the empty sixth column is
  omitted.

32×32 art also plays on 16×16 displays through Glyph's existing scaling.
Review both sizes through the real generator before accepting changes;
native 32×32 carries more facial and wing detail.

## Reproduce and review

Run from the repository root, with Python 3, Pillow and Flutter available:

```bash
python3 tool/import_cc0_sprites.py
python3 skills/glyph-animation/scripts/validate_sprite.py --all
dart run tool/build_sprites.dart
dart run tool/build_catalog.dart
dart run tool/artist_preview.dart
flutter analyze
flutter test
```

Downloads are cached under `build/catalog-import/`. A changed upstream file
fails the SHA-256 check and requires a new source review. The importer does
not execute archive contents. It reads only the named image members.

`build/artist_preview/collection.gif` previews all entries at both sizes
through Glyph's player. `collection.png` is a still, and `highlights.png`
and `highlights.gif` show six selected entries. These files are review
artifacts, not catalogue payloads. Device GIF baking and loop timing are covered by
`test/library/cc0_catalog_test.dart`.

Changing art already published requires new sprite and item IDs, as in
[catalogue delivery](CATALOG_DELIVERY.md). Rebuild and verify the unsigned
remote payload against the published catalogue before releasing it through
the protected catalogue workflow.
