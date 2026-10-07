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

- Catalog delivery is implemented in this unreleased checkout: bounded
  staging/cache, reactive app integration and a Pages workflow.
  `defaultUrl` points at the Pages site, but the client stays off until the
  maintainer replaces the placeholder signing key (docs/CATALOG_DELIVERY.md).
- `NowPlayingListener` now also supplies opt-in logo notifications in this
  unreleased checkout. Permission is granted only by the person; physical
  Android/WLED QA remains.
- Device Shows run autonomously from Saved items. Glance adds separate
  phone-owned Shows in this unreleased checkout; physical QA remains.
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

Implementation status (7 October, unreleased): notification overlays and
monitor ownership are implemented. The live base generator/instance/feed
continue underneath; only the selected host receives the alert frame.
Native playback is left intact while realtime input is used, then live mode
and any prior realtime override are restored. No preset or Show is rewritten;
exact Show position is left to WLED, not promised. This is the first temporary
alert path, not the phone-owned Show coordinator needed by Glance below.
Automated coverage is in `test/features/notifications` and Android bridge
filter tests. Physical screen-off/locked-phone/WLED QA remains a release gate.


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
  monitoring free of frame traffic. The foreground notification's Stop
  ends monitoring as well as live playback; do not resurrect a terminated Dart session from an alert.

Acceptance: fake-clock tests cover live/native/Show restoration, feed
continuity, bursts, manual takeover, power off, switching/disconnect,
Send suppression and cleanup. Physical QA covers each playback path with
state/presets/config restored and test-owned files removed afterwards.

### 2. Notifications

Implemented in this checkout, not yet released: Make entry, searchable app
picker with installed icons, local app/quiet-hour preferences, explicit
session start, synthetic logo preview, four-second bounce, bounded/coalesced
queue, native filtering and guarded live/native restoration. Now Playing
continues independently. See [notification implementation and QA](NOTIFICATIONS.md).


Extend the existing Android listener with posted/removed/connected/
disconnected handling and a separate Dart event feed. Now Playing remains
usable without enabling alerts. Wait for listener connection before using
listener operations, following Android's lifecycle contract.

Confirmed product scope (7 October): logo-only alerts, with no message text
or app-name text on the display. Use the originating app's installed icon,
fitted for the device, in a short bounce/pulse animation, then restore the
previous playback. A roughly 4-second alert is the initial tuning target;
validate legibility and motion on small and wide panels.

- Add Notifications under Make: opt-in, a searchable app picker with each
  app's icon/name and an independent enabled switch, preview, master toggle
  and quiet hours. Persist the selected packages locally. Start with no apps
  selected. App names appear in settings, not on the display.
- Reuse the existing Android notification-access permission and foreground
  service; granting access for Now Playing does not enable alerts. The phone
  stays on the same network with Glyph running in the background. No silent
  boot auto-start or historical notification replay.
- Filter selected packages natively before obtaining icon/event payloads.
  Do not extract notification title, body, sender, conversation, images or
  other message contents. Ignore Glyph itself, media controls, ongoing
  service/status notifications and group summaries. Coalesce repeated
  updates to the same notification; removal cancels a queued alert.
- Use installed app icons rather than notification attachments. Keep icon
  pixels and bounded event/queue data in memory only; no notification
  contents in diagnostics, storage, network requests or the catalog. If an
  icon cannot be loaded, use a neutral Glyph alert symbol, with no text.
  Start with at most three queued alerts and a 30-second expiry; discard
  stale alerts and suppress them during protected interactive sessions.
- Live-only: no Send. Handle denied/revoked access and inactive sessions
  visibly; never claim delivery after the OS stops Glyph. Provide a
  synthetic preview using a selected app's icon without needing another app
  to send a notification.

Acceptance: native filtering/update/removal/lifecycle tests; Dart/widget
consent, persisted app selection, icon conversion/animation, midnight-spanning
quiet hours, expiry and restoration tests. Android QA includes screen off, locked phone, permission
revocation and process termination, alongside existing Now Playing.

### 3. Glance cards and phone-owned Shows

Implemented in this unreleased checkout; physical Android/WLED QA remains
before release. See [implementation and QA notes](GLANCE.md). Counters follow
the phone timezone only, per the product decision on 7 October 2026.

Separate persisted card configuration from timestamped feed snapshots.
Services fetch outside the render loop; pure Dart generators consume data.
Start with weather and days-until/since, reusing text/layout helpers and
checking 8×8, 32×8, 16×16 and 32×32.

- Glance under Make configures/previews a card and shows it live. Start with
  a manually chosen place/coordinates, local timezone/units, no prerequisite
  for continuous GPS or a location permission.
- Weather: request needed current/daily Open-Meteo fields only. Cadence: every 15 minutes while used, sharing requests across previews/
  Shows and backing off on failure. Cache the last good result with its
  timestamp/stale indicator. 2-hour expiry: show unavailable and
  skip in a Show rather than inventing zeros. Validate thresholds in QA.
- Days-until/since uses a civil date in the phone timezone and updates at midnight, with
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

Separate delivery track, not a Glance prerequisite. Confirmed: a static
catalog on GitHub Pages, an explicit Check for new animations action, and
optional daily automatic checks (off by default). Checks run only while the
app is open, including on resume when due. No accounts, upload service or
per-user endpoints. Implemented in this unreleased checkout; publishing and
production activation remain pending. See [delivery and QA](CATALOG_DELIVERY.md).

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

## Product decisions

Confirmed on 7 October: ship the bug bundle separately as v1.3.2, then start
v1.4 with playback ownership/restoration. The user authorised the release.

Confirmed on 7 October: phone-present background streaming is acceptable,
using the same model as Now Playing. Notifications show only a briefly
animated app logo, with no message text. The person chooses enabled apps
inside Glyph; notification access alone does not enable the feature.

Confirmed on 7 October: GitHub Pages catalog hosting, manual checks and
optional daily automatic checks. Automatic checks start off. Days counters
follow the phone timezone only.

Other proposals to resolve before implementation: remaining provider refresh
limits. Existing user power-on choices continue
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
