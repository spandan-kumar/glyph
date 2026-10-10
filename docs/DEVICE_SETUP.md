# Device setup wizard

Plan agreed on 9 October 2026, refined on 10 October. Implementation has not started. This follows
the prepared v1.3.6 maintenance release; it does not expand that release.

## Decisions and scope

- Include joining home Wi-Fi, with an assisted Android connection and a
  guided Android Wi-Fi settings fallback.
- Support one rectangular panel first. Several panels on one controller,
  irregular shapes, gaps and layout-file editing come later. This is separate
  from Glyph's existing groups of independent devices.
- Offer an optional power-supply/current-limit step using an entered rating.
- Assume WLED is already installed and the hardware is connected. Firmware
  flashing is outside this wizard. Explain that prerequisite on the new-device
  path and link to the WLED installer when needed.
- Support a single addressable digital output for the first hardware-write
  path. Existing complex outputs, HUB75, custom maps and unsupported firmware
  retain the current discovery/orientation/settings path without conversion.
- No account, cloud service or internet requirement for setup itself.
- Android uses the assisted setup-network connection with guided fallback.
  iOS uses guided Wi-Fi settings initially, sharing the Dart configuration and
  verification flow. This does not imply that the iOS release is ready.
- Keep this device format on ESP filesystem storage. Bigger displays will
  need additional hardware storage; microSD/other storage and compatible WLED
  playback support must be verified on that hardware. Do not shorten content
  automatically to make it fit, or assume an SD card works with stock firmware.

## Existing pieces to reuse

`OnboardingFlow` and `MatrixSetupPage` already share discovery, a device hello,
an orientation correction and an optional first-vibe choice. `SearchStep`
already provides mDNS, subnet discovery and manual addressing. `DeviceStore`
holds the selected device, capabilities and app-local layout. `WledClient`
already reads configuration and posts partial changes. Setup currently blocks
notification alerts through `ToolSession`.

The current orientation correction changes Glyph's live frame ordering; it
does not configure the physical panel in WLED. The wizard must keep hardware
wiring and app presentation transforms separate and avoid correcting twice.
Success must cover both live streaming and device-owned GIF playback.

## Entry points and flow

First launch and Device → Add a device share the same wizard. An existing
device gets Device → Set up display, starting with its current configuration.
The quick Fix orientation action remains available for a working display.
Use the Lightbox design kit, visual diagrams and plain questions; show
technical output settings only when necessary.

1. **Connect.** Choose “Already on Wi-Fi” or “New device”. The first choice
   uses existing discovery/manual address. The new-device choice connects
   to the WLED setup network with Android's system approval, including
   renamed/password-protected setup networks. Verify WLED and device identity
   before showing the home-network form. Offer guided settings if permission
   or connection is declined/unavailable.
2. **Join home Wi-Fi.** List networks scanned by WLED through `/json/net`,
   handling asynchronous scan progress and duplicates; keep manual/hidden SSID
   entry. This avoids phone-side scanning, not all Android connection permissions.
   Explain the 2.4 GHz requirement for supported ESP32 hardware and help when
   the desired network is missing or available only at 5 GHz.
   Choose or enter the home network and password. Keep
   credentials only for the operation; never log them or put them in shared
   preferences, backups or diagnostics. Route provisioning requests through
   the selected local Wi-Fi network even when mobile data is active. Save the
   device identity before handoff. Where firmware keeps AP access available,
   poll `/json/info` for a valid home-network IP before releasing the setup
   connection. Return the phone to home Wi-Fi, try that IP first and verify
   identity; use discovery/manual addressing if AP access disappears or the IP
   changes. Prove this order in the contract spike. Support retry,
   manual IP and a guided return to the setup network after a wrong password.
   An HTTP acknowledgement alone is not successful provisioning.
3. **Check the device.** Read firmware/capabilities, current configuration,
   output count/type, LED count, mapping overrides and reachability. Save a
   private recovery snapshot before any hardware change. A settings PIN gets
   an unlock route. Weak Wi-Fi offers a placement/retry step; do not change
   transmit power or other RF settings automatically. Let an already-working
   device continue without rewriting it.
   A supported panel already configured in WLED starts with a dim corner/arrow
   check. If live and saved playback agree, offer Finish and optional power
   review; show size/wiring correction only when needed or explicitly requested.
4. **Size and output.** Offer common sizes such as 8×8, 16×16, 8×32 and 32×32,
   plus custom width/height, with LED-count comparison. Prefill from WLED.
   For a simple output, explicitly review the resulting LED count. Preserve
   its GPIO, LED type and colour order unless the user changes them. If the
   output pin is unknown, ask for the actual connected pin; never guess it.
   Block incompatible counts, dimensions or unsupported output configurations
   instead of silently truncating or replacing them.
5. **Power (optional).** Ask for supply voltage, current in amperes and whether
   the controller shares it. Show the existing LED limit in milliamperes and
   the proposed limit separately. Preserve an existing stricter limit by
   default; reserve controller headroom when shared. Verify limiter semantics
   on supported firmware before defining the recommendation formula. Supply
   rating alone does not establish the safe capacity of wiring or connectors.
   Skipping preserves the existing limit. Tests start dim and use sparse pixels.
6. **Wiring.** Default to three sparse physical tests: light LED 0 and ask
   which corner lit; light the next few LEDs and ask which way they travel;
   then light the first LED in the next row/column and ask which end lit.
   Known dimensions plus those answers identify corner, rows/columns and
   zig-zag/straight for a conventional single panel. Confirm with diagrams;
   retain manual diagram choices. Prove raw physical addressing first, bypassing
   app transforms, existing WLED maps, realtime offsets and output reversal.
   A logical LED 0 after mapping is not sufficient evidence of the wiring.
   Keep draft changes local; do not save to flash on every control adjustment.
   A phone diagram previews the candidate. If temporary live candidate testing
   cannot bypass the existing map safely, apply once and validate with recovery
   rather than pretending a stream confirms an unapplied WLED layout.
7. **Review and apply.** Show the selected size, wiring and any output/power
   changes. Apply only the necessary configuration fields, perform any required
   restart, reconnect by identity and read back the result. Refresh capabilities
   and display bounds. Preserve Saved looks, Shows, Routines, boot choices and
   unrelated outputs/settings. Do not upload a whole configuration file.
   Use the mapping/output transaction rules below; a partial JSON envelope
   does not mean output-array entries are safely partially editable.
8. **Look at your device.** Show corners sequentially with named positions,
   an upward arrow, an asymmetric letter and a moving row/column marker.
   Offer “Looks right”, “Something is wrong” and “Restore previous setup”.
   Do a sparse colour check; correct output colour order only if needed.
   Separate electrical layout errors from a physically rotated display. For
   rectangular displays, handle dimension-swapping rotations explicitly;
   current app-local 90° transforms only support squares.
9. **Finish.** Verify a short device-owned animation as well as streaming,
   then clean up the temporary file and restore the previous playback for
   existing devices. New devices can name the display and choose a first vibe.
   Finish can offer Send; it must not save an animation merely to exit setup.
   Mark per-device setup complete only after read-back and user visual approval.

Keep discovery, naming, the optional power step and advanced details skippable
where appropriate. Back retains the draft. Cancel restores temporary test state;
after a hardware write it clearly offers keep/revert instead of hiding the change.

## Mapping and output transaction

- Read live config and explicitly check `if.live.rlm` (Use LED map for realtime),
  which Glyph currently reads without using. For the wizard's normalized WLED
  2D layout, enable it when needed, include it in review, and snapshot/restore
  its previous value. Verify both live and GIF behavior after reconnect.
- Before migration, retain the complete app `MatrixLayout`: rotation, mirrors
  and serpentine. Encode the intended physical orientation/wiring in WLED and
  verify it. Only then replace the app layout with `MatrixLayout.identity` and
  restart streaming. Clear all four corrections, not just rotation. Restore
  the old app layout and realtime flag on rollback; retain the checkpoint if
  the app exits between device verification and local persistence.
- Plain-strip setups follow an explicit migration: confirm one supported
  output and its count, learn the physical wiring, create a WLED single-panel
  2D configuration, enable realtime mapping, verify and then clear the app
  corrections. Unsupported/multi-output/custom-map setups retain their
  existing configuration and quick app-local orientation path.
- For `hw.led.ins`, read the complete existing outputs and send the complete
  entries, preserving GPIO, type, order, start, reverse, skip, frequency,
  driver, per-output current and other supported fields. Change only intended
  count/colour/power values. Omitted fields can become defaults; prove full
  round-trip preservation on each supported schema. Apply the same rule to
  replacing the panel array. Do not replay the whole device configuration.
- Prove that rollback can return a newly created 2D layout to the original
  plain-strip mode; do not assume omitting the matrix object disables it.
- The working-device fast path never clears an existing app transform merely
  because WLED reports a panel. It must verify or migrate the full mapping
  first. Corner/arrow tests alone also do not prove the saved GIF path.

## Recovery and resource ownership

- Store a durable operation record before writes: device identity, phase,
  previous/candidate layout fields, app-local transform and relevant playback
  state. Retain a private config/state snapshot and a preset/file inventory
  for verification. Exclude credentials; do not blindly replay a whole snapshot.
- Roll back only fields the operation changed. Re-read before applying and
  detect changes made from WLED/another client; ask to reload rather than
  overwriting them. Keep recovery available from Device after app restart.
- Distinguish “write failed”, “write may have succeeded but reconnect failed”,
  “verified” and “restored”. Retry reads/reconnection before repeating a write.
  Restoration requires a reachable controller; an offline device remains in
  recovery-pending state, with actionable reconnect help.
- Wi-Fi provisioning has its own checkpoint. Existing Wi-Fi passwords cannot
  be reconstructed from a normal config snapshot. Preserve AP fallback during
  onboarding, avoid silently migrating an already-connected device to another
  network, and test recovery after incorrect credentials on a spare controller.
- A dedicated setup session owns test playback. Stop/suspend competing Music,
  Now Playing and Rotations deliberately; suppress/drop alerts during tests.
  Isolate tests to the selected device, including mirrored groups and WLED sync.
  Restore previous playback and group membership deliberately, with generation
  checks so cleanup cannot overwrite a newer user action or another device.
- Backgrounding pauses test streams; do not run setup as a background service.
  Cancel discovery, timers, network callbacks/bindings and test generators on
  exit. No microphone, persistent power locks or endless network retries.
- Recovery of playback must account for changed dimensions and saved bounds.
  Report incompatible existing content and offer rollback; never rewrite all
  the user's Saved looks to make a layout change appear successful.

## Implementation order and completion criteria

1. **Prove the contracts.** On a spare controller, verify supported firmware's
   network scan, AP join confirmation/IP capture and handoff; minimal panel
   patch, realtime-map flag, strip-to-2D migration and reversal, runtime mapping
   versus restart, complete output-entry count updates, current limiter,
   display bounds and restoration.
   Verify physical-index tests and custom-map detection. Capture sanitized
   fixtures. Gate hardware writes on proven schema/capability combinations.
2. **Models and transaction.** Add pure-Dart single-panel/output models and
   validation in `lib/wled`; scoped read/write methods in `WledClient`; a
   resumable setup/recovery coordinator under `lib/features/device` with
   persistence/lifecycle wiring outside the engine. Prove interrupted writes,
   verification and rollback before building the full UI.
3. **Android Wi-Fi connection.** Add a narrow native bridge for setup-network
   requests, per-network provisioning HTTP and callback cleanup. Request only
   the permissions needed by the platform/API in use. Keep the manual settings
   fallback available throughout; unsupported Android versions use it.
4. **Wizard and playback.** Extend shared onboarding/Device entry points,
   diagrams, optional power review, draft navigation and visual verification.
   Reuse arrow/letter patterns; generate sparse calibration frames in pure
   Dart without adding catalog artwork. Add an explicit setup playback session.
5. **Verification and release.** Run analyze, targeted/full Flutter tests,
   native bridge tests and an arm64 build. Then physical Android/controller QA.
   Assign the wizard release version only after these gates pass.

Automated coverage must include all corners × rows/columns × zig-zag/straight,
square and rectangular sizes, count mismatches, malformed/unsupported configs,
custom maps, PIN lock, colour order, power-unit conversion and preservation of
stricter limits. Include realtime mapping on/off, non-identity app layouts,
plain-strip migration/rollback and full output-entry preservation. Exercise
partial writes, ignored writes, delayed flash save,
restart, identity/IP changes, timeouts, cancellation at every phase, process
restart recovery, stale callbacks and external edits. Verify unrelated config,
presets/files, app transforms and grouped devices remain intact.

Widget tests cover both connection paths, optional steps, back/skip/cancel,
large text, screen-reader labels and reduced motion. Native/device tests cover
permission denial, setup Wi-Fi without internet, mobile data active, wrong
password, customized AP, network scans still running, hidden/duplicate SSIDs,
AP disappearance, captured-IP identity mismatch, home-network return and
callback release. Cover iOS guided settings through platform fakes initially.

Physical acceptance requires a disposable/spare WLED controller for new-device
provisioning; do not factory-reset the maintainer's working display. On the
working display, snapshot state/config/presets, prove streaming and saved GIF
orientation, inject a recoverable failure, verify restoration, clean test files
and check that the phone is idle after exit. Multi-panel behavior is only an
unsupported-config preservation test in this version.

## Primary references and unresolved technical checks

- [WLED quick start](https://kno.wled.ge/basics/getting-started/): setup network
  and AP access. Support customized names/passwords, not just defaults.
- [Android network request API](https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap):
  assisted local-network connection; route local traffic through its Network.
- [WLED 16.0.1 configuration source](https://github.com/wled/WLED/blob/v16.0.1/wled00/cfg.cpp):
  panel fields and configuration behavior. WLED explicitly treats the config
  schema as changeable; do not infer compatibility from version number alone.
- [WLED mapping](https://kno.wled.ge/advanced/mapping/) and
  [JSON API](https://kno.wled.ge/interfaces/json-api/): custom mapping and
  playback/display bounds must be accounted for before a layout is changed.

Remaining engineering decisions: compatible firmware/schema allowlist, exact
reconnect deadlines/backoff, whether transient candidate mapping can be tested
without a persistent write, the current-headroom recommendation, and recovery
of saved playback after a size change. Resolve these with the contract spike;
they are not extra product questions for the maintainer.
