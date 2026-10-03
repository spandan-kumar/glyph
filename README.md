# Glyph

A clean, fast app for animating WLED LED matrices — 1,097 animations, a pixel
editor, scrolling text and clocks, GIF import, a music visualiser, games, and
full control of what's stored on the matrix.

Glyph does the rendering on your phone and either **streams** frames to the
matrix live or **saves** them onto it, so it works with any WLED controller
regardless of how much memory it has.

> Status: 1.1.0, Android. iOS builds from the same code but hasn't been tested
> yet.

## Install

Download [`release/glyph-1.1.0-arm64-v8a.apk`](release/glyph-1.1.0-arm64-v8a.apk)
on an Android phone (7.0+, 64-bit ARM — almost every phone from the last few
years) and open it. You'll need to allow installs from your browser or file
manager. The SHA-256 checksum is next to it.

This APK is signed with a debug key, so it's for sideloading only.

## What you need

- A WLED controller driving an LED matrix (tested with WLED 16.0.1 on an ESP32
  with a 16×16 WS2812B panel)
- In WLED, the matrix set up under **Settings → 2D Configuration**
- Your phone on the same Wi-Fi as the matrix

| Controller | Live streaming | Save GIFs to the matrix |
|---|---|---|
| ESP32 / S2 / S3 / C3 on WLED 16+ | ✅ | ✅ |
| ESP32 on WLED 0.14–0.15 | ✅ | — (built-in effects and presets only) |
| ESP8266 | ✅ | — (WLED has no GIF player there) |

Glyph checks what each controller supports when it connects and only offers
what works.

## Features

**Discover** — 1,097 animations across 18 categories: 62 procedural effects
(plasma, fire, aurora, reaction–diffusion, falling sand, black holes…) and 247
original pixel-art sprites (faces, weather, animals, food, holidays, symbols).
Every effect can be recoloured with 42 palettes and tuned with sliders.
Favourites, recently played, seasonal shelves and ranked search.

**Create**
- **Pixel editor** — frames, onion skin, mirror drawing, fill, line, shapes,
  undo, and a live mirror that shows your drawing on the matrix as you draw.
- **Scrolling text, clock and countdown** — hand-made pixel fonts. Clocks are
  saved using WLED's own Scrolling Text effect, so they keep showing the real
  time with your phone off.
- **Import** — any GIF, WebP or photo, with crop, LED colour tuning,
  background removal and a size check before saving.
- **Music** — nine visualisers driven by the microphone, with automatic gain
  and beat detection. Audio never leaves the phone.
- **Games** — Snake, Blocks, Brick Breaker, Pong, Flap, Racer and Invaders,
  with the phone as the controller and the matrix as the screen.
- Share creations as a GIF or an editable `.glyph` file.

**Your matrix**
- Presets with thumbnails, playlists and schedules that run on the matrix
  without the phone, and a file manager for what's stored on it.
- Power, brightness and night light.
- Stream to several matrices at once.
- Keep streaming with the screen off (Android).
- Home-screen widget with power and next-preset buttons.

## How it works

```
 Phone: render engine ──┬── Stream: DDP over UDP :4048, 40 fps ──────┐
 (same code draws the   │                                            ├─► WLED ─► LEDs
  previews and the      └── Save: encode GIF → POST /upload →        │
  real LEDs)                Image effect → preset ───────────────────┘
```

- **Streaming** sends each frame with [DDP](https://kno.wled.ge/interfaces/ddp/).
  A 16×16 frame is 768 bytes, so one packet per frame.
- **Saving** bakes the animation into a compact GIF (one shared colour table,
  only changed pixels per frame — typically 8–25 KB for a 4-second 16×16
  loop), uploads it and saves a WLED preset so it plays on its own.
- The library is data: each item is an effect id plus parameters and a
  palette, or a sprite. New items can be delivered as a catalog file without
  an app update (the remote catalog is supported but not hosted yet).

## Build from source

Requires Flutter 3.47+ (Dart 3.13) and the Android SDK.

```bash
flutter pub get
flutter test
flutter run                      # debug on a connected phone
flutter build apk --release --split-per-abi --target-platform android-arm64
```

`pubspec.yaml` pins `permission_handler_android` to 13.0.1: version 14 needs
`compileSdk 37`, which the Android Gradle plugin in Flutter's current template
(9.1) can't build yet.

To stream an effect from your computer without the app (handy for testing):

```bash
dart run tool/stream_smoke.dart <matrix-ip> plasma 5
```

### Editing the library

Sprites live in `assets/catalog/sprites/*.json`; the catalog is generated.

```bash
dart run tool/build_sprites.dart    # sprites → lib/engine/generators/sprite_data.g.dart
dart run tool/build_catalog.dart    # → assets/catalog/catalog.json
dart run tool/sprite_preview.dart   # render sprite sheets to PNG for review
```

A test fails if the generated files are out of date.

## Project layout

```
lib/
  engine/     render engine: frames, palettes, generators, sprites, GIF encoder
  wled/       WLED client: JSON API, DDP streaming, discovery, presets, schedules
  library/    catalog, favourites, remote catalog
  app/        playback, devices, creations, background streaming
  features/   editor, text, import, audio, games, device management
  ui/         theme, Discover, Now Playing, shared widgets
tool/         catalog and sprite builders, previews, streaming smoke test
docs/PLAN.md  product plan and roadmap
```

## Not done yet

- Hosting the remote catalog, so new animations can ship without an update
- An online community feed (sharing currently works by sending files)
- iOS testing and release (background streaming isn't supported on iOS)
- Play Store release: needs a release signing key, a privacy policy
  (microphone use) and the foreground-service declaration

## Content and credits

All effects and pixel art in the library are original to this project. No
code was copied from WLED or other GPL/EUPL projects; WLED's documented APIs
are used to talk to the controller.

Glyph is not affiliated with the WLED project.
