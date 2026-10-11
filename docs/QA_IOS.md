# Glyph iOS QA — executable test plan

Prepared 11 October 2026. **This is a plan, not a completed QA record.** Run it
against the exact candidate checkout and a physical WLED **16.0.1** controller.
Record the commit, uncommitted changes, app version/build, signing identity,
phone/OS and controller identity before starting. Android QA is not iOS evidence.

Scope: the complete Flutter product, iOS integration and safe controller
recovery. The setup wizard, forecast/air quality and Home Assistant sheet are
built but not yet released in the documented baseline. Multi-panel grids are
being built; their cases below are acceptance requirements for the candidate,
not claims that they already work. Recheck implementation at execution time.

Use this file with [AGENTS.md](../AGENTS.md), [README](../README.md),
[engineering plan](PLAN.md), [roadmap](ROADMAP.md), [device setup](DEVICE_SETUP.md),
[Glance](GLANCE.md), [Alerts](NOTIFICATIONS.md), [Home Assistant](HOME_ASSISTANT.md)
and [Lightbox UX](design/UX.md). The results/evidence format follows
[v1.3.6 QA](QA_1_3_6.md). All instructions needed to run the cases are included
here; those documents explain the underlying contracts.

## Execution and evidence rules

- Run build/platform gates first, then onboarding, setup, Display/Send, Make,
  live information, Device, catalog, lifecycle and accessibility. Finish cleanup
  even when a case fails. Stop hardware writes if recovery or identity is uncertain.
- In each table mark **one** Pass or Fail box. Leave both blank for unrun,
  blocked or not applicable cases and record the reason in the results template.
  Pass means every listed expectation was observed. A supported feature with a
  broken iOS fallback is a failure, not an Android-only exemption.
- Run rows with variants once per variant; record each outcome. Unavailable
  hardware, fixtures, older iOS build or unimplemented grids must be **Blocked**.
  Simulator-only coverage never passes a physical-device requirement.
- Save evidence by ID: screenshot/video, visible LED observation, sanitized
  app/Xcode log, HTTP read-back, GIF metadata/hash, timing and recovery result.
  Record phone preview and physical LEDs separately. HTTP success or a toast
  alone does not prove correct playback, wiring or restoration.
- Prefix all test-owned content `QA-IOS-<run>-…`; keep a ledger of created
  creations, cards, Rotations, Saved IDs/files, Shows, Routines, HA automations
  and every setting changed. Never reuse an owner's name or ID deliberately.
- Expected product words: **Display / Make / Device**, **Send**, **Saved**,
  **Shows**, **Routines**, **Rotations**. Technical names belong in advanced
  details/firmware pages, not primary Glyph UI.

## Prerequisites and build

| Requirement | Preparation / acceptance |
|---|---|
| Mac and Xcode | Use **Xcode 27 stable** for the current iOS generation, or a stable Xcode version supporting the actual test phone's OS. Match macOS to Apple's [Xcode requirements](https://developer.apple.com/xcode/system-requirements). Record `xcodebuild -version` and `xcode-select -p`; do not use the project's `compatibilityVersion = Xcode 9.3` as a tooling requirement. Older supported OS testing may need an older compatible Xcode. |
| Flutter | Project baseline Flutter 3.47+, Dart **3.13.5+** (`pubspec.yaml`). Record `flutter --version`, `flutter doctor -v`, `git rev-parse HEAD` and `git status --short`. Resolve tooling/signing blockers before physical QA. |
| Native dependencies | At authoring time **no `ios/Podfile`, entitlement file or app-specific capabilities are checked in**. Flutter 3.44+ defaults to Swift Package Manager and can fall back to CocoaPods for plugins; missing Podfile alone does not prove a failure. Have current CocoaPods available if fallback is required; capture actual dependency/build errors. Follow [Flutter native dependency guidance](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers). Do not silently add native configuration during a QA run. |
| Signing/install | Open `ios/Runner.xcworkspace`, choose Runner → Signing & Capabilities, select the approved development Team/profile and a unique permitted bundle ID if the team cannot sign `dev.spandankumar.glyph`. Record any override; do not commit it. Connect/unlock/trust the iPhone, enable Developer Mode where required, and trust the development certificate. A personal team can be used for local testing subject to its capability limits. See [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup). |
| OS/device matrix | Project deployment target is **iOS 15.0**. Minimum physical run: one current iPhone with notch/Dynamic Island. Also test a small iPhone, an iOS 15 device if supported by available tooling, and iPad portrait/landscape for popovers/safe areas. Record missing devices as coverage limits; do not raise the deployment target to hide plugin incompatibility. |
| Controller/network | WLED 16.0.1 ESP32 with Image/GIF support, known single digital-output panel (16×16 baseline), stable safe supply and known wiring. Phone and Mac on the same non-isolated LAN; allow local HTTP and UDP **4048**, mDNS `_wled._tcp`. Keep controller IP/MAC/AP credentials/PIN privately available. Use a spare for Wi-Fi provisioning, PIN changes, failure injection, layout migration and storage pressure. |
| Additional hardware | A real rectangular panel (32×8 or equivalent), 8×8 and 32×32 if available; two or four equal panels on one controller for grid QA, including one mounted upside down. A second independent WLED device is needed for switch/mirror checks. A panel grid is not a group of separate controllers. Never claim size readability from resized phone previews. |
| Optional services | Internet for signed catalog/Open-Meteo; a test Home Assistant 2024.10+ instance with WLED integration for end-to-end HA cases. Core browsing/rendering/counters/device control must work without internet. No GPS permission is needed for Glance place search. |
| Permissions/settings | `Info.plist` currently includes `NSLocalNetworkUsageDescription`, `NSBonjourServices` with **`_wled._tcp`**, and `NSMicrophoneUsageDescription`. It has no `UIBackgroundModes` or ATS exceptions. Verify the **built** plist as well as source. Check microphone plugin permission configuration if permission cannot be requested. Do not add broad ATS exceptions or background modes just to make QA pass. |
| Privacy/evidence | Store controller snapshots and credentials in a private directory outside the repo; exclude them from shared logs/screenshots. Record Wi-Fi/AP names only in private evidence where needed. Ask the display's owner to expect dim test patterns before any live stream; agree a safe brightness cap, e.g. 10–20%, within existing limits. |

Build/run commands (run in a disposable checkout or retain a before/after status
because Flutter may generate native integration files; this plan does not
authorize source fixes, commits or release publishing):

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter --version
flutter doctor -v
xcodebuild -version
xcode-select -p
flutter pub get
flutter analyze                    # required: No issues found!
flutter test                       # record counts/skips, do not assume old totals
flutter devices                    # copy the physical iPhone device ID
open ios/Runner.xcworkspace         # configure local signing if needed
flutter build ios --release         # signed device build; not an install command
flutter run --release -d <iphone-device-id>
```

Use `flutter run -d <iphone-device-id>` for diagnostic debug runs. Run final
lifecycle, timing and performance cases in **release with debugger detached**;
an attached debugger can change suspension behavior. If signing is blocked,
`flutter build ios --release --no-codesign` checks compilation only and cannot
satisfy device installation. For layout-only checks:

```bash
flutter build ios --simulator --debug
flutter run -d <simulator-device-id>
```

| Surface | What it establishes / limits |
|---|---|
| Simulator | Browsing, local creations, layout, keyboard, semantics and some HTTP rendering checks. LAN/mDNS/UDP behavior uses the Mac environment and is not physical iPhone evidence. Local-network privacy is not supported in the simulator; microphone routing and haptics differ. |
| Physical iPhone | Required for Local Network allow/deny/revoke, discovery, UDP/DDP, AP-to-home Wi-Fi handoff, microphone/session interruptions, haptics, suspension, lock and real LED validation. |
| Network distinction | Local-network access and multicast entitlement are separate. DDP unicast does not itself require multicast entitlement; Bonjour plugin behavior/raw multicast must be tested on the signed build. No checked-in multicast entitlement exists. See [Apple local-network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). |

## Known iOS gaps to verify first

These are code findings at authoring time, not permission to report iOS support
for Android features. Re-run the searches below on the candidate. AppDelegate
currently registers Flutter plugins only; SceneDelegate has no custom bridge.

```bash
rg -n 'Platform\.isAndroid|Platform\.isIOS|TargetPlatform.android|MethodChannel|EventChannel' lib ios android
rg -n 'NowPlaying|NotificationAlerts|glyph/power|glyph/setup_wifi|glyph/platform|UIBackgroundModes|NSAppTransportSecurity|entitlements' lib ios android
rg --files ios
```

| Gap / source | Expected iOS UI and execution rule |
|---|---|
| Background streaming — `lib/app/background.dart`, `glyph/power`, Android foreground service | `BackgroundStreaming.supported` is false on iOS. Background switches/Android notification Stop instructions should be absent or clearly unavailable. Foreground Music/DDP can work; Home/lock cannot be advertised as persistent playback. Test graceful stop/timeout and resource release, not Android service survival. Ordinary **Keep screen on** is separate and should still work while foregrounded. |
| Assisted Wi-Fi — `features/device/setup/setup_wifi.dart`, `glyph/setup_wifi`, `glyph/platform` | `Platform.isAndroid` guards probe/bind; iOS must show **guided Wi-Fi settings**. No assisted join/system network request or Android nearby/location permission. Current `openSettings` invokes an unimplemented channel and catches failure: manual Settings → Wi-Fi must remain executable, and a button that promises to open Wi-Fi but silently does nothing is a UX defect to record. |
| Now Playing — `features/now_playing/now_playing_service.dart`, `glyph/now_playing`, `glyph/now_playing/events`; Android `NowPlayingBridge` | Show **Android only for now** and explain other apps' media cannot be read. No notification-access prompt or claim to follow Spotify on iOS. Current screen still has demo/style/Show controls: verify demos are honest and unsupported live actions cannot falsely claim an album cover is showing. |
| Alerts — `features/notifications/notification_service.dart`, `glyph/notifications`, `glyph/notifications/events`; Android notification bridges | iOS cannot access other apps' notifications. Status **Android only**, disabled **Android only for now** CTA; no monitoring, installed-app picker results, permission route or real logo delivery. Decorative bell is a demo. Quiet-hour controls, if visible, must not imply monitoring is active. |
| Widget — `features/device/home_widget_bridge.dart` | Guarded by `Platform.isAndroid`; no WidgetKit extension/App Group is present. Do not instruct iPhone users to add the Android widget. Record an iOS widget as unavailable, not tested. |
| Time/diagnostics — `features/device/device_time.dart`, `app/community.dart`, `glyph/platform` | Native phone/IANA-timezone bridge is Android-only. **Set the time** must work using the iPhone's current UTC offset, preserve already-enabled owner NTP settings and disclose/record DST limitation for a newly configured zone. Missing phone-model diagnostics must degrade safely without a plugin error. |
| Permissions/WebView/accessibility | Plist has local-network/mic strings but no ATS exception, background mode or Podfile permission macros. Local WLED HTTP/WKWebView, microphone grants and plugin linkage are gates. No explicit `disableAnimations`/`accessibleNavigation` handling was found in the skim: Reduced Motion is an acceptance test, not an assumed implementation. |

## Controller safety, snapshots and recovery

**Never factory reset the maintainer's display, flash firmware, change GPIO/type,
raise an existing power limit or delete the owner's files/presets.** New-device
tests use a spare with functioning AP fallback. For a shared working display,
limit the run to reversible content/control tests with a recovery path.

1. Announce the dim patterns/streams. Record original power/brightness, selected
   Saved/Show, layout/app transforms, mirrors, sync settings, time/NTP, PIN state,
   LED output fields and AP fallback settings. Freeze other writers during QA;
   if the owner changes something, preserve that newer choice and reconcile
   with them rather than replaying the old snapshot.
2. Snapshot **all three required resources before any Glyph connection that
   could install an intro**, plus live config/info and file inventory. Inspect
   HTTP errors and parse the JSON. Example on the Mac (replace host):

   ```bash
   export GLYPH_QA_HOST='192.168.1.123'
   export GLYPH_QA_DIR="$(mktemp -d /tmp/glyph-ios-qa.XXXXXX)"
   chmod 700 "$GLYPH_QA_DIR"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/json/state" -o "$GLYPH_QA_DIR/state.before.json"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/presets.json" -o "$GLYPH_QA_DIR/presets.before.json"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/cfg.json" -o "$GLYPH_QA_DIR/cfg.before.json"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/json/cfg" -o "$GLYPH_QA_DIR/config-live.before.json"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/json/info" -o "$GLYPH_QA_DIR/info.before.json"
   curl --fail --max-time 15 "http://$GLYPH_QA_HOST/edit?list=/" -o "$GLYPH_QA_DIR/files.before.json"
   ```

   A missing `presets.json` on a spare is a recorded initial absence, not an
   empty snapshot substituted for a failed read. Retain private copies of
   pre-existing GIFs that any authorized replacement could affect. Poll saved
   files until settled; `/json/cfg` reflects live config before `/cfg.json` does.
3. Choose a safe native baseline that does not delete/change existing Saved
   entries. Record realtime timeout and whether `if.live.rlm` and
   `if.live.no-gc` are enabled. Setup tests temporarily disable realtime mapping
   to address physical LEDs and must restore it on **every** exit.
4. Restore setup using **Restore previous setup / Undo display setup** first;
   read back layout, count, limiter, realtime map and app transforms. For manual
   recovery, restore only changed fields with `POST /json/cfg`; layout uses
   `POST /settings/2D` with complete original panel entries (`SOMP`, `MPC`,
   `P0B/R/V/S/X/Y/W/H`, repeated for each panel). Output-array writes require
   complete preserved output entries. A JSON matrix patch alone cannot undo
   2D mode at runtime. Do **not** upload `cfg.json` blindly: it can reboot and
   passwords may be masked. Keep recovery pending if unreachable.
5. Stop all phone streams; exit live mode (`POST /json/state` with `{"live":false}`)
   before restoring native playback. Switch the active segment away from a
   test GIF before deletion. Remove only ledger-owned presets/files; Glyph
   Saved deletion/Storage is preferred. API fallback: delete test Saved ID via
   `POST /json/state` with `{"pdel":<test-id>}`, and its unreferenced file with
   `GET /edit?func=delete&path=%2F<test-file>`; verify disappearance.
6. Restore test-changed preset bodies from `presets.before.json` only if needed
   and safe; with exclusive access an exact saved `presets.json` can be restored
   through WLED's file editor/upload and polled until parsed content matches.
   Never overwrite intervening owner changes. Preserve a pre-existing system
   intro. If Glyph installed system files/presets during this run, explicitly
   reconcile those additions against the baseline on the spare; the app's
   normal UI intentionally hides/protects them.
7. Restore config **before** state, allow reconnection, verify MAC, restore
   original native Saved/Show or the relevant writable state fields (power,
   brightness, segment bounds/effect/name/colors, night light, realtime override).
   Do not POST the entire state response with read-only fields. Preset/file
   inventories and config must match baseline except agreed changes; compare
   parsed JSON, allowing documented volatile timestamps/runtime fields and
   preset-file padding. Check the physical panel and original off/on state.

### Simulate a new device without resetting it

On a **spare only**, record original `nw.ins[0]` SSID/BSSID and AP settings,
confirm AP fallback is enabled and know its password. Configuration reads can
mask passwords: do not assume a snapshot contains a reusable Wi-Fi password.
To force AP fallback while retaining the stored password, patch **only the
first network's SSID**, omitting `psk` (and all unrelated keys):

```bash
curl --fail --max-time 15 -H 'Content-Type: application/json' \
  --data '{"nw":{"ins":[{"ssid":"QA-IOS-MISSING-NETWORK"}]}}' \
  "http://$GLYPH_QA_HOST/json/cfg"
curl --max-time 15 -H 'Content-Type: application/json' \
  --data '{"rb":true}' "http://$GLYPH_QA_HOST/json/state"
```

Confirm no nearby AP has that name. A reboot can drop its response; verify the
AP actually appears rather than assuming failure/success from curl. Join it
manually on iPhone (usually `WLED-AP`, default password `wled1234`, often
`4.3.2.1`; use this spare's actual values). Keep the local network even when
iOS reports no internet. Run the guided wizard, entering the known correct
home credentials when provisioning. For recovery without the wizard, connect
Mac/phone to the AP and POST the same minimal payload containing the **original
SSID** to `http://4.3.2.1/json/cfg`, still omitting `psk`, then reboot and
reconnect on the home LAN. If a wrong-password test overwrote `psk`, restoring
SSID alone is insufficient: re-enter the privately known original password
through the guided form. Restore changed BSSID/AP/NTP fields separately and
verify the original MAC, home connection and baseline config. Do not print
passwords in commands, diagnostics or evidence.

## Test data and observation helpers

Use Draw to make an asymmetric arrow/letter with red/green/blue corners, save
as `QA-IOS-…-DRAW`, export GIF and `.glyph` to **Files → On My iPhone**, then
make a second distinct look. Retain these until Shows/Rotations/HA tests finish.
Use Write message `QA IOS — THE LAST LETTER IS Z` and a longer repeated version
for full-scroll testing. Use a photo you own and long card/device titles.

For repeatable import fixtures on the Mac, create them outside the repo and
transfer to the test phone's Files (AirDrop/USB/cloud folder). This script needs
Pillow in a temporary virtual environment; it creates no source changes:

```bash
python3 -m venv "$GLYPH_QA_DIR/venv"
"$GLYPH_QA_DIR/venv/bin/pip" install Pillow
"$GLYPH_QA_DIR/venv/bin/python" - "$GLYPH_QA_DIR" <<'PY'
from pathlib import Path
from PIL import Image, ImageDraw
import json, sys
p = Path(sys.argv[1])
im = Image.new('RGB', (32, 16), 'black')
d = ImageDraw.Draw(im)
d.polygon([(16, 1), (11, 7), (14, 7), (14, 13), (18, 13), (18, 7), (21, 7)], fill='white')
for xy, color in [((0, 0, 2, 2), 'red'), ((29, 0, 31, 2), 'green'), ((0, 13, 2, 15), 'blue')]:
    d.rectangle(xy, fill=color)
im.save(p / 'QA-IOS-arrow.png')
frames = [Image.new('RGB', (16, 16), c) for c in ('red', 'green', 'blue')]
frames[0].save(p / 'QA-IOS-timing.gif', save_all=True, append_images=frames[1:], duration=[80, 1000, 120], loop=0)
frames[0].save(p / 'QA-IOS-animation.webp', save_all=True, append_images=frames[1:], duration=[80, 1000, 120], loop=0)
many = [Image.new('RGB', (16, 16), ((i * 17) % 256, (i * 37) % 256, (i * 71) % 256)) for i in range(100)]
many[0].save(p / 'QA-IOS-100.gif', save_all=True, append_images=many[1:], duration=100, loop=0)
(p / 'QA-IOS-broken.gif').write_bytes(b'GIF89a-broken')
(p / 'QA-IOS-newer.glyph').write_text(json.dumps({'format': 'glyph', 'version': 999, 'creation': {}}))
PY
```

For each uploaded GIF, find its path from the new Saved body/file inventory,
download it with `curl --fail "http://$GLYPH_QA_HOST/<file>" -o <private-path>`
and inspect `Image.open(path).n_frames`, size and the sum/max of each frame's
`duration` using that Python environment. Compare hashes with `shasum -a 256`.
Device GIF frame waits must each be **≤1,000 ms**; full sequences must not be
shortened for weak Wi-Fi/storage. Stream gamma/white balance is applied by the
phone where WLED skips gamma; GIFs use WLED gamma. Check actual blacks/hues at
safe brightness rather than requiring the phone screen to match LED luminance.

Failure injection: turn **phone Wi-Fi** off for reachability loss; disable only
the test router's **WAN** for offline feeds while keeping local device access.
For write interruption switch the phone to another Wi-Fi during the indicated
operation on a spare, then reconnect and verify. Do not disconnect the owner's
router. Storage pressure uses only counted test files on a spare, leaving room
for recovery/config saves. PIN/custom map/output changes use WLED settings on
the spare and are logged/restored. No case requires a factory reset.

## 1. Build, platform and onboarding

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 001 Build/install gate | Tooling/signing prepared | 1. Run build commands above. 2. Install release on phone. 3. Cold launch, then kill/relaunch. 4. Inspect built plist and signed capabilities in Xcode/build artifact. | Analysis/tests/build results recorded; app launches with correct icon/name/version; all plugins link; no uncaught MissingPluginException. Plist contains local-network/Bonjour/mic declarations; actual capabilities recorded. | SwiftPM/Pod fallback, iOS 15 compatibility, signing/profile capability mismatch, scene startup. | ☐ | ☐ |
| 002 Android gaps | Installed build; controller snapshots complete | 1. Open Music, Now Playing, Alerts, Glance and Device. 2. Exercise unsupported controls once. 3. Compare with gaps table. | Honest Android-only messages; no Android permissions/services/widget instructions; no false streaming status. Record currently exposed misleading actions as failures. | Missing native channels may be caught yet leave misleading UI. | ☐ | ☐ |
| 003 Clean offline onboarding | Fresh **test** install, no LAN/internet; never erase owner's app data | 1. Launch. 2. Inspect splash/welcome. 3. Choose Just looking around. 4. Browse all tabs. 5. Restart. | Browse works offline; Display/Make available; Device has clear connection action; no onboarding loop or mandatory account; completion remembered. | Splash/scene transition, safe areas and first-run persistence. | ☐ | ☐ |
| 004 Local Network denied/allowed | Fresh permission state on test phone | 1. Find my device. 2. Deny Local Network. 3. Retry and enter known IP. 4. Enable Glyph in Settings → Privacy & Security → Local Network (path may vary by OS). 5. Return/retry. | Denial produces reachable help/retry, not endless search or crash; granting recovers discovery/control without reinstall; no writes to guessed hosts. Record missing permission-specific help. | Prompt may reject first request before answer; physical phone required. | ☐ | ☐ |
| 005 Discovery/manual address | Permission allowed; known IP/MAC; controller reachable | 1. Search 6–10 s. 2. Select found device. 3. Repeat using numeric IP and advertised `.local` name. 4. Try invalid address, non-WLED host and offline IP. | Correct identity/capabilities; useful failure/retry/manual route; no duplicates; HTTP reachability and mDNS results recorded separately. | Bonjour resolution vs subnet scan, VPN/client isolation; successful manual IP does not pass mDNS. | ☐ | ☐ |
| 006 Hello/orientation/first vibe | New app record of test device | 1. Connect and watch phone/panel hello. 2. Choose Something looks off. 3. Test arrow directions/mirror correction. 4. Looks right; select Calm/Party/Classic where offered. 5. Restart. | Intro/preview coherent; visual approval explicit; working orientation and selected look persist; onboarding does not return. Wizard/legacy entry differences recorded. | No native Back button: visible Back/Close and interactive dismissal must work. | ☐ | ☐ |
| 007 Add/cancel/retry | Already onboarded; spare device available | 1. Device → Your devices → Add a device. 2. Cancel search. 3. Re-enter and connect spare. 4. Cancel naming/vibe. | Existing device/data retained; no phantom selection or late search takeover; naming/vibe skippable; onboarding not globally reset. | Route edge-swipe cancellation and stale callbacks. | ☐ | ☐ |

## 2. Setup wizard — guided Wi-Fi and identity

All provisioning/PIN/failure cases below require the spare and the recovery
procedure above. Keep mobile data on for one guided run; repeat with it off.

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 008 Connect choices | Spare reachable on home LAN | 1. Enter setup from Add device, then existing-device Set up display. 2. Choose Yes, it's on my Wi-Fi. 3. Back and choose No, it's new. | Correct discovery vs guided join; prerequisite says WLED installed/hardware connected; no flashing or reset required. | Guided route must not call Android permission/assisted UI. | ☐ | ☐ |
| 009 New-device AP join | Spare forced to missing SSID; AP fallback verified | 1. Choose new. 2. Follow Settings → Wi-Fi steps manually. 3. Stay connected despite no internet. 4. Return to Glyph. 5. Tap Open Wi-Fi settings separately and record behavior. | Guided instructions give correct AP/password and advance after reaching verified WLED; no assisted join promised. Manual fallback remains usable if settings button cannot launch. Silent inert button recorded as defect. | No assisted Wi-Fi join implemented; Settings handoff and cellular routing. | ☐ | ☐ |
| 010 Renamed/protected AP | Spare AP customized and logged | 1. Expand Renamed its network? 2. Enter actual SSID/password. 3. Join in Settings and return. 4. Cancel/retry once. | Correct guided details; obscured home credentials; no reset/default-name assumption; retry retains useful draft only. | Keyboard/password autofill, app suspension while Settings open. | ☐ | ☐ |
| 011 Network scan/manual SSID | Phone on spare AP; known home 2.4 GHz network | 1. Open Home Wi-Fi list; retry scan while still running. 2. Select network. 3. Try manual hidden SSID entry. 4. Inspect duplicated-name results if available. | WLED scan handles asynchronous loading/deduplication; manual entry works; 2.4 GHz guidance and empty/5 GHz-only help; no iPhone scanning/GPS request. | iOS cannot supply Android scan assumptions. Duplicate/hidden-network subcase blocked if unavailable. | ☐ | ☐ |
| 012 Successful home handoff | Correct home credentials; mobile data enabled | 1. Submit credentials. 2. Observe restart. 3. Manually return iPhone to home Wi-Fi. 4. Wait bounded reconnect (up to 75 s), retry/manual IP if needed. 5. Read `/json/info`. | Success only after home-LAN discovery and matching MAC; AP HTTP acknowledgement alone is insufficient; changed IP handled; password not persisted/logged in app. | Phone may stay on no-internet AP or auto-join another SSID; release debugger must be detached. | ☐ | ☐ |
| 013 Wrong password/recovery | Spare; original password known privately | 1. Provision a deliberately wrong home password. 2. Follow failure help to rejoin AP. 3. Retry correct credentials. 4. Restore baseline Wi-Fi/config. | Failure actionable; AP return recognized; no false success/endless spinner; no unrelated AP/TX-power settings reset; recovery verified by MAC. | Settings switching during callbacks; SSID-only restore cannot fix overwritten password. | ☐ | ☐ |
| 014 Identity/timeout guard | Two test controllers or controllable spare IP change | 1. Make saved IP point to other device, or enter other device's IP during retry. 2. Also retry with unreachable IP. 3. Restore correct address. | Wrong MAC rejected for provisioning verification; bounded waits/cancel; no writes or cleanup to other host; eventually correct device recovers. | Cached Bonjour/IP and late responses. Missing second controller is Blocked. | ☐ | ☐ |
| 015 PIN detection/unlock | Spare with recorded known settings PIN | 1. Start setup. 2. Try wrong PIN, blank PIN, correct PIN. 3. Cancel locked route once. 4. Re-lock/retest after unlock timeout/restart. | Readable config does not bypass write lock; wrong PIN error; correct PIN verified by write probe; no hardware mutation while locked; PIN not logged. | Secure keyboard/focus and lifecycle on return from firmware settings. | ☐ | ☐ |

## 3. Setup wizard — size, wiring, grids, apply and undo

The published setup documents describe the single-panel baseline. Active,
uncommitted grid work appeared in this workspace during authoring, including
`lib/wled/panel_grid.dart`, `lib/ui/setup/grid_diagram.dart` and
`lib/ui/setup/order_screens.dart`. The inspected model describes **equal panels
in a regular rectangular grid**, with a corner/across-or-down/straight-or-snaking
chain and per-panel upside-down correction; it rejects arbitrary panel order,
mixed sizes, gaps and overlaps. For **022–026**, record the exact candidate's
implementation status first. If absent, mark Blocked; still run unsupported
configuration preservation in 021. Do not replace physical checks with previews.

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 016 Working-device fast path | Correct existing 2D spare, Saved GIF and nonidentity app transform recorded | 1. Set up display. 2. Run Look check and finish without edits. 3. Compare config/presets/files/transforms. | No gratuitous layout/count writes; existing transform not silently cleared; original playback restored; migration only after visual verification. | Stream and GIF must both be tested independently after setup. | ☐ | ☐ |
| 017 Size/count validation | Known single digital output | 1. Select matching preset size. 2. Try custom across/down extremes and a count mismatch. 3. Return to correct dimensions; Back/Next. | Draft retained; LED count change explicit in review; bounded dimensions; invalid/unsupported size blocked; no guessed GPIO/type/color-order change. | Small screen/stepper hold/release and Dynamic Type. | ☐ | ☐ |
| 018 Three-tap physical wiring | Dim sparse test; actual wiring documented | 1. Identify lit LED 0 corner. 2. Identify first run direction. 3. Identify next run start. 4. Confirm diagram; use manual correction once. 5. Cancel and repeat. | Corner, rows/columns and straight/zig-zag match physical LEDs; `if.live.rlm` disabled only for raw test and restored on cancel/finish; no double app transform. | Tap diagrams need VoiceOver names; interrupted test cannot leave map disabled. | ☐ | ☐ |
| 019 Wiring variants | Spare conventional panel; alternate wiring fixtures available | 1. Repeat 018 for four corners × rows/columns × straight/zig-zag, using real configurations/hardware where possible. 2. Include rectangular layout. | Physical corner/run and result match each variant; missing physical combinations explicitly blocked with automated coverage separate. | Do not relabel app-local rotation as physical wiring evidence. | ☐ | ☐ |
| 020 Optional power review | Spare with safe existing limiter and known supply rating | 1. Skip power step. 2. Repeat with valid amps, blank/invalid/zero input. 3. Inspect proposed/current limits and apply safe value. | Skip preserves limit; proposal is 85% of rating rounded down to 50 mA, retaining any stricter existing limit; no extra controller subtraction; validation and units clear. | Numeric/decimal keyboard, locale decimal separator; never raise owner's safe limit. | ☐ | ☐ |
| 021 Unsupported layouts | Spare with recorded multi-output/custom map/HUB75 or unsupported firmware fixture | 1. Enter setup. 2. Inspect fallback. 3. Cancel; use orientation/settings route where offered. 4. Diff config. 5. Include mixed-size/gapped/overlapping/custom-order panels if grid support exists. | No conversion/truncation of unsupported wiring; no GPIO guesses; existing config preserved; fallback available. Unsupported grids remain intact; regular supported grids are not rejected merely for having multiple panels. | Availability must use actual device capabilities; fixture-only runs are not physical passes. | ☐ | ☐ |
| 022 One-or-several choice | Candidate grid feature; real two-panel grid | 1. Enter setup for one panel. 2. Choose several. 3. Set per-panel size and row/column counts. 4. Back to one and forward again. | Explicit one/several choice; total width/height/LED count and diagram agree; single route stays simple; draft/back predictable; not device mirroring. | Choice/grid diagram accessible; controls fit narrow phone. | ☐ | ☐ |
| 023 Panel order test | Two or four panels, known physical chain order | 1. Answer Which panel lit up?, Which panel is next?, Where did it jump to? using actual lit panels. 2. Verify corner, across/down and straight/snaking diagram. 3. Try Test again/manual order. 4. Repeat 1×N, N×1 and 2×2 layouts; reverse start corner. | First/next/second-run start correspond to physical chain; redundant questions skipped for one row/column; supported non-row-major chain correct; arbitrary chain not silently accepted. If LEDs cannot light because count is too low, Nothing lit up/help and explicit Set LEDs now must be safe, logged and reversible on cancel. | Named row/column choices and manual alternatives; raw tests bypass existing map safely. | ☐ | ☐ |
| 024 Upside-down panels | Grid with a later panel mounted 180° from first; first panel is wiring reference | 1. Complete order and first-panel three-tap wiring. 2. On Are any panels upside down?, select only inverted panel. 3. Inspect LED-0/corner preview and show arrow/letter across seam after apply. 4. Toggle back then correct; re-enter setup. | First panel remains reference; selected panels get opposite start corner while rows/columns/zig-zag stay correct; choices prefill on return; unaffected panels/seams correct; stream and saved GIF match. A globally inverted display is corrected without double rotation. | Portrait/landscape UI must not alter physical orientation selection; diagram has panel labels/selected states. | ☐ | ☐ |
| 025 Grid review/read-back | Correct grid draft, existing test Saved/Show/Routine | 1. Review arrangement/count/output fields and power guidance. 2. Apply. 3. Read complete WLED panel array and segment bounds. 4. Stream/send cross-seam fixture. | Complete panel entries/offsets/order/orientations persist; total bounds/count correct; unrelated output fields/presets/files preserved; no clipping. Review shows supply-per-panel guidance and slower one-wire update warning above 1,024 LEDs; no need to illuminate full white to check it. | Larger bake may hit preparation/storage budget; explicit error required. | ☐ | ☐ |
| 026 Grid invalid/recovery | Spare; grid feature present | 1. In draft/review only, try one-panel Several, more than 18 panels, more than 16,384 LEDs or whole side over 255; inspect clamped controls/errors. 2. Test unsupported mixed/gapped/custom-order config separately. 3. Interrupt a valid apply by switching phone Wi-Fi. 4. Reconnect; Restore/Undo, including any early Set LEDs now write. | Single-panel route offered; model limits guard Next/Apply without hardware writes; invalid grid not silently truncated; partial/uncertain apply shown honestly; recovery restores original single/grid/plain-strip config and app transforms, not just preview. | Suspended callbacks and changed dimensions; missing injection opportunity recorded. | ☐ | ☐ |
| 027 Review/apply/read-back | Valid single-panel correction | 1. Inspect review. 2. Back/edit/return. 3. Apply once. 4. Read live config, persisted cfg after settling, `/json/state`. | Only intended layout/map/count/limiter fields change; layout applied via 2D form; complete output entry preserves pin/type/order/reverse/skip; bounds refreshed; presets/files intact. | Network drop after write is uncertain, not automatic success; no full-config replay. | ☐ | ☐ |
| 028 Look/finish/Send parity | Applied setup; physical observer | 1. Inspect sequential corners, up-arrow, asymmetric letter, row/column motion and RGB. 2. Something is wrong → correct/restore. 3. Looks right/Done. 4. Stream then Send arrow/drawing and close phone. | Both paths agree in orientation/colors; approval gates completion; full app rotation/mirrors/serpentine migration verified; exiting setup does not implicitly create user Saved. | Rectangular 90° transforms need explicit bounds handling; existing app path only supports square rotations. | ☐ | ☐ |
| 029 Cancel/background every phase | Spare; snapshots; repeatable setup draft | 1. Cancel at Join, Home Wi-Fi, PIN, Size, each wiring tap, Review, Applying and Look where offered. 2. Repeat with Home/lock 30 s at wiring/apply. 3. Return. | Draft navigation sane; temporary tests pause in background; test map/playback restored on exit; after writes explicit keep/revert or pending recovery; no lingering retries/mic/streams. | Settings handoff must remain usable while setup pattern streaming pauses. | ☐ | ☐ |
| 030 Interrupted apply/rollback | Spare valid draft; home Wi-Fi available | 1. During Apply switch phone Wi-Fi away. 2. Reconnect. 3. Inspect result and read-back. 4. Restore previous setup. | Failure/uncertain-write distinguished; reads verify before retrying writes; failed apply rolls back, or exposes recovery-pending if unreachable; older callbacks do not claim Done. | HTTP response lost after successful write; suspension. | ☐ | ☐ |
| 031 Durable undo/process restart | Applied changed setup, including strip→2D on spare | 1. Kill app during Look; relaunch. 2. Device → Undo display setup. 3. Verify original fields and original strip mode. 4. Repeat undo while temporarily unreachable. | One MAC-scoped recovery record survives; full original mapping/app layout/map/count/limiter restored; offline restore remains actionable, never falsely says restored. | App process removal vs in-memory cancellation; recovery must survive restart. | ☐ | ☐ |
| 032 Setup ownership/external change | Second test device/mirror; Music or Rotation used previously | 1. Enter setup on selected device. 2. Verify mirrors untouched. 3. Change selected device or an unrelated setting from WLED during draft. 4. Cancel/restore. | Competing tool streams stopped deliberately; setup isolated from group/sync; no cleanup sent to new device; external edits not blindly overwritten; unrelated config preserved. | Async host/selection generations, not Android service behavior. | ☐ | ☐ |

## 4. Display, Stage morph, library and Send

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 033 Channels/catalog breadth | Bundled library; online checks off | 1. Browse every channel/category. 2. Play representative procedural, sprite and Famous Classics look; Halloween/Diwali. 3. Scroll offscreen and return. | Baseline around 1,209 looks/22 categories unless candidate catalog differs; titles/credits correct; live previews and active Stage coherent; offscreen previews do not consume needless work. | Release scrolling/frame pacing and phone temperature. | ☐ | ☐ |
| 034 Surf/search/favourites/recents | Connected controller; test look selected | 1. Swipe Stage both directions. 2. Search title/mood/no match; clear. 3. Favourite/unfavourite; replay recent. 4. Restart. | Channel surf order/title/LEDs agree; search instant/recoverable; favourites and recents persist; empty results usable; no unsupported gestures promised. | Horizontal swipe vs scroll/back-edge gesture; keyboard overlap. | ☐ | ☐ |
| 035 Surprise and held tiles | Display active | 1. Roll dice; try shake only if offered. 2. Tap/long-press Stage-deck tiles including held state. 3. Rapidly change selections. | Correct landing/held-play semantics and single selected look; haptic feedback; no stuck shuffle/late playback. Record shake as absent if not implemented rather than inventing behavior. | Motion sensors not evidenced by simulator; distinguish haptics from visual result. | ☐ | ☐ |
| 036 Stage morph/mini-Stage | Tall feed; notch phone; recording enabled | 1. Slowly scroll full Stage to collapsed layout and back. 2. Reverse mid-morph. 3. Switch tabs during collapse. 4. Record Display → Make → Device → Display. | One coherent live Stage, title/transport moves without duplicate/blank/jump/clip; compact controls work; dock label fades through intermediate values; active underline and ambient color settle. | Safe area/120 Hz timing, overscroll bounce, interruptions; Reduced Motion tested separately. | ☐ | ☐ |
| 037 Tweak/palette/knobs | Procedural and sprite variants | 1. Open Tweak. 2. Change palette, speed and every available parameter to min/mid/max. 3. Adjust brightness; close/reopen. | Live phone/panel updates; labels/values accurate; palette/parameters preserved; blacks and low-brightness hues stable; no accidental full-brightness flash. | Rotary drag and VoiceOver adjustment alternatives; haptic detents differ by device. | ☐ | ☐ |
| 038 Stream pause/resume | Native baseline recorded; connected device | 1. Play/stream look 30 s. 2. Pause/resume. 3. Stop live/control power off. 4. Disconnect/reconnect. | State/Stage match device; no UDP to off/other device; native playback returns after exit/timeout; retry usable. | HTTP can succeed while UDP is blocked; observe physical animation and live state. | ☐ | ☐ |
| 039 Full/compact Send | GIF-capable device, free space | 1. Send from full Stage. 2. Send distinct look from collapsed Stage. 3. Inspect Saved/file/read-back; close Glyph for 2 min. | Same busy/status/availability; upload verified before leaving stream; Sent confirmation; correct device GIF persists phone-free; no duplicate system entry exposed. | Bake isolates, iOS memory budget, cellular handoff during upload. | ☐ | ☐ |
| 040 Full-content/gamma Send | Sprite, long Write exact look and slow Ocean procedural | 1. Send all three, including sprite at faster speed. 2. Download/decode GIFs. 3. Watch two loops each. 4. Compare safe dim RGB/black fixture stream vs GIF. | Complete sprite motion and final Z visible; procedural recording ≥30 s; each frame wait ≤1 s; no shortened fallback for RF/storage; no double gamma or long blank between different files. | CPU/memory, device gamma vs phone correction; read-back required. | ☐ | ☐ |
| 041 Unchanged/changed re-Send | 039/040 Saved entries retained | 1. Re-Send identical content while another native look plays. 2. Choose Play it. 3. Change palette/speed and Send again. | Already on your device leaves playback/upload/storage unchanged until Play it; changed content replaces safely and reuses Saved ID; old unreferenced file retired after switch. | Delayed equality read cannot act on later selection. | ☐ | ☐ |
| 042 Send cancellation/failure | Spare; active stream/native baseline; ledger | 1. Start Send then select another look. 2. Repeat with Wi-Fi loss during upload. 3. Retry after reconnect. 4. Diff Saved/files/state. | Busy clears; canceled operation cannot hijack newer look/device; no interrupted Saved entry; failed verified upload leaves previous playback intact; staging debris recoverable/cleaned. | Background suspension mid-bake/upload; final state wins over toast. | ☐ | ☐ |
| 043 Capability/resource limits | Spare low-space controller; oversized test creation or incompatible device | 1. Disconnect and inspect Send. 2. Try live-only tool. 3. Attempt too-large bake/send and storage failure. 4. Return to valid Send. | Unavailable controls hidden/disabled honestly; explicit preparation/storage error before unsafe allocations where applicable; no shorter content or lost previous playback; UI recovers. | iOS jetsam vs graceful budget error; do not fill maintainer filesystem. | ☐ | ☐ |

## 5. Make — Draw, Write, Clock, Timer, import and creations

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 044 Studio/tools | Connected and offline/disconnected variants | 1. Open Make; inspect all tiles/demos. 2. Enter/exit Draw, Write, Clock, Timer, Bring a GIF, Music, Play, Now Playing, Glance, Alerts. | All tools reachable; honest phone/device status; Made by you shown consistently here and on Display; unsent owned tool playback stops on leaving; sent content remains. | Route swipe dismissal and keyboard focus; no Android-only promises. | ☐ | ☐ |
| 045 Draw start/canvas | Test device dimensions; empty creation | 1. Choose Blank/template; device/common/custom sizes. 2. Draw corners and arrow; pinch/zoom/pan. 3. Toggle live mirror. | Canvas bounds correct; first stroke appears promptly on panel by default when connected; mirror off stops live updates; no stray stroke from pan/edge gesture. | Multitouch/gesture arbitration and bottom home indicator. | ☐ | ☐ |
| 046 Drawing tools/colors | 045 drawing | 1. Use pencil, eraser, fill, picker, line, rectangle, move. 2. Mirror X/Y. 3. Pick palette/custom RGB and recent colors. 4. Undo/redo each. | Pixel operations correct and bounded; undo one operation at a time; chosen colors/selected tool evident; no destructive action without clear affordance. | Color-picker labels and drawing semantics; haptic selection. | ☐ | ☐ |
| 047 Frames/animation | Drawing with three distinct frames | 1. Add/duplicate/reorder/delete frame. 2. Onion skin. 3. Set speed endpoints; play/pause. 4. Undo. | Frame order/count/selection valid; onion skin preview-only; loop/timing correct on panel; deleted last-frame behavior safe; reorder works without drag via accessible actions. | Long-press/reorder gesture and VoiceOver custom Move earlier/later actions. | ☐ | ☐ |
| 048 Save/edit/dirty exit | Unsaved drawing | 1. Save/rename. 2. Edit again, undo to saved state. 3. Exit with new unsaved change; exercise discard/cancel/save choices. 4. Restart and reopen. | Creation persists with correct pixels/meta; dirty prompt accurate; cancel retains work; Save never means Send; device untouched by local save. | Dialog keyboard/safe area and interactive dismiss. | ☐ | ☐ |
| 049 Write controls/keyboard | Test message ending Z | 1. Type/paste, edit selection, delete to empty. 2. Use Tiny/Classic/Bold, colors/palette/background, Plain/Outline/Shadow, motion/direction/speed. 3. Preview/show. | Empty send guarded; final letters fully scroll; supported glyphs render, unsupported emoji/non-Latin degrade visibly without crash; controls update live. | Smart punctuation, IME/composition, dictation/paste, keyboard covering CTA. | ☐ | ☐ |
| 050 Write save/send modes | Long message; native text-capable device | 1. Save Exact look locally while editing text during bake. 2. Send Exact look and decode full GIF. 3. Send Device font variant. 4. Leave tool/lock phone. | Save captures intended snapshot and newer edits stay editable/dirty; exact GIF keeps full scroll; native font/color differences explained; both sent variants play phone-free. | Async isolate completion after navigation; native font is not phone preview parity. | ☐ | ☐ |
| 051 Clock/time | Device clock/NTP snapshot; phone correct time | 1. Show clock, change offered face/colors/seconds/date/format. 2. Send. 3. Lock phone 2 min. 4. Compare device time and UTC epoch. | Live preview follows phone; sent clock uses native device font/time settings and keeps time alone; clock-sync error explicit; no baked frozen clock claimed as live. | iPhone supplies offset, not IANA ID; keyboard/date/time formatting and DST limits. | ☐ | ☐ |
| 052 Timer/countdown | Native baseline, no owner schedules modified | 1. Choose target 2 min ahead using date/time picker. 2. Show countdown; pause/stop/restart if offered. 3. Cross zero and inspect labels. 4. Try sending/saving. | Correct target/zero/reached behavior; no negative rollover; live-only countdown cannot be misrepresented as a baked/sent working timer; leaving unsent tool restores device. | App suspension/phone timezone/12-hour locale; date picker sheets. | ☐ | ☐ |
| 053 File/photo acquisition | Fixtures in Files; owned photo available | 1. Open a file: GIF, animated WebP, PNG/photo. 2. Choose a picture using offered system picker. 3. Cancel both. 4. Open cloud-backed file offline. | Correct decode and frame count; original aspect ratio; cancel preserves previous import; unavailable file actionable; no blanket Photos permission assumed when system picker suffices. | Files security access/download delay; missing usage keys if a plugin asks direct photo access. | ☐ | ☐ |
| 054 Import processing/timing | Arrow PNG, timing GIF/WebP | 1. Crop/fit; rotate; flip X/Y; Pixel art. 2. Change Bright/Contrast/Colour/Gamma. 3. Remove dark/chosen background, tolerance, colors/dither. 4. Speed/frame-step/scrub/play. | Correct corners/aspect/crop; transparent/removed pixels unlit; settings applied consistently; frame timing/order retained at All/1×; intentional frame-step changes explicit. | Crop pinch/drag, orientation metadata and slider semantics. | ☐ | ☐ |
| 055 Import save/send/re-edit | Processed import; free controller space | 1. Save. 2. Reopen from Made by you and edit. 3. Send; leave tool. 4. Open another import while processing. | Pixels/settings/timing persist; sent GIF loops alone; latest import wins; no stale processing overwrite or device takeover; actions recover. | Memory pressure from image decode/bake and picker lifecycle. | ☐ | ☐ |
| 056 Malformed/large imports | Broken GIF, newer `.glyph`, large owned image | 1. Open each invalid/large fixture. 2. Cancel a long decode/bake. 3. Open valid small fixture. | Clear broken/newer-version/resource-limit error; no crash/OOM, partial creation or Saved entry; valid retry works. Record fixture dimensions/bytes. | iOS memory ceiling; do not treat process kill as acceptable validation. | ☐ | ☐ |
| 057 GIF/`.glyph` share round trip | Saved Draw/import plus 100-frame fixture | 1. Share GIF and `.glyph` to own Files via iOS share sheet. 2. Dismiss without sharing once. 3. Reimport `.glyph`. 4. Decode exported GIF. 5. Repeat on iPad. | Share sheet opens/anchors; no external recipient contacted; GIF frame timing preserved with sensible crisp upscale; `.glyph` retains pixels/meta and imports under new ID, never overwrites original. | iPad popover anchor, Files destination, cancel and temporary-file access. | ☐ | ☐ |
| 058 Creation management/persistence | Several test creations | 1. Rename/play/edit/delete only test creations. 2. Search/favourite where available. 3. Restart offline. 4. Inspect Display Made by you and Rotation references. | Consistent library; persistence independent of internet; deleted references shown unavailable rather than silently substituting another item; owner creations untouched. | Storage path/plugin persistence and cold-start reload. | ☐ | ☐ |

## 6. Make — Music, games, Now Playing and Alerts

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 059 Microphone deny/allow/revoke | Fresh mic permission; physical phone | 1. Open Music/request access. 2. Deny. 3. Enable Microphone in Settings for Glyph and return. 4. While active revoke; return. | Denied state helpful; no false Listening/live sound; grant recovers; revoke stops capture safely; privacy text says audio stays on phone; orange indicator only during capture. | NSMicrophoneUsageDescription alone may not configure permission_handler; record no-prompt/plugin errors. | ☐ | ☐ |
| 060 Nine visualizers | Mic allowed; external speaker at safe volume | 1. Use Spectrum, Mirror, Waveform, Beat rings, Bass fire, Waterfall, Starburst, VU meter, Radial. 2. Play beats then silence 10 s each. 3. Adjust palette/Sensitivity/Smoothing/Range and effect controls. | Every style responds to real microphone; silence settles/idle animation distinguishable from reaction; phone/panel synchronized; parameters stable; no Send for live-only content. | Audio routing/session differences; simulator microphone cannot pass this. | ☐ | ☐ |
| 061 Music stop/leave/interruption | Streaming Music; native baseline | 1. Stop. 2. Restart/leave screen. 3. Restart; interrupt with Siri or a test call, then return. 4. Select another look/device. | Capture/stream ownership released on stop/leave; mic indicator clears after settling; interruption safely recovers or requires explicit restart; never restores onto new target. | AVAudioSession interruptions/routing; no Android foreground service. | ☐ | ☐ |
| 062 Music keep-screen-on | Set test phone Auto-Lock to 30 s; foreground Music | 1. Enable Keep screen on, wait 60 s. 2. Disable, wait for lock. 3. Exit Music and repeat idle wait. | Awake only when requested/owned; lock works after disable/exit; background switch unavailable on iOS; no persistent awake state after stopping. | Wakelock plugin support differs from background execution; restore Auto-Lock afterwards. | ☐ | ☐ |
| 063 Music Home/lock | Release, debugger detached; native baseline | 1. Stream reacting Music. 2. Home 30 s then 2 min. 3. Repeat lock 2 min. 4. Return/restart and Stop. | No promised ongoing iOS background Music; safe stop/timeout returns WLED native look; no stuck mic indicator or falsely active session on return; transient OS grace period recorded. | Hidden background toggle is insufficient if internal default still attempts service or shows background failure toast. | ☐ | ☐ |
| 064 Every game | Test device; disconnected variant too | 1. Play Snake, Blocks, Brick Breaker, Pong, Flap, Racer, Invaders for ≥60 s each. 2. Exercise each offered control, difficulty/options, score/loss/restart. | Seven games functional, panel/preview agree; touch controls responsive; score/high-score persist; disconnected play stays on phone; no Send of live game. | Multitouch, landscape/safe areas, large text; haptics cannot substitute visual loss feedback. | ☐ | ☐ |
| 065 Games ownership/lifecycle | Active game; native baseline | 1. Pause/resume if offered. 2. Home/lock 30 s. 3. Return, navigate Back, reconnect after Wi-Fi loss. | No game progressing invisibly against user expectations; safe pause/stop and explicit restart; tool stream ends on exit and baseline returns; no stray controls/awake ownership. | System gestures vs game pad; actual suspension, not debugger behavior. | ☐ | ☐ |
| 066 Now Playing unsupported | iPhone, known native look; music app playing | 1. Open Now Playing. 2. Read notice. 3. Change demo styles and attempt Show/Stop. 4. Switch music track, return. | Android-only notice/no access prompt; no claim to follow tracks; unsupported Show must be disabled or clearly described as demo and cannot falsely claim real cover delivery. No covers/files stored. | Current shared UI still exposes Show; test safety/accuracy instead of marking whole screen N/A. | ☐ | ☐ |
| 067 Alerts unsupported | iPhone; native Saved/Show playing | 1. Open Alerts. 2. Inspect status/CTA/app picker/quiet hours/demo. 3. Attempt Test/enable; receive an ordinary test notification on phone. 4. Restart Glyph. | Android only status, disabled enable/test; no notification access request, app enumeration, real overlay or monitoring; no change to native playback; persisted quiet hours cannot imply active service. | iOS notification permission for Glyph is not access to other apps' notifications. | ☐ | ☐ |
| 068 Unsupported-feature isolation | Music/Rotation/Draw used sequentially | 1. Visit Alerts/Now Playing between supported tools. 2. Return to Display and select fresh look. 3. Inspect files/presets/logs. | Unsupported visits do not steal playback, retain timers/feed ownership or create Saved entries; no native-channel error leak. Android overlay/resume cases explicitly N/A for current iOS implementation. | Caught bridge errors can still cause tool cleanup/state bugs. | ☐ | ☐ |

## 7. Glance cards and phone Rotations

Use names/coordinates of two real places with different timezones, one European
and one outside Europe. No GPS. Freshness cases require actual elapsed time or
an explicitly supplied QA fixture build; record which. Do not alter iPhone
clock to bypass TLS/cache behavior and call it normal coverage.

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 069 Empty state/card persistence | Test profile with no Glance data | 1. Open Glance; inspect alternating demo. 2. Add/edit/delete a test card. 3. Focus without showing. 4. Restart offline. | Weather/days empty-state CTA; card focus/preview distinct from live; config persists; Save local vs Show on device clear; no Send/GIF for live cards. | Safe-area tiles, modal keyboard and per-screen ownership. | ☐ | ☐ |
| 070 Place search/disclosure | Internet available | 1. Add Weather; read disclosure before typing. 2. Type rapidly, choose place. 3. Use manual named coordinates and long card title. 4. Change °C/°F. | Debounced results/latest query wins; place/coords disclosure, Open-Meteo/CC BY/GeoNames credit links; no GPS request; valid units/day/high-low; final letters scroll. | Keyboard/autocorrection, HTTPS failures and external links. | ☐ | ☐ |
| 071 Current weather/timezones | Two places; one day differs from phone | 1. Show each card. 2. Inspect temperature/condition/high-low/day/night and observation age. 3. Edit place while request pending. | Chosen place's local day/night; observation time displayed in phone local time; latest place used; missing values not zero; sensible small/wide-panel layout. | Phone locale/timezone independent of place timezone. | ☐ | ☐ |
| 072 Forecast | Candidate has forecast; place also has Weather | 1. Add Forecast for same place. 2. Show today, next three hours and next three days. 3. Change units/title/place. 4. Inspect readout timestamps. | Today high/low dominant; place-local hourly labels/day labels; matching units; same weather request/cache reused, not requests per frame; no stale earlier place. | Narrow panel scrolling/dynamic labels and request deduplication. | ☐ | ☐ |
| 073 Air quality | Candidate has AQ card; European/non-European phone region variants | 1. Add AQ place. 2. Compare Auto, US AQI and European preferences. 3. Change **phone region**, relaunch, retry Auto. 4. Inspect index/level/PM2.5/disclosure. | Auto follows phone region, not selected place; explicit override stable; number, level word and index name consistent; CAMS modelled forecast disclaimer and Open-Meteo/CAMS/Copernicus/GeoNames credits. | iOS region vs language; color cannot be only level cue. Restore region. | ☐ | ☐ |
| 074 AQ no-data/invalid fields | QA response fixture with null AQ, or verified uncovered place | 1. Request null/no-coverage data. 2. Show card alone then in Rotation. 3. Restore valid data and retry. | App No air quality data here, panel NO AIR DATA; never AQ=0; Rotation skips unavailable entry and recovers. Record actual response/fixture and no-data location. | Real API coverage varies: no available fixture/location means Blocked, not assumed Pass. | ☐ | ☐ |
| 075 Offline/freshness/expiry | Weather/AQ fetched; LAN retained, WAN disabled | 1. Record fetch times. 2. Trigger failed refresh. 3. Observe Weather at 45 min/2 h, AQ at 90 min/6 h. 4. Relaunch offline and reconnect WAN. | Failed refresh/age marks OLD/stale; weather unavailable by 2 h, AQ by 6 h; cached data survives restart within limits; no invented zero; retry bounded and successful recovery. | Foreground elapsed-time run required; iOS background refresh is not promised. Fixture timings documented separately. | ☐ | ☐ |
| 076 Feed cadence/backoff | Network log on test router/Mac or authorized QA feed fixtures | 1. Show same place in editor/card/Rotation. 2. Observe ≥30 min. 3. Inject timeout/5xx/429 only via supplied fixture build if available. 4. Retry repeatedly. | Weather ≤one shared due refresh per 15 min, AQ per 30 min; failed cached data backoff, Retry-After and explicit-retry floor respected; no poll per frame. Missing fault fixtures blocked separately. | TLS interception needs test trust setup; do not modify production endpoint/signing to inject errors. | ☐ | ☐ |
| 077 Day counters | Offline; phone timezone known | 1. Add until tomorrow/today/yesterday and since yesterday/future. 2. Long title/large count/leap-day date. 3. Show each. | Civil days correct; TODAY/past/future-since labels explicit; no 24-hour arithmetic errors; works without requests; date friendly and last letters visible. | Calendar picker/locale and system timezone. | ☐ | ☐ |
| 078 Midnight/travel/DST | Counter/Weather active; controlled timezone change; midnight session or QA clock fixture | 1. Cross phone local midnight. 2. Change phone timezone to move date across boundary. 3. Check counter and remote place Weather/Forecast. 4. Restore timezone; cover DST boundary via real run/fixture. | Counter follows phone date, remote cards place date; no off-by-one through DST; change updates without recreating card. Evidence distinguishes real and simulated clock. | Restore system automatic time/timezone; offset-only device clock is a separate risk. | ☐ | ☐ |
| 079 Mixed Rotation editor | Card, library look with tweaks and test creation | 1. New Rotation; add via Cards/Animations/Yours. 2. Reorder/remove; change durations (chips 5/10/15/30/60; custom if offered). 3. Save/reopen. | Ordered previews/references/tweaks retained; persisted durations within 3–120 s model limits; no device preset masquerading as renderable phone entry; Rotations distinct from Shows. | Drag alternatives, duration accessibility and long-title layout. | ☐ | ☐ |
| 080 Rotation run/skip/fallback | Mixed Rotation; native baseline | 1. Show and time two loops. 2. Delete referenced test card/creation. 3. Make all entries unavailable. 4. Restore/add valid entry. | Order/durations correct; unavailable references visible in editor and skipped; all unavailable displays -- with bounded ~3 s retry scan; recovery uses current entries. No alert interruption claim on iOS. | Wall-clock timing and suspension; background support off. | ☐ | ☐ |
| 081 Glance/Rotation stop/leave | Running card/Rotation on device | 1. Stop. 2. Restart and leave screen. 3. Repeat Home/lock, Wi-Fi loss, power off and device switch. 4. Relaunch. | iOS background toggle hidden/unavailable; non-background run ends and native look returns (timeout if unreachable); no auto-resume after restart or packets to new/off host. | Android default Keep showing after you leave does not apply as an iOS service promise. | ☐ | ☐ |
| 082 Feed size/readability | Real 8×8, 16×16, wide and 32×32 panels where available | 1. Show Weather/Forecast/AQ/counters with negative temp, long title, large count, stale and no-data states. 2. Observe safe bright/dim environments. | Values/units/condition distinguishable and full text readable; never send stale as fresh; visual limitations recorded per actual panel. | Phone Dynamic Type cannot fix physical LED readability; absent sizes Blocked. | ☐ | ☐ |

## 8. Device — control, Saved, Shows, Routines, storage and integrations

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 083 Hub/power/brightness/night light | Baseline snapshotted; safe brightness cap | 1. Open Device while stream, Saved and off. 2. Power toggle, fader, Night light Fade out/Then off/Sunrise. 3. Close phone while short fade runs. | Stage/source/status accurately reflects device or honest placeholder; controls/numbers agree with read-back; fade runs on device; no implicit brightness/power jump. | Device status may be polled, not a literal GIF pixel mirror; safe-area fader access. | ☐ | ☐ |
| 084 Saved play/rename/delete | Two QA Saved looks and owner entries left intact | 1. Play QA entry; rename; mark power-on if offered. 2. Cancel Delete. 3. Delete playing QA GIF with file-free option. 4. Refresh/restart. | Correct ID renamed; switches away before removing playing file; only selected QA entry/file removed; unrelated Saved retained; system Glyph intro/Power-on hidden/undeletable. | Sheet dismissal vs destructive confirmation; stale selected-host response. | ☐ | ☐ |
| 085 Missing file/shared references | Spare test GIF referenced by a Show/boot; ledger | 1. Remove only QA GIF through WLED editor after switching away. 2. Refresh Saved. 3. Inspect warning/actions. 4. Delete referenced Saved using app. | Missing file identified, not falsely playable; reference impact explained; no system/user file deletion; Show/boot behavior deliberate; refresh recovers after re-Send. | Device-side external changes and cache invalidation. | ☐ | ☐ |
| 086 Shows editing/playback | Two QA Saved looks | 1. New Show; add/reorder/remove entries, durations/transitions. 2. Set shuffle, Forever/Times and ending look/off where offered. 3. Save/play; lock phone through two cycles. | Ordered/finite/shuffle behavior matches definition; runs on device without phone; Show names/metadata persist; Glance mix link leads to Rotation rather than embedding live card. | Keyboard/reorder on narrow phone; native WLED owns exact cycle timing. | ☐ | ☐ |
| 087 Shows failure/delete | QA Show; offline controller variant | 1. Edit/cancel. 2. Save while phone Wi-Fi off. 3. Reconnect/retry. 4. Delete QA Show. | Cancel preserves definition; failure honest and recoverable; no duplicate or owner preset changes; deleting Show does not delete its Saved looks/files. | Delayed write completion and repeated taps. | ☐ | ☐ |
| 088 Set the time/offset | Spare device with NTP off/unsynced; config logged | 1. Open Routines → Set the time. 2. Check clock/read-back. 3. Repeat with NTP already enabled/custom owner timezone. 4. Retry unreachable. | Clock set from phone UTC; enables NTP only if off; preserves existing enabled config/host; error explicit. Newly enabled iOS timezone uses offset fallback; DST behavior limitation recorded. | `glyph/platform` IANA bridge unavailable; fixed offset may not follow future DST. | ☐ | ☐ |
| 089 Routines execution | Device time correct; QA Saved/Show | 1. Create one-time daily/weekday Routine 2–3 min ahead. 2. Select days/time/target, enable and Send. 3. Lock phone past trigger. 4. Read device state. | Sentence summary matches trigger/target; native schedule fires with phone off; unrelated schedules preserved; no manual phone timer dependency. | 12/24-hour picker and phone/device timezone mismatch. | ☐ | ☐ |
| 090 Routine variants/validation | Spare; QA schedule slots only | 1. Edit every-hour, sunrise/sunset offsets, seasonal date range where offered. 2. Try invalid date range/empty target; cancel. 3. Disable/delete QA Routine. | Valid fields read back; invalid combinations guarded; slot capacity/error honest; sunrise/sunset requires valid device location/time and is not claimed verified without observed event. | Locale date ordering and keyboard; long-wait variants may be Blocked. | ☐ | ☐ |
| 091 Boot intro/power-on | Spare; original boot selection/files recorded | 1. Inspect Routines with system intro only. 2. Choose QA power-on look. 3. Reboot spare once; observe intro then chosen look. 4. Restore original boot. | System row hidden; Choose a power-on look empty action; user power-on editable; intro not duplicated/deletable; intro installation preserves unrelated presets. | Reconnect after reboot/Bonjour new IP; physical observation required. | ☐ | ☐ |
| 092 Storage/list/delete/free-up | Spare with QA files; baseline inventory | 1. Open Storage and refresh. 2. Inspect used/free values and referenced/unused files. 3. Cancel delete/free-up. 4. Delete only QA unused file; try active file via supported route. | Usage agrees with device; reference/active-file safeguards; system config/intro protected; no unrelated unused owner file removed by bulk action. | Sheet scroll/safe area; asynchronous list must be tied to host. | ☐ | ☐ |
| 093 Storage milestones/full-send | Spare; bounded QA filler files; recovery headroom | 1. Cross 50%, refresh twice/restart. 2. Cross 90%. 3. Attempt Send too large for remaining staging space. 4. Remove filler below threshold and recross. | One warning per threshold crossing/device; persisted non-nagging; re-arms below threshold; Open reaches storage; explicit insufficient-space error preserves playback and complete content. | iOS bake memory independent of controller filesystem; don't exhaust config/recovery space. | ☐ | ☐ |
| 094 Devices/switch/mirror | Two test controllers, both snapshots; second distinct layout | 1. Add/select/rename devices. 2. Enable mirror for second; stream dim look. 3. Make mirror unreachable; switch primary during Send/Glance. 4. Disable mirror. | Per-device dimensions/transforms used; failure visible without breaking primary; new target not touched by old cleanup; setup/Saved native actions selected-target only; mirrors stop safely. | UDP per-host routing/network loss; groups differ from panel grids. | ☐ | ☐ |
| 095 Advanced orientation/forget | QA device record; config baseline | 1. Show test pattern; rotation/mirror/serpentine corrections. 2. Try rectangular 90° option. 3. Restore app layout. 4. Forget spare and re-add. | App-local transforms explained/persisted; unsupported rectangular rotation guarded; forget local record does not erase controller files/settings; no factory-reset language. | Accessible toggles and host identity after rediscovery. | ☐ | ☐ |
| 096 Firmware settings/WebView | Device reachable; spare for writes | 1. Open WLED firmware settings. 2. Navigate subpages/history, Refresh, Close/back. 3. Change spare name only and return. 4. Repeat unreachable then Retry. | Local HTTP pages render/use JS; history back before closing; useful failed-page UI; device refresh/reconnect reflects change; no unintended reset/update. | WKWebView ATS/local-network policy may block HTTP even if Dart API works; inset/keyboard/platform-view gestures. | ☐ | ☐ |
| 097 Home Assistant sheet/copy | QA Saved/Show names, including long/mixed case | 1. Saved → Use with Home Assistant. 2. Copy each QA name to own Notes/text field. 3. Open guide, return. 4. Repeat no Saved/Shows. | Exact stored trimmed names, case/spaces preserved; system/unnamed items excluded; empty message useful; guide launches Safari; no entity-watch setup falsely offered. | Clipboard/paste prompts, safe-area scroll, external app handoff. | ☐ | ☐ |
| 098 HA end-to-end | Test HA 2024.10+, WLED light/preset/playlist entities | 1. Import both guide blueprints in test HA. 2. Trigger QA Saved and Show by copied name with 10 s return. 3. Repeat while device initially off. 4. Manually choose another look before return. 5. Lock phone throughout. | HA triggers native content/return without Glyph; off state restored; newer manual choice preserved; optional other selector permits cross-kind restore. Quiet hours/cooldown/bounded until-trigger exercised using test automation only. | Safari/my.home-assistant redirect; not dependent on iOS notification access. Missing HA instance Blocked. | ☐ | ☐ |

## 9. Catalog delivery, community and persistence

Do not alter production catalog endpoints, signatures or publish content for
QA. Invalid-signature/newer-version cases need supplied signed/invalid test
fixtures in an authorized QA build; label fixture results separately.

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 099 Public catalog/manual check | Production verification key enabled; internet | 1. Glyph menu → New animations. 2. Inspect host/privacy/count/status. 3. Check now; recheck. 4. Browse library/credits. | Signed Pages catalog loads, count/status/time update; recheck up to date; all content accessible; no device IDs/account/analytics sent; count need not increase for unchanged revision. | TLS/network/cache path must work in iOS build, not Android evidence. | ☐ | ☐ |
| 100 Offline cache/recovery | Successful 099; favourites/recent/channel active | 1. Kill app; disable internet and relaunch. 2. Browse/search. 3. Check now offline. 4. Restore internet/recheck. | Bundled/cache available cold; failure keeps library/selected look/favourites/recents/channel; explicit error; recovery updates status without resetting playback. | iOS process kill/container persistence. | ☐ | ☐ |
| 101 Daily checks/persistence | Check once a day initially off | 1. Confirm default off/no startup request. 2. Enable, restart; note timestamp. 3. Leave app backgrounded >24 h, resume when due. 4. Disable/restart. | Toggle persists; due checks only while app open/on resume; no iOS background fetch promise; no repeated checks before due; last good cache retained. | True elapsed 24 h or documented clock fixture required; if not run mark Blocked. | ☐ | ☐ |
| 102 Activation/failure/update fixtures | Authorized QA catalog fixture build available | 1. Present valid new arrivals, invalid signature/hash, truncated/oversized/malformed payload, newer-app manifest and rejected ID collision. 2. Restart after each. | Only fully validated compatible catalog accepted atomically; Just added shown on new arrivals; useful update-required route; invalid data keeps last good content/registry and user selection. | No debug bypass of signature validation counts as delivery pass; missing fixtures Blocked. | ☐ | ☐ |
| 103 Glyph menu/diagnostics/What's new | All tabs; external links enabled | 1. Open menu from each tab. 2. What's new, roadmap/community/Discord, Suggest animation, Send feedback; cancel before posting. 3. Copy diagnostics, inspect privately. 4. Restart/update with same signing ID if prior iOS build available. | Correct links/version/device details; feedback preview editable, no automatic posting; safe missing iOS phone-model fallback; no credentials/notification content; What's new cadence and user data persist across update. | `glyph/platform` absent; Safari/share-sheet return. Upgrade subcase Blocked without older compatible build. | ☐ | ☐ |

## 10. iOS lifecycle, haptics, accessibility and release stability

Repeat lifecycle rows for ordinary Display stream, Draw mirror, Music and
Glance/Rotation. Use a test Saved/Show as the native baseline. Record realtime
timeout; when unreachable/killed, wait that timeout plus 10 s and observe the
panel. Persistent **device-owned** Saved/Shows/Routines/Clock must continue
when the phone is locked/off; phone live streams have no iOS background guarantee.

| ID / test | Preconditions | Steps | Expected result | iOS-specific risk | Pass | Fail |
|---|---|---|---|---|---|---|
| 104 Home/lock/force quit | Release, detached debugger; each live tool | 1. Home 30 s/2 min, lock 2 min, force quit separately. 2. Observe LEDs/live state/phone mic indicator. 3. Relaunch. | Stream stops safely or expires to native playback; no stuck realtime mode, microphone/awake ownership or silent auto-resume; UI reflects actual session. Record any ordinary Display auto-resume behavior explicitly. | OS grace periods differ; no Android Stop notification exists. | ☐ | ☐ |
| 105 Network/power/manual takeover | Two QA devices; native baseline | 1. Wi-Fi off/on, AP roam, controller brief reboot. 2. Power off via Glyph/WLED. 3. Choose a new native look in WLED during live activity. 4. Switch target while reconnect pending. | Errors/retry honest; fresh user action wins; no late power-on/restore/UDP to new/off host; device native playback remains viable; no spin or crash. | Cellular cannot reach LAN; Bonjour changes/IP reuse; airplane mode differs from WAN-only loss. | ☐ | ☐ |
| 106 Safe areas/orientation/keyboard | Notch iPhone, small phone and iPad variants | 1. Rotate every main tab/tool/setup step/sheet and firmware page. 2. Open keyboard for search, Write, names, SSID/password, PIN. 3. Scroll to primary action and dismiss keyboard/route via available gestures. | No clipped Stage/title/CTA/dock, home-indicator overlap, stuck focus or RenderFlex overflow; inputs/buttons remain reachable; layout stays correct after rotation/back. | iPhone plist allows portrait and both landscapes; iPad also upside-down; popovers/platform views. | ☐ | ☐ |
| 107 Dynamic Type/contrast | Physical iPhone and iPad | 1. Settings → Accessibility → Display & Text Size → Larger Text; test default, largest standard and largest accessibility size. 2. Bold Text/Increase Contrast. 3. Repeat Display, every Make tool, setup, Device lists/dialogs and errors. | Text/buttons readable, scrollable and untruncated where needed; values/status not conveyed solely by color; LED headings have readable semantic equivalents; no forced text-scale suppression. | Custom fonts/pixel headings/FittedBox/knobs may hide scaling issues. | ☐ | ☐ |
| 108 VoiceOver navigation/actions | VoiceOver on; test content, safe controller state | 1. Navigate splash/onboarding, dock/Stage/Tweak/Send, each tool, card/Rotation editor, setup diagrams/PIN/review/undo, Saved/Shows/Routines/storage/HA. 2. Activate/adjust without sighted gestures; inspect focus after sheets/errors. | Meaningful labels, roles, selected/disabled/busy states and numeric values; logical focus; knobs/faders increment/decrement; frame Move earlier/later actions work; essential setup steps have textual choices; no endless frame announcements. | Custom LED canvas/headings/sparse diagram semantics; test actual VoiceOver, not source presence. | ☐ | ☐ |
| 109 Reduced Motion | Settings → Accessibility → Motion → Reduce Motion on, then off | 1. Cold launch. 2. Repeat intro, Stage morph/surf, Surprise, Send beam, dock/tab changes, animated sheets and live tile previews. 3. Complete same tasks. | Nonessential UI motion suppressed/simplified without removing controls/state feedback; no moving focus/mandatory long animation; intentional LED content stays controllable and distinguishable from decorative UI motion. Log unsupported preference as failure/gap. | No explicit reduced-motion hook found at authoring time; cannot assume framework handles custom animation. | ☐ | ☐ |
| 110 Haptics | Physical iPhone with haptics enabled; iPad/no-haptic variant | 1. Channel change/knob detent, Send, Surprise landing, selection/toggles, games. 2. Repeat haptics disabled or hardware without support. | Selection ticks, light Send and stronger Surprise/appropriate game events feel distinct where supported; no repeated buzz from previews; all actions remain visually/semantically usable without haptics. | Simulator/iPad cannot establish Taptic strength; system settings/hardware differ. | ☐ | ☐ |
| 111 Release soak/performance | Release detached; safe brightness; power/thermal baseline | 1. Browse/tweak 10 min. 2. Stream Music 10 min foreground. 3. Run mixed Rotation 10 min foreground. 4. Perform large supported Send then Stop. 5. Idle 2 min. | No crash/jetsam/stuck UI, serious sustained stutter or uncontrolled heat; input stays responsive during bake; idle releases capture/streams/awake state; record duration, battery drop and thermal observation rather than inventing thresholds. | iOS memory/thermal throttling, 60/120 Hz; debug speed is not release evidence. | ☐ | ☐ |
| 112 Final restore verification | All preceding runs stopped; private ledger/baselines | 1. Execute cleanup below. 2. Capture after JSON/inventory. 3. Compare parsed baseline/config/presets and file hashes/sizes. 4. Observe original physical look/off state, then idle phone. | No test content/settings/HA actions remain; owner data preserved; recovery verified by correct MAC; no mic indicator/live stream/awake ownership; all exceptions/remaining coverage limits documented. | A success toast or process exit does not establish restoration. | ☐ | ☐ |

## Results template

Copy into the run's private report; publish only sanitized evidence. Do not
fill these placeholders with assumptions or results from another platform.

| Run metadata | Value |
|---|---|
| Date/time/timezone; tester/agent | |
| Commit; dirty diff summary; app version/build; artifact hash | |
| Mac/macOS; Xcode version; Flutter/Dart; SwiftPM/Pods outcome | |
| Signing Team/profile/capabilities; bundle ID overrides | |
| Phone/iPad model, iOS/iPadOS; release/debug; debugger detached? | |
| WLED version/build, board, private MAC reference, sizes/output/grid arrangement | |
| Network/AP setup, Local Network/mic grants, region/timezone, realtime timeout | |
| Baseline/evidence directory (private); safe brightness agreed | |
| Candidate feature status: wizard / grids / forecast / AQ / HA | |

| Automated/build gate | Result / evidence |
|---|---|
| `flutter analyze` | |
| Full `flutter test` (counts/skips) | |
| Signed `flutter build ios --release` | |
| Physical release install/cold start | |
| Optional simulator/fixture/native checks (name exact commands) | |

| Case ID + variant | Pass / Fail / Blocked / N/A | Actual result vs expected | Evidence / issue | Retest result |
|---|---|---|---|---|
| | | | | |

| Finding | Detail |
|---|---|
| Blocking defects | Repro steps, expected/actual, build/device, controller impact, sanitized logs |
| iOS gaps/fallback failures | Separate intentional Android-only scope from misleading/broken iOS UI |
| Unverified coverage | Exact IDs/variants, missing hardware/fixtures/elapsed waits; do not count as passes |
| Performance/thermal | Run duration, brightness, battery delta, frame observations, memory/thermal logs if available |
| Restore comparison | Config changed-field diff, preset parsed equality, file inventory/hash checks, original state observation |
| Final recommendation | Ready / not ready for stated iOS scope, with outstanding gates; no implied release approval |

## Cleanup checklist

- [ ] Stop Music, games, cards/Rotations and all Display/editor/import streams.
      Turn off Keep screen on; verify mic indicator clears and phone auto-locks.
      No Android service/notification check can substitute for iOS cleanup.
- [ ] Reconnect to the **original controller MAC**; resolve pending setup recovery
      and Undo layout/grid migration before forgetting any device record.
      Restore realtime map, app rotation/mirrors/serpentine, output count/complete
      output fields, power limiter, sync and original dimensions/bounds.
- [ ] Restore original Wi-Fi SSID/password/BSSID and AP fallback/settings on the
      spare; verify home connection. Restore PIN, time/NTP/offset, device name,
      boot selection and night light. Never restore masked credentials as real ones.
- [ ] Switch away from playing test GIF before deleting. Remove only ledger-owned
      Saved entries, staged/replaced/unused GIFs, Shows and Routines. Preserve all
      pre-existing system/owner files; reconcile any system intro installed by QA.
- [ ] Restore original config fields, presets and native playback/power/brightness
      as described above. Poll persisted files after flash writes/reboot; compare
      `/json/state`, `/presets.json`, `/cfg.json` and file inventory against private
      snapshots. Record runtime-only differences and any intentional exceptions.
- [ ] Remove test creations/cards/Rotations/import/share fixtures from app/Files
      and test HA automations/blueprints if created for this run. Do not delete
      pre-existing content or alter unrelated HA configuration.
- [ ] Restore phone Wi-Fi/mobile data/VPN, region/timezone/automatic time,
      Auto-Lock, Dynamic Type, Bold Text, contrast, Reduce Motion, VoiceOver and
      haptic settings to recorded defaults. Restore catalog daily-check preference.
- [ ] Restart Glyph once: saved user data intact, live tools off, no unexpected
      device power-on/stream, native baseline visible (or original off state).
      Inspect final logs for fatal/unhandled/plugin/network retry loops.
- [ ] Keep credentials/snapshots private; retain only sanitized screenshots,
      timings/GIF metadata and defect evidence for handoff. Remove temporary
      trust/proxy settings used by QA fixtures.
- [ ] Record every blocked/N/A case and cleanup exception. Check working-tree
      status; no unintended source/config changes, commits, tags or publication.
