# AGENTS.md

Guidance for AI coding agents (and humans) working on Glyph. `CLAUDE.md` and
`CODEX.md` point here; keep this file the single source of truth.

## Project

Glyph is a Flutter app (Android first, iOS from the same code) that drives
WLED LED matrices. The phone renders every frame; Glyph either **streams**
frames live over DDP or **sends** a baked GIF to the controller, which plays
it with WLED's Image effect and a saved preset.

- Package: `glyph` · App id: `dev.spandankumar.glyph` · Dart 3.13, Flutter 3.47
- Product/UX spec: `docs/design/UX.md` (design language "Lightbox")
- Roadmap: `docs/PLAN.md`

## Commands

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # Flutter location on the dev machine
flutter pub get
flutter analyze                     # must report "No issues found!"
flutter test                        # full suite (~960 tests, ~30 s)
flutter test test/engine            # one area
flutter build apk --release --split-per-abi --target-platform android-arm64
dart run tool/stream_smoke.dart <device-ip> plasma 5   # stream an effect from the computer
```

Generated files — regenerate, never hand-edit:

```bash
dart run tool/build_sprites.dart    # assets/catalog/sprites/*.json → lib/engine/generators/sprite_data.g.dart
dart run tool/build_catalog.dart    # → assets/catalog/catalog.json
dart run tool/make_icon.dart        # launcher icons + assets/brand/glyph_icon.svg (amber LED-dot g)
```

A test fails if the generated sprite data or catalog is stale.

## Layout

```
lib/
  engine/     pure Dart: Frame, palettes, generators, sprites, intro, GIF baker/encoder, LED gamma
  wled/       WLED client (JSON API, upload, presets, schedules), DDP sender/groups, discovery
  library/    catalog model, bundled/remote catalog, favourites & recents
  app/        PlaybackController, DeviceStore, creations, background streaming, storage alerts
  features/   editor, text (Write/Clock/Timer), import, audio, games, device (manager, boot intro)
  ui/         design kit (ui/design), Display (ui/tune), Make (ui/make), Device (ui/matrix),
              onboarding, splash, theme, GlyphActions (ui/actions.dart)
assets/       catalog JSON, sprite packs, fonts (OFL), brand
tool/         builders, previews, smoke tests
test/         mirrors lib/
docs/         UX spec, plan, README media
release/      the current APK + sha256
```

## Conventions

- **Engine stays pure Dart** (`lib/engine`, most of `lib/wled`): no Flutter
  imports, so it runs in isolates and `dart run` tools.
- **UI uses the design kit only** (`lib/ui/design`: `Lb` tokens, `LbType`,
  `Stage`, `Knob`, `LedText`, parts). Geometry is sharp: radii 1–3 px; only
  LED dots and knobs are round. No stock Material look, no gradients.
- **User-facing words:** Display / Make / Device; "device", not "matrix";
  **Send** (not Keep/Save to matrix); **Saved**, **Shows**, **Routines**.
  Never show "preset", "playlist", "segment" or "DDP" in primary UI.
- Match the surrounding code's style: concise, sparse comments that explain
  *why*, Dart 3 records/patterns where they help.
- Content must be original or public-domain/CC0; no trademarked characters,
  no code copied from WLED (EUPL) or other copyleft sources.

## Testing

- Widget tests: pump fixed durations, **never `pumpAndSettle`** (previews
  tick forever); pause playback at the end of a test.
- Device behaviour is tested against fakes (`test/features/device/fake_wled.dart`,
  `http` `MockClient`); the live-device test only runs with `GLYPH_LIVE_HOST`.
- Run `flutter analyze` and the relevant tests before calling work done.

## WLED gotchas (verified against WLED 16.0.1 source)

- **GIF frame waits carry over between files** (`image_loader.cpp` never
  resets `currentFrameDelay`). Device GIFs cap every frame at 1 s
  (`deviceMaxFrameCs`); never add long holds.
- Streamed (DDP) frames skip WLED's gamma when `if.live.no-gc` is true — the
  app applies device gamma/white balance itself (`lib/engine/led_gamma.dart`);
  GIFs are left to WLED's gamma (no double correction).
- Upload first, switch after: `saveGifToDevice` verifies the file before
  leaving live mode; a failed send must leave the device untouched.
- Re-sending an animation reuses its preset (no duplicates). The boot intro
  (`glyph-intro.gif`, "Glyph intro", "Power-on") is system-owned: hidden and
  undeletable in the app.
- A playing GIF can be deleted only after switching the segment away from it.

## Real-device etiquette

When testing against a real controller: snapshot `/json/state`,
`/presets.json` and `/cfg.json` first, restore them afterwards, delete any
test files/presets you create, and never touch the user's own presets or
files. Don't flash test streams on someone's display without saying so.

## Git

- Work on `main` unless told otherwise; commit only when asked.
- Commit messages: imperative summary line, a body explaining why.
- Releases: bump `version:` in `pubspec.yaml`, rebuild the APK into
  `release/` with its `.sha256`, tag `vX.Y.Z` on GitHub.
