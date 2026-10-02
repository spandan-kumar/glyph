# Glyph — plan

A clean, fast animation app for WLED LED matrices with a huge library. Android
first, iOS from the same Flutter codebase later. Published on the stores, free
for now.

## Principles

- **Phone does the work.** The ESP only shows pixels or plays small GIFs, so it
  runs on any ESP8266/ESP32 variant and any amount of RAM/flash.
- **Detect, don't assume.** On connect we read `/json/info` + `/json/eff` and
  enable features per device (`DeviceCapabilities`).
- **Library is data.** Entries are generator id + params + palette (or a GIF
  asset), so the catalog grows from a CDN without app updates.
- **Licence-clean.** Our own effect code (no WLED/GPL code copied); art only
  from CC0/permissive sources, licence recorded per asset.

## Playback paths

| Path | How | Works on | Phone needed |
|---|---|---|---|
| Stream | DDP over UDP :4048, 40 fps | every ESP, WLED ≥ 0.14 | yes |
| Save to matrix | bake GIF on phone → `POST /upload` → Image effect → preset | ESP32 family + WLED 16 | no |
| Native | WLED built-in effects / presets via `/json/state` | every ESP | no |

## Roadmap

1. **Phase 0 – spike** ✅ DDP streaming verified on the dev matrix.
2. **Phase 1 – MVP**: device discovery/manual IP, now playing, ~20 generators,
   ~100 curated items, streaming, save-to-matrix, brightness, on-device presets.
3. **Phase 2 – Create**: pixel editor (frames, onion skin), scrolling text,
   clock, GIF/image import with crop, playlists, favourites.
4. **Phase 3 – Library**: CDN catalog (1000+), search/tags, audio reactive
   (mic FFT → stream), games with the phone as controller.
5. **Phase 4 – Polish**: widgets, schedules (WLED timers), multi-matrix sync,
   community sharing, Pro tier if wanted, iOS release.

## Dev device

WLED 16.0.1, ESP32 (4 MB flash, ~880 KB free FS), 16×16 serpentine,
`if.live.rlm = true` (realtime respects the 2D map), Image effect present.
Wi-Fi signal is weak (−91 dBm) — expect dropped frames when streaming.
