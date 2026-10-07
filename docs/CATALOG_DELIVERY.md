# Animation catalog delivery

Implemented in the unreleased checkout. GitHub Pages and optional daily
checks were confirmed on 7 October 2026. The site is **not deployed yet**;
`RemoteCatalog.defaultUrl` remains null. No APK version bump or release is
part of this work.

## In the app

Glyph menu → New animations offers a manual check and a daily-check toggle
(off by default). Checks contact the named static host, without device IDs,
notification content, analytics, accounts or custom request headers.
Downloaded looks are cached on the phone and available offline.

Daily means at most one automatic attempt per 24 hours, persisted across
restarts, including unsuccessful attempts. Checks run while Glyph is open
or on resume when due; there is no background service, wakeup or notification.
Turning the option on permits the first check immediately when due. Manual
checks also satisfy that day's cadence; manual retries remain available.

Bundled content paints first. Startup then validates the source-bound cache
without contacting the host. A single app-owned CatalogStore installs the
staged sprites and rebuilds AppScope. Rails, open category pages, search and
Glance pickers update; selected channel, favourite/recent IDs, current
playback, its parameters/palette/speed and live stream remain intact.
Retired IDs disappear from surf orders; an already playing generator keeps
its own decoded drawing. Send transfers a decoded sprite into the GIF
worker so downloaded art works in that isolate too.

## Artifact and publication

`version: 1` is the document schema. `revision` is a positive integer content
revision, independent of the app version and item `added` revisions. Its
source is `assets/catalog/content_revision.json` (currently 3). A published
revision is immutable; bump it for new or changed content. Identical
workflow reruns are allowed.

The builder combines the generated catalog with all reviewed sprite packs,
including their source/attribution and item notices. It fails on rejected
entries. No external GIF/assets are supported yet; clients skip unsupported
entries with reasons. New drawings need new sprite IDs. An existing item ID
cannot be reassigned to a different generator; changed art needs new item
IDs too. Bundled drawings cannot be replaced by a download.

```sh
python3 skills/glyph-animation/scripts/validate_sprite.py --all
dart run tool/build_sprites.dart
dart run tool/build_catalog.dart
dart run tool/build_remote_catalog.dart
```

Output lives in `build/catalog-site/`, never in the app's docs folder:

- `catalog-v1.json`: current artifact.
- `previous.json`: exact previously published artifact after a content change.
- `revisions/<revision>.json`: current and previous versioned files.
- `index.html`: small catalog landing page.

`.github/workflows/catalog.yml` validates sprites and generated assets,
runs engine/library/tool tests, downloads the currently hosted artifacts,
and builds the site. A host failure other than initial 404 blocks publishing
so it cannot silently discard a previous artifact. Actions retains a copy
for 90 days; Pages deploys only from main. A content push or manual `publish`
run publishes the reviewed content. No APK needs rebuilding for later
compatible additions.

For rollback, manually run Animation catalog with mode **rollback** from a
validated main checkout. The builder validates both hosted artifacts and
swaps them: previous becomes current, and current becomes previous. It
keeps their original revision numbers and exact bytes. Clients accept the
lower revision on their next manual/daily check; favourites referring to
retired entries are retained for later restoration. A failed deployment
leaves the existing Pages site unchanged. A second rollback restores the
other artifact. For older recovery, restore a retained Actions artifact
through the same validation/deployment process; the site guarantees the
immediately previous artifact, not an indefinite history.

Local rollback preparation (without publishing):

```sh
dart run tool/build_remote_catalog.dart \
  --current build/catalog-current.json --previous build/catalog-previous.json \
  --rollback --output build/catalog-rollback
```

## Production activation

1. Commit/push the reviewed changes when authorised. In repository Settings
   → Pages, select **GitHub Actions** as the build source.
2. Run Animation catalog → publish on main. Verify the deployment and fetch
   `https://spandan-kumar.github.io/glyph/catalog-v1.json`; check schema,
   content revision and the client validation tests against that artifact.
3. Only then set `RemoteCatalog.defaultUrl` to that verified HTTPS endpoint,
   update the disabled-default test, and include activation in an app release.

Before activation, a test build can opt into a verified staging/Pages URL:

```sh
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=GLYPH_CATALOG_URL=https://spandan-kumar.github.io/glyph/catalog-v1.json
```

Ordinary builds stay offline until the endpoint is configured. The override
is a build setting, not a user-facing arbitrary URL field.

## Bounds and verification

Download: 2 MiB, eight-second total header/body deadline, no redirects;
timeouts abort the request and cancel body consumption. Validation and sprite expansion run in a
Dart isolate. The same byte cap applies to cache/artifact reads, with only a
small allowance for the cache's source binding. Writes use a flushed temp
file and atomic rename; failed checks/writes keep the prior cache and
registry. Disposal suppresses late adoption and closes the client.

Schema bounds: 2,000 items, 32 packs, 512 sprites, 8,192 frames overall,
64 frames per sprite, 256 sequence steps, 2 Mi decoded pixels overall.
Rows are at most 256×64 and 8,192 pixels per frame; parts, colors, patches,
metadata and nesting are bounded before sprite expansion. Frame duration
uses the existing 20–10,000 ms format; device GIF encoding still caps each
wait at one second. Reject empty sequences, non-finite values, incompatible
motion/color syntax before adoption. A conflicting drawing or reused item
identity rejects the whole update, retaining the previous cache across
restarts. Duplicate sprite IDs are excluded with reasons. Skip unknown
generators, palettes and unsupported assets with reasons. Retain notices
and source fields, including nullable historic years.

Tests cover staging without registry mutation, malformed tails, byte/count/
expansion bounds, body timeout cancellation, durable-write failure, offline
restart, HTTP/redirect failure, source binding, collisions, attribution,
daily opt-in/cadence/failure/resume/disposal, UI refresh with active playback,
remote Send pixel correctness, immutable revisions and artifact rollback.
The complete 1,209-look initial artifact validates under the bounds.

Local verification on 7 October 2026: `flutter analyze` reports no issues;
1,114 Flutter tests pass (one live-device test skipped), four native Android
unit tests pass, and the arm64 debug APK builds. The settings screen was
rendered with the app fonts and visually checked. The sprite validator
reports zero errors and 383 warnings from the existing packs. YAML parsing and
Bash syntax checks pass for the workflow; GitHub execution is pending.

Partial Pixel 8/WLED checks now cover downloads from a local fixture server,
validation, offline cache reload, rendering and streaming; see
[device QA](DEVICE_QA_2026_10_07.md) for results and pending Send checks/cleanup.
Before public activation, execute the workflow on GitHub and verify the live
HTTPS artifact. Those publication paths remain unverified.
