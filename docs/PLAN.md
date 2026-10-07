# Glyph — engineering plan

Reconciled on 7 October 2026 against `main` at `75656c4`, v1.3.1+6.
Release follow-up: v1.3.2+7 contains the bug bundle below; v1.4 adds features.
[ROADMAP.md](ROADMAP.md) owns product priorities and launch plans; this file
owns implementation order, dependencies and acceptance criteria. Dates are
targets, not reasons to ship unfinished behaviour.

[ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md) records verified ordering
failures and the boundaries required by this plan. Use its acceptance
criteria alongside the feature checks below.

Glyph is a free, open-source (MIT), Android-first app for WLED displays.
The phone renders; a device either receives live frames or plays content
sent to it. No account, subscription or Glyph backend. Optional internet
features must name their providers and explain what they send.

## Current baseline

| Area | Shipped in v1.3.1 |
|---|---|
| Display | Lightbox Stage, channels, search, favourites/recents, palette and motion controls, streaming, Send |
| Library | 1,209 curated looks, 62 procedural generators, 329 sprites, 22 categories; Halloween and Diwali packs |
| Make | Pixel editor/live drawing, Write/Clock/Timer, GIF/WebP/photo import, GIF and `.glyph` sharing/import |
| Live tools | Nine mic visualisers, Now Playing album art/progress, seven games |
| Device | Discovery/manual address, capabilities, Saved, Shows, Routines, storage, boot intro, orientation fix, switching/mirroring, Android widget |
| Community/release | MIT licence, contributor guide/agent skill, diagnostics, Glyph menu, What's new, issue forms, CI, signed APK/checksum workflow, Discord announcements, Dependabot |

Baseline verification: analysis reports no issues; 1,009 tests pass, with
the live-device test skipped without `GLYPH_LIVE_HOST`. This does not verify
physical panels or Android background lifecycle behaviour.

Partial foundations, not shipped features:

- `RemoteCatalog` validates, caches and merges data, but `defaultUrl` is
  null and `main()` loads only the bundled catalog.
- `NowPlayingListener` provides media-session access; it has no notification
  event handlers. Permission is granted only by the person.
- Shows are WLED playlists of Saved items, with no live data refresh or
  phone-owned sequences.
- The orientation fix transforms Glyph frames; it does not configure panel
  wiring, tiling or WLED's 2D configuration.
- iOS scaffolding exists; an iOS product release remains future work.

## Principles and playback paths

- Keep rendering in pure Dart. Network, Android bridges, persistence and
  lifecycle control sit outside `lib/engine`.
- Detect device capabilities. Preserve working streaming and upload paths.
- Use the design kit and Display / Make / Device, Send / Saved / Shows /
  Routines vocabulary. Explain phone requirements in the UI.
- Keep original or public-domain/CC0 art and its source/attribution notes;
  remote delivery follows the same contribution rules.

| Path | Implementation | Phone needed |
|---|---|---|
| Stream | Render → corrected frames → DDP group | Yes |
| Send | Bake GIF → verified upload → Image effect → Saved look | No after sending; GIF-capable WLED required |
| Native | Device effects, clocks, Saved, Shows and Routines | No after configuration |

## v1.3.2: one bug and polish bundle

The confirmed release scope is v1.3.2+7: all five known polish issues plus
the current correctness fixes A1–A3. No new Glance features are included.
The tag-triggered Release workflow builds the arm64 APK and checksum,
publishes the changelog and runs the existing Discord announcement.

Include the audit's current bug classes in this same bundle: guard late
device/Send results (A1), preserve playback when replacement uploads fail
(A2), and serialize boot/Saved writes so unrelated presets survive (A3).
These additional findings have no GitHub issue IDs yet. Remote blockers
A5–A6 are gates before activating that dormant feature.

A1–A3 have fixes and automated regression coverage in v1.3.2 (7 October):
selection/session guards, staged replacement uploads, and a shared
host queue with preset-write settling. Controller QA was not performed:
no Android phone/controller was attached during release preparation.
Replacement needs temporary extra space;
unknown-owner old files remain in Storage. Post-commit network failures and
concurrent external writers remain limitations documented in the audit.

| Issue | Change | Acceptance |
|---|---|---|
| [#20](https://github.com/spandan-kumar/glyph/issues/20) | Send from the collapsed Stage | Same availability, busy state and result as the full control; reachable while browsing; unsupported/live-only looks handled correctly |
| [#21](https://github.com/spandan-kumar/glyph/issues/21) | Restrained sharing invitations | Persist the invitation policy; ordinary sends get plain confirmation; unchanged re-sends never prompt |
| [#22](https://github.com/spandan-kumar/glyph/issues/22) | Sharing opens Discord | Menu, post-send, creation and What's new agree; file/GIF sharing and developer-facing GitHub links remain available |
| [#23](https://github.com/spandan-kumar/glyph/issues/23) | Hide the system intro from Routines | Hide only the system power-on row; preserve user power-on choices, useful empty state and boot installation |
| [#24](https://github.com/spandan-kumar/glyph/issues/24) | Recognise unchanged content already on device | Offer Play it without upload/beam; changed settings, size or content still sends; reuse existing presets |

#20–#24 are included in v1.3.2 (7 October):

- The collapsed Stage uses the same Send control and status as the full
  Stage; disconnected, unsupported and live-only looks hide the compact key.
- Sharing opens Discord throughout the app. The automatic invitation is
  persisted: first fresh Send, then at least ten additional Sends and seven
  days between invitations. Unchanged re-sends do not count or prompt.
- Routines hides the built-in intro. A user's power-on look stays editable
  and still runs after the intro; intro-only devices offer “Choose a power-on
  look” beside the empty state.
- Send compares exact encoded GIF bytes against the Saved entry's device
  file before uploading. Identical content offers “Play it” without a beam,
  upload, storage requirement or playback interruption. Changed content,
  dimensions, palette, parameters or speed still sends and reuses the Saved
  ID. Sending a tweaked clip now preserves its playback speed in GIF timing.

The matching check reads the device file over Wi-Fi; it adds no stored
fingerprint that could become stale after an external edit. The larger live
playback refactor remains separate. Documentation corrections are bundled
in this release.

Combined verification after these fixes: `flutter analyze` reports no issues;
`flutter test` passes 1,036 tests, with one live-device test skipped. The suite
includes generated-data checks. This verifies the release source; physical
controller/Android QA remains unverified.

## v1.4: playback foundation before more feeds

Proposed minimum: playback ownership/restoration,
notifications, weather and days-until cards. Setup wizard and Home Assistant
blueprint are independent work and ship when their checks pass. Planes,
crypto, air quality and more cards follow a working end-to-end information
flow. This scope is provisional pending the release decision below.

### 1. Playback ownership and temporary alerts

Add a small app-level coordinator around `PlaybackController`,
`GlyphActions`, `DeviceStore` and `BackgroundStreaming`. Keep the renderer
and DDP sender focused on their jobs; do not build a generic display
framework yet. It owns the user's current session and a temporary alert,
with a session generation and target host for every interruption.

- Suspend a live session without discarding instance/time, palette, params
  or speed. Keep feed ownership alive: Now Playing's follower currently
  detaches when another generator takes over, so swapping generators alone
  would break restoration. Resume the same session after the alert.
- Capture recoverable device playback before alert streaming. Prefer Saved/
  Show identity, otherwise restore the relevant native state. Do not create
  a preset just for restoration. Define/test whether a device Show resumes
  its position or restarts; do not promise exact position without support.
- A new user action supersedes restoration. Power off, Stop, device switch
  and disconnect cancel alerts/queues; stale callbacks cannot power on a
  device or restore to a different host.
- Suppress alerts during drawing, games, guided setup and Send. Discard
  stale events rather than replaying them afterwards. Default to the
  selected device; mirrored devices need explicit alert inclusion.
- Release timers/subscriptions and background ownership when stopped.
  Reuse the existing foreground service/Stop action; enable it while the
  app is visible, with no silent boot auto-start.
- Give an enabled alert monitor its own background ownership, including
  while WLED plays a native look and no stream is open. The current
  `BackgroundStreaming.watch` stops the service when streaming stops;
  update that policy to account for monitoring and live Shows. Keep idle
  monitoring free of frame traffic. Stop ends monitoring as well as live
  playback; do not resurrect a terminated Dart session from an alert.

Acceptance: fake-clock tests cover live/native/Show restoration, feed
continuity, bursts, manual takeover, power off, switching/disconnect,
Send suppression and cleanup. Physical QA covers each playback path with
state/presets/config restored and test-owned files removed afterwards.

### 2. Notifications

Extend the existing Android listener with posted/removed/connected/
disconnected handling and a separate Dart event feed. Now Playing remains
usable without enabling alerts. Wait for listener connection before using
listener operations, following Android's lifecycle contract.

- Add Notifications under Make: opt-in, choose apps, preview, toggle and
  quiet hours. Explain the change from media-session access to processing
  selected alerts. Default message visibility awaits the decision below.
- Filter allowed packages before extracting text. Ignore Glyph's own
  notifications, media controls, ongoing service/status notifications and
  group summaries. Updates replace the same queued notification; removal
  cancels a queued alert. Do not replay history when enabling.
- Keep bounded payloads/queues in memory only: no text in diagnostics,
  files, network requests or catalog. Proposed UX limits: one scroll with
  an 8-second cap, three queued alerts, 30-second expiry; validate on panels.
- Live-only: no Send. Handle denied/revoked access and inactive sessions
  visibly; never claim delivery after the OS stops Glyph. Provide a
  synthetic test alert without needing another app to send a message.

Acceptance: native filtering/update/removal/lifecycle tests; Dart/widget
consent, per-app settings, midnight-spanning quiet hours, expiry and
restoration tests. Android QA includes screen off, locked phone, permission
revocation and process termination, alongside existing Now Playing.

### 3. Glance cards and phone-owned Shows

Separate persisted card configuration from timestamped feed snapshots.
Services fetch outside the render loop; pure Dart generators consume data.
Start with weather and days-until/since, reusing text/layout helpers and
checking 8×8, 32×8, 16×16 and 32×32.

- Glance under Make configures/previews a card and shows it live. Start with
  a manually chosen place/coordinates, local timezone/units, no prerequisite
  for continuous GPS or a location permission.
- Weather: request needed current/daily Open-Meteo fields only. Proposed
  cadence: every 15 minutes while used, sharing requests across previews/
  Shows and backing off on failure. Cache the last good result with its
  timestamp/stale indicator. Proposed 2-hour expiry: show unavailable and
  skip in a Show rather than inventing zeros. Validate thresholds in QA.
- Days-until/since uses a local date/timezone and updates at midnight, with
  defined reached/past-date states. A baked GIF is not a live counter.
- Persist phone-owned Show definitions separately: entries for library
  looks, creations and cards, duration/order. Existing WLED Shows remain
  device-owned. Use Shows with clear Runs on your device / Needs your phone
  labels; never silently convert one into the other.
- Reject initially unsupported mixes such as device presets whose visuals
  Glyph cannot render. Support skip-on-unavailable, a bounded fallback when
  every item is unavailable, and alert interruption/resume.
- Live cards/Shows use Show on device and a visible background toggle, not
  Send. Stop/network loss/process termination must let WLED return to its
  own playback. Do not promise guaranteed Android background availability.

Acceptance: mocked feeds cover timezones/midnight, missing fields,
freshness, offline cache, errors and shared refresh. Fake-clock Show tests
cover order/duration, skips, all-unavailable fallback and alert resumption.
No feed polls per frame; counters require no network.

### 4. Remote catalog: finish the dormant path

Separate delivery track, not a Glance prerequisite. Proposed first version:
a static catalog on GitHub Pages and an explicit Check for new animations
action. Hosting and optional automatic checks remain decisions for later;
no accounts, upload service or per-user endpoints are needed.

- Build a remote JSON artifact from reviewed packs, including sprite data
  and attribution/notices. Separate content revision from schema version.
  Publish after sprite/catalog validation; retain a previous artifact for
  rollback. Do not repurpose the app docs folder as the publishing output.
- Add an app-level catalog store: bundled data at first paint, validated
  cache overlay, background refresh that rebuilds `AppScope`/rails/search.
  Wire startup/disposal; setting `defaultUrl` alone is insufficient.
  Preserve favourites/recents, channel selection and active playback.
- Bound download/decode size, sprite/frame counts and timeouts. Validate
  before accepting data or mutating the runtime sprite registry. Keep the
  last good cache on failure and replace atomically. Preserve `notice` and
  supported attribution fields through validation.
- Preserve protection against replacing bundled drawings. Use new IDs for
  changed remote art initially so new metadata cannot resolve to a stale
  registered drawing. Skip incompatible generators/assets with reasons.
- Keep offline content. Explain that checks contact the static host; add
  no device IDs, notifications or analytics.

Acceptance: offline first launch/cache restart, HTTP failure, malformed/
oversized data, incompatible entries, attribution, ID collisions, UI
refresh, favourite retention and artifact rollback. Change the test that
asserts `defaultUrl` is null only when delivery is actually enabled.

### 5. Delivery order and release gates

1. Land the bug bundle and documentation reconciliation.
2. Prove alert interruption/restoration using synthetic input across live
   and device-owned playback, preserving background/Now Playing behaviour.
3. Wire notifications and verify Android lifecycle on hardware.
4. Deliver weather/counters end to end, then phone-owned Shows. Standalone
   cards remain usable if mixed Shows need more time.
5. Run remote catalog delivery independently; hosting cannot block fixes
   or unrelated cards.
6. Release after scoped features pass analysis, relevant/full tests,
   generated-data checks, physical QA and clear phone/internet disclosures.
   Add versionCode changelog/release notes then; festivals do not waive gates.

Planes/crypto/air quality need provider, coverage and usage checks before
scope is promised. The panel wizard needs config snapshot, live wiring
patterns, verified write/reconnect and an accessible restore path. The HA
blueprint uses existing Saved IDs and can ship independently. Before AWTRIX,
extract only the adapter boundary needed by WLED and that second device.

## Product decisions awaiting answers

Confirmed on 7 October: ship the bug bundle separately as v1.3.2, then start
v1.4 with playback ownership/restoration. The user authorised the release.

1. Can live cards/alerts require the Android phone on the same network with
   Glyph running in the background? Autonomous live data needs a different
   architecture, to be planned before promising it.
2. Notification default: app icon/name with per-app text opt-in, or icon
   plus short message text after enabling that app?

Other proposals to resolve before implementation: catalog hosting/automatic
checks and provider refresh limits. Existing user power-on choices continue
after the system intro; #23 only changes how that is presented.
Record answers here and keep the product roadmap consistent.

## External implementation references

- [Android notification listener](https://developer.android.com/reference/android/service/notification/NotificationListenerService): callbacks and connection lifecycle.
- [Open-Meteo forecast API](https://open-meteo.com/en/docs): current/daily data and timezone fields.
- [Open-Meteo terms](https://open-meteo.com/en/terms): provider limits and attribution must be reflected in this optional external feature.
- [GitHub Pages publishing](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site): static artifact delivery through Actions.

## Dev device

WLED 16.0.1, ESP32 (4 MB flash, ~880 KB free FS), 16×16 serpentine,
`if.live.rlm = true` (realtime respects the 2D map), Image effect present.
Previously measured signal was weak (−91 dBm); include weak-network QA.
Snapshot state, presets and config before tests, restore afterwards, and
remove only test-owned files/presets.
