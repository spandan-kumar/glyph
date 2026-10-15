# AGENTS.md

Guidance for AI coding agents (and humans) working on Glyph. `CLAUDE.md` and
`CODEX.md` point here; keep this file the single source of truth. Read it
fully before your first change.

## Project

Glyph is a Flutter app (Android first, iOS from the same code) that drives
WLED LED matrices. The phone renders every frame; Glyph either **streams**
frames live over DDP or **sends** a baked GIF to the controller, which plays
it with WLED's Image effect and a saved preset.

**North star:** the device is the hero; the phone is its remote. Every screen
keeps the device visible (the Stage), every action shows up on it instantly,
and the app's only colour comes from what the device is showing.

- Package: `glyph` · App id: `dev.spandankumar.glyph` · Dart 3.13, Flutter 3.47
- Product/UX spec: `docs/design/UX.md` (design language "Lightbox")
- Roadmap: `docs/PLAN.md` (engineering), `docs/ROADMAP.md` (launch and community)

## How to work

- **Read before you write.** Find the existing pattern (a sibling screen, the
  client method next door, the fake in `test/`) and follow it. Prefer
  extending what exists over a new abstraction.
- **Own the UX decisions.** Specs and plans are guides, not scripts. Choose
  what serves the user's journey, then say what you chose and why.
- **Verify, don't assume.** WLED behaviour is checked against its source or a
  real device, never guessed. When a doc and the code disagree, the code
  wins; fix the doc.
- **Small, focused diffs.** Never run `dart format` (or any reformatter) over
  files you didn't change; reformatting unrelated files has been reverted
  before. Don't touch generated files by hand.
- **Done means checked:** `flutter analyze` is clean, the relevant tests pass,
  and anything device-facing was tried on hardware when hardware is available.
  Report failures and skipped steps plainly.
- **Ask only for real decisions** (product direction, anything involving the
  maintainer's accounts, money or secrets). Otherwise pick the sensible
  default, proceed and mention it.
- **Secrets are the maintainer's.** Never read, print, type or commit
  passwords, keystores or signing keys. Write a script for the maintainer to
  run instead.
- When you split work across helper agents, give each a narrow, explicit task
  and the files it owns, and review what comes back before committing.

## Commands

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # Flutter location on the dev machine
flutter pub get
flutter analyze                     # must report "No issues found!"
flutter test                        # full suite (~1,000 tests, under a minute)
flutter test test/engine            # one area
flutter build apk --release --split-per-abi --target-platform android-arm64
dart run tool/stream_smoke.dart <device-ip> plasma 5   # stream an effect from the computer
```

Generated files: regenerate, never hand-edit.

```bash
dart run tool/build_sprites.dart    # assets/catalog/sprites/*.json → lib/engine/generators/sprite_data.g.dart
dart run tool/build_catalog.dart    # → assets/catalog/catalog.json
dart run tool/make_icon.dart        # launcher icons + assets/brand/glyph_icon.svg (amber LED-dot g)
```

A test fails if the generated sprite data or catalog is stale.

## Layout

```
lib/
  engine/     pure Dart: Frame, palettes, generators, sprites, intro, GIF baker/encoder,
              LED gamma, setup test frames
  wled/       WLED client (JSON API, upload, presets, schedules, setup: Wi-Fi, panels,
              LED count, time), DDP sender/groups, discovery, panel grids, timezones
  library/    catalog model, bundled/remote signed catalog, favourites & recents
  app/        PlaybackController (incl. alerts), DeviceStore, creations, background
              streaming, storage alerts, What's new
  features/   editor, text (Write/Clock/Timer), import, audio, games, now_playing,
              notifications (logo alerts), glance (weather, forecast, air, countdowns,
              Rotations), device (manager, boot intro, time, setup wizard logic)
  ui/         design kit (ui/design), Display (ui/tune), Make (ui/make), Device
              (ui/matrix), setup wizard (ui/setup), onboarding, community, theme,
              GlyphActions (ui/actions.dart)
android/      MainActivity (platform channel), Wi-Fi setup bridge, notification listener
ios/          AppDelegate (platform channel), Info.plist (local network)
assets/       catalog JSON, sprite packs, fonts (OFL), brand
homeassistant/ blueprints (show a Saved look, play a Show)
tool/         builders, previews, smoke tests, backup_secrets.sh
test/         mirrors lib/
docs/         UX spec, plan, roadmap, setup, Glance, HA, privacy, signing, QA, launch kit
skills/       portable agent skills (glyph-animation: draw a sprite and open a PR)
fastlane/     store listing metadata and per-versionCode changelogs
.github/      CI, release, catalog and announce workflows, issue forms
```

## Architecture rules

- **Engine stays pure Dart** (`lib/engine`, most of `lib/wled`): no Flutter
  imports, so it runs in isolates and `dart run` tools.
- **One playback owner.** `PlaybackController` owns the generator, the stream
  and alerts; screens ask it, they don't open their own DDP senders. Alerts
  draw over playback temporarily (`beginAlert`/`endAlert`) without replacing
  the user's look. Interactive tools, Send and setup call `blockAlerts`.
- **Device state lives on the device.** Settings that should survive the app
  (layout, Wi-Fi, LED count, time, presets) are written to WLED itself, not
  kept as an app-side overlay.
- **Every device write must be safe to fail.** Check first, change second,
  verify after; a failure leaves the device as it was. Snapshot before
  multi-step changes (see `SetupSnapshot`) and offer Undo.
- Stale async work must not act: capture a generation/revision before an
  `await` and bail if it changed (the pattern used across `DeviceStore`,
  playback, alerts and setup).

## Design system: Lightbox

Full spec: `docs/design/UX.md`. Code: `lib/ui/design/`. **UI uses the design
kit only.** No stock Material look, no gradients, no coloured card
backgrounds. Material widgets are fine when themed by `lib/ui/theme.dart` or
the studio styles in `lib/ui/make/studio_kit.dart`.

**Concept:** a dark room with a light source: matte warm-black surfaces,
1 px hairlines like an instrument panel, type printed on hardware, colour
only from the LEDs.

**Tokens (`Lb`):**

| Token | Use |
|---|---|
| `ink` #0B0A09 | app background, under the ambient glow |
| `panel` #131210 / `raised` #1B1917 | panels and sheets / controls, chips, knobs |
| `line` #2B2723 | hairlines and borders (`Lb.hairline`, 1 px) |
| `text` / `text2` / `text3` | primary / secondary / labels |
| `ledOff`, `bezel` | unlit dots, the panel's own black |
| `phosphor` #FFB547 | fallback accent when nothing plays |
| `danger`, `ok` | destructive actions, connected/success dots |

- **Accent** for active controls is the live ambient colour
  (`AmbientScope` / `readAccent`), falling back to `phosphor`.
- **Shape:** `rControl`/`rPanel` 2, `rSheet` 3, `rTile` 1. Crisp rectangles;
  only LED dots, status dots and rotary knobs are round. Depth comes from
  hairlines and lighter surfaces, not shadows; the only glow is LED bloom and
  the ambient backdrop.
- **Type (`LbType`):** Bricolage Grotesque for `display`, `title`, `heading`,
  `body`, `bodyStrong`, `small`; DM Mono for `label` (uppercase, tracked,
  `text3`) and `mono`. LED headings and big numbers use `LedText`.
- **Motion:** `Lb.fast` 180 ms, `Lb.medium` 260 ms, `Lb.slow` 420 ms,
  `Lb.ease` (easeOutCubic). Respect `Lb.reduceMotion`: decorative loops hold
  still, meaningful moves still run.
- **Sizes:** primary button `Lb.cta` 52, touch target ≥ `Lb.touch` 48, gutter
  20, status dot 6, big hardware keys `Lb.keyLarge` 76. A switched-off device
  dims to `Lb.opacityDeviceOff`.
- **Haptics:** `selectionClick` on channel change and knob detents,
  `lightImpact` on Send, `mediumImpact` on Surprise landing.
- **Parts:** `Stage` (live mirror, bloom, bezel, swipe), `AmbientBackdrop`,
  `LedText`, `Knob`, `LbToggle`/`LbToggleTile`, `Dock`, `MonoLabel`,
  `PanelSection`, `LbPanel`, `StatusDot`, `LedSpinner`, `LivePreview`,
  `LedMatrixView`. Studio screens: `StudioScaffold`, `StudioGroup`,
  `StudioKnob`, `StudioSegments`, `studioToast`/`studioFail`/`studioNoDevice`.
  Guided flows: `StepLayout`, `SetupPrimary`, `SetupSecondary`, `SetupLink`,
  `BusyBody`, `StepStatusRow` in `lib/ui/setup/setup_parts.dart`.

**Screen patterns:**

- **Stage first.** Show the result on the LED preview, then the controls.
  Changes stream live; no Apply buttons.
- **One primary action that names the next step** ("Allow notification
  access", "Turn on alerts", "Try again"), at most one secondary, and a text
  link for escapes. Disabled buttons say why ("Pick an app below first").
- **Guided flows are one question per screen:** a `title`, one plain `line`,
  big answers. Ask about what the user can see on the device ("Which corner
  lit up?") instead of about settings.
- **Empty states invite** ("Add your first card"), **errors say what to do**
  ("Check it's on and on the same Wi-Fi"), **busy states say what's
  happening** (`BusyBody`). Never a dead end; offer Undo after big changes.
- Bottom sheets for actions and choices; snack-bar toasts for results, with an
  action when useful ("Play it"). Lay out for phone widths first; nothing
  scrolls sideways.

## Words (user-facing copy)

Voice: short, warm, second person, verbs for labels. "Look up." "Sent to your
device." "Can't see it?"

| Say | Never in primary UI |
|---|---|
| Display / Make / Device (the tabs) | Tune, Matrix (old names) |
| device, display | matrix, controller, ESP32 |
| **Send** (to device) | Keep, Save to matrix, upload |
| **Saved** (looks on the device) | preset |
| **Shows** (play one after another) | playlist |
| **Routines** (sentences: "Weekdays at 7:00 → Sunrise") | schedule, timer, cron |
| **Rotations** (Glance cycles; never "Shows") | |
| look, animation | effect id, segment, DDP, realtime, FS, LED map |

Advanced details may live behind "Details". Dates are friendly, never ISO.

## WLED facts (verified against WLED 16.0.1 source or hardware)

**Playback and Send**

- **GIF frame waits carry over between files** (`image_loader.cpp` never
  resets `currentFrameDelay`). Device GIFs cap every frame at 1 s
  (`deviceMaxFrameCs`); never add long holds.
- Streamed (DDP) frames skip WLED's gamma when `if.live.no-gc` is true: the
  app applies device gamma/white balance itself (`lib/engine/led_gamma.dart`).
  GIFs are left to WLED's gamma (no double correction).
- Frames sent to a switched-off device light it up. Check `on` (and that
  nothing else is `live`) before streaming uninvited, as alerts do.
- Upload first, switch after: `saveGifToDevice` verifies the file before
  leaving live mode; a failed send must leave the device untouched.
- Re-sending an animation reuses its preset (no duplicates). The boot intro
  (`glyph-intro.gif`, "Glyph intro", "Power-on") is system-owned: hidden and
  undeletable in the app.
- A playing GIF can be deleted only after switching the segment away from it.

**Setup and config** (details: `docs/DEVICE_SETUP.md`)

- `POST /settings/2D` (form: `SOMP`, `MPC`, `P{i}B/R/V/S/X/Y/W/H`; `S` means
  serpentine by its presence) applies the panel layout at runtime and
  recreates segments, so **restore playback afterwards** (`restorePlayback`).
  JSON `hw.led.matrix` needs a reboot instead. `WLED_MAX_PANELS` is 18; the
  LED limit varies by chip.
- `hw.led.ins` entries are rebuilt from defaults: post the full entry.
- `if.live.rlm: false` bypasses the LED map for realtime (used by the wiring
  test). `info.maps` always lists id 0; find custom maps from the file list.
- Wi-Fi: write `nw.ins[0].ssid/psk` (with `bssid "000000000000"`) via
  `/json/cfg`, then `{"rb":true}`. The `/settings/wifi` form resets the AP name
  and TX power; don't use it.
- While the phone is on WLED-AP, WLED doesn't look for home Wi-Fi. A
  configured device that can't connect flaps its AP (~6 s up every ~20 s).
- GET `/json/cfg` is never PIN-protected; detect a settings PIN with a no-op
  write that returns 401.
- Internet time (`if.ntp`) needs a reconnect or reboot to start: write it with
  the Wi-Fi credentials before the reboot, and push the phone clock via state
  `time` so routines work immediately.

**Android networking**

- Joining WLED-AP uses `WifiNetworkSpecifier` + `bindProcessToNetwork`; Android
  routes away from networks without internet unless the process is bound.
- API 29–32 need `ACCESS_FINE_LOCATION`; 33+ need `NEARBY_WIFI_DEVICES`.
- Platform channel replies must be on the main thread.

## Real-device etiquette

- Snapshot `/json/state`, `/presets.json` and `/cfg.json` first; restore them
  afterwards; delete any test files/presets you create; never touch the
  user's own presets or files. Confirm with a zero diff against the snapshot.
- Say so before flashing test streams on someone's display.
- Never factory-reset the maintainer's devices. Simulate a fresh device by
  pointing its Wi-Fi at a missing network, then restore it.
- Device IPs belong to the maintainer's network: ask, or discover them; don't
  hardcode them in code, tests or docs.

## Testing

- Widget tests: pump fixed durations, **never `pumpAndSettle`** (previews
  tick forever); pause playback at the end of a test.
- Device behaviour is tested against fakes (`test/features/device/fake_wled.dart`,
  `http` `MockClient`); the live-device test only runs with `GLYPH_LIVE_HOST`.
- New behaviour gets a test next to its neighbours; bug fixes get a test
  that fails without the fix.
- Run `flutter analyze` and the relevant tests before calling work done.

## Privacy and security

Glyph has no account, ads, analytics, tracking or Glyph server
(`docs/PRIVACY.md`). The only network calls besides the user's own devices
are Open-Meteo (weather, air quality), GitHub Pages (the signed catalog, only
when checked) and links the user taps. Don't add another service, SDK or
telemetry without updating `docs/PRIVACY.md` and asking the maintainer.
Notification alerts send only the app's logo to the device, never message
content. Report vulnerabilities per `SECURITY.md`.

## Content and licensing

- Glyph's code is MIT-licensed (`LICENSE`). New content must be original or
  public-domain/CC0 and credited where required; no trademarked characters, no
  code copied from WLED (EUPL) or other copyleft sources.
- Exception: the imported animation collection (`catalog_assets/pipplee/`)
  was added by the maintainer with its creator's permission. It isn't MIT and may show third-party characters.
  Don't treat it as precedent for other imports or for contributions. Never
  name its source in user-facing copy (app, store, website, release notes).
- `CONTRIBUTING.md` is the guide for contributors (sprite format, art
  licensing, PR checklist); keep it in sync when the sprite format or commands
  change.
- For any task that adds or changes a pixel-art animation (sprite), follow the
  `glyph-animation` skill in `skills/glyph-animation/SKILL.md`; validate with
  `python3 skills/glyph-animation/scripts/validate_sprite.py --all`. Keep the
  skill's `reference.md` and validator in sync with `sprite.dart`,
  `palette.dart` and `build_catalog.dart`.
- The remote catalog is Ed25519-signed and published by the `catalog`
  workflow, which needs the maintainer's approval (`docs/CATALOG_DELIVERY.md`).

## Git and releases

- Work on `main` unless told otherwise; commit only when asked. Commit from
  the main checkout; don't leave work only in an agent worktree.
- Commit messages: imperative summary line, a body explaining why.
- Releases: bump `version:` in `pubspec.yaml` (`X.Y.Z+N`), add
  `fastlane/metadata/android/en-US/changelogs/<N>.txt` (≤500 chars) and an
  identical `changelogs/<2000+N>.txt`, and a `lib/app/whats_new.dart` entry.
  Push to `main`, wait for CI (`ci.yml`, analyze + test) to pass on that
  commit, then push a `vX.Y.Z` tag. `.github/workflows/release.yml` builds the
  signed arm64 APK and its `.sha256` and publishes the GitHub release; don't
  commit APKs to `release/`.
- If the release workflow fails before a GitHub release exists, fix it on
  `main` and move the tag (`git tag -f vX.Y.Z && git push -f origin vX.Y.Z`).
  Once a release is published, never move its tag; bump the patch instead.
- After publishing, download the APK, check its `.sha256` and run the three
  `apksigner` checks in [docs/SIGNING.md](docs/SIGNING.md#verifying-a-release):
  API 28+ must show `d9f51a1f…`, API 24–27 `8f7a1d18…`, and the lineage both.
- Signing: every release is signed with the old key, the new key and the
  lineage; never fall back to old-key-only. Don't change the signing steps,
  keys or secrets unless the maintainer asks. Keys, rotation and backups:
  [docs/SIGNING.md](docs/SIGNING.md).

## Where to look

| Topic | Doc |
|---|---|
| Screens, journeys, visual language | `docs/design/UX.md` |
| Setup wizard, panel grids, WLED setup internals | `docs/DEVICE_SETUP.md` |
| Glance cards and Rotations | `docs/GLANCE.md` |
| Community drawings and moderation | `docs/COMMUNITY.md` |
| Notification alerts | `docs/NOTIFICATIONS.md` |
| Home Assistant blueprints | `docs/HOME_ASSISTANT.md` |
| Catalog signing and delivery | `docs/CATALOG_DELIVERY.md`, `docs/CATALOG_ART.md` |
| Signing keys and releases | `docs/SIGNING.md` |
| iOS test plan | `docs/QA_IOS.md` |
| Launch kit, F-Droid | `docs/launch/` |
