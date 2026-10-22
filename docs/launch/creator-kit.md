# Glyph creator kit

Glyph is a free, MIT-licensed Flutter app that drives WLED LED matrices with 1,200+ animations, pixel art, clocks, games and live music features, with no account. Your phone renders the frames, streaming them live or sending a GIF to a compatible controller for playback without the phone.

**For:** WLED display owners, ESP32 makers building a first panel, pixel artists, and Home Assistant users who want an existing display to do more.

## What to show

- **Set up display:** Wi-Fi join, size selection, three physical wiring answers, review and a visual check.
- **Display:** swipe channels, choose palettes and tune motion across 1,236 looks in 22 subject groups: 62 procedural generators, 356 sprites and public-domain classics.
- **Make:** draw live, scrolling text, GIF/WebP/photo import, clocks/timers, nine microphone visualisers and seven games.
- **Now Playing:** Android album art and progress, live on the panel. Needs the phone; covers are not stored.
- **Device:** Send, Saved, Shows and Routines run without the phone on supported hardware. Home Assistant blueprints trigger existing Saved looks or Shows.
- **Glance:** weather, forecast, modelled air quality and day counters. Cards/Rotations need the phone; weather/air quality use Open-Meteo. Counters work offline.

**Coverage:** v1.4.12 is current; setup, Glance and Home Assistant blueprints shipped in v1.4.0. Fresh-controller and live Home Assistant checks remain pending; grids and iOS have automated coverage only. Android first; iOS is untested on hardware.

## Hardware and budget

Typical build: **16×16 WS2812B 5 V panel (256 LEDs), ESP32 running WLED 16+, suitable 5 V supply, wiring/connectors and diffuser/enclosure**, plus an Android phone on the same Wi-Fi. Use a separate panel power feed, common ground and suitable current limit. [Install WLED](https://install.wled.me) first; Glyph does not flash firmware.

Budget roughly **US$40–80**, excluding phone, tools, shipping and taxes. This planning estimate varies by supplier; branded builds cost more. [Robu's panel listing](https://robu.in/product-category/rgb-led-strip/) showed a 16×16 5 V WS2812 panel at ₹1,329 on 11 October 2026. ESP8266/older WLED can stream; Send requires GIF support and free controller storage.

## Three clip ideas

1. **“Which corner lit up?”** Film three wiring answers, then the arrow check. Mark cuts through review/apply; three taps cover wiring, not all Wi-Fi setup.
2. **“Swipe, see it change.”** Keep phone and panel in one shot as three Display channels change, then tune a palette.
3. **“Album art becomes pixels.”** Play creator-owned cover art, open Now Playing and hold on the progress bar. Caption “Live from your phone.”

## Links, assets and contact

[Source](https://github.com/spandan-kumar/glyph) · [APK/releases](https://github.com/spandan-kumar/glyph/releases/latest) · [Obtainium updates](https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/spandan-kumar/glyph) · [Discord](https://discord.gg/fMbzGQd6wk)

Assets in [`docs/media`](../media/): `icon.png`, `social_preview.png`, `intro.gif`; screenshots `display.png`, `rails.png`, `tweak.png`, `make.png`, `draw.png`, `device.png`. Refresh outdated screenshots. Filming: [storyboard](video-storyboard.md).

**Contact:** Spandan Kumar, maintainer, via [GitHub Discussions](https://github.com/spandan-kumar/glyph/discussions) or [Discord](https://discord.gg/fMbzGQd6wk); label creator/press requests.

**Rights/credits:** Code and original artwork are MIT; retain copyright/licence notices when redistributing substantial portions. Suggested credit: “Glyph by Spandan Kumar, MIT; powered by WLED.” Glyph is independent of WLED. Public-domain art has source/jurisdiction notes; fonts use SIL OFL. Open-Meteo data is CC BY 4.0; preserve Open-Meteo, CAMS/Copernicus and applicable GeoNames credits. Air quality is a CAMS model forecast, not a sensor reading. Use creator-owned music/covers or obtain permission.
