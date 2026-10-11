# Logo alerts — unreleased implementation

Open **Make → Notifications**, choose apps, optionally set quiet hours,
allow Android notification access, then turn on **Notification alerts**.
The shared permission also enables Now Playing, but permission alone never
starts alerts. All apps are off initially. **Preview on device** uses a
selected app's installed logo without needing an actual notification.

The phone must remain on the device's Wi-Fi. Glyph's foreground notification
keeps monitoring alive even while WLED plays a Saved animation or Show, with
no idle frame traffic. Its **Stop** ends monitoring and live playback.
Removing Glyph from recent apps or killing its process ends the session;
app/quiet-hour preferences persist, but monitoring always starts off.
Android-only; iOS shows that other apps' notifications are unavailable.

## Implementation

- Android `NowPlayingListener` and `NotificationAlertsBridge` share the
  existing permission but use a separate event channel from media sessions.
  No notification extras are read. Only allowlisted package identity,
  notification key, arrival/removal time and 32×32 installed icon RGB cross
  the alert bridge. No message/title/sender/conversation or attached image
  is extracted, stored, logged or sent to a controller.
- The picker queries launchable apps, without `QUERY_ALL_PACKAGES`.
  Icons are obtained from Android, kept in memory, and never bundled in
  Glyph's catalog. A neutral amber bell replaces unavailable icons.
- Ongoing/foreground-service activity, media transport and group summaries
  are filtered before icon work. Updates to a notification key are coalesced;
  removal cancels a queued event. Native key tracking is bounded to 256.
- Dart coalesces bursts per app, keeps at most three waiting events and
  drops arrivals aged 30 seconds or more. Quiet hours support midnight
  and equal endpoints (all day). Stopped/suppressed/offline events are
  discarded; existing Android notifications are never enumerated/replayed.
- A four-second overlay retains the base generator, instance, parameters,
  palette, clock and media feed. The base continues for live playback;
  paused playback stays paused. Only the selected target gets the overlay,
  with the same layout/gamma handling as normal streaming; mirrors retain
  the base frame. Native playback uses a temporary socket and restores
  live mode/realtime override without rewriting a preset, effect or Show.
  WLED controls Show timing; exact position is not promised.
- Device selection/control and playback/stream/suppression generations
  guard asynchronous work. A new user command cancels queued events and
  invalidates restoration. Protected tools/setup/Send own suppression.
  Cancellation during a newer command lets WLED's realtime timeout return
  its own look rather than sending a stale restoration command.

## Verification and release gate

Automated: Flutter tests cover default-off consent, app persistence/search,
quiet hours, icon animation, selected-host pixels, live/native restoration,
bursts/expiry/removal, power/manual takeover/device switch, access revocation,
engine teardown stopping the foreground service, and independent
foreground-service ownership. JVM tests cover
native allowlist/ongoing/media/summary filtering and bounded key tracking.
CI runs analyze, the Flutter suite, Android compilation and native tests.

Before release, test on a physical Android phone and WLED controller:

1. Snapshot `/json/state`, `/presets.json`, `/cfg.json`; use only test-owned
   content, announce the test stream and restore snapshots afterwards.
2. Allow two apps, leave one off. Verify installed logos, readability on
   8×8/16×16/wide devices, four-second timing and no message/app-name text.
3. Test an active live effect, Now Playing while changing songs, a Saved
   GIF and a native Show. Confirm mirrors retain their look, paused
   playback stays paused, and no duplicate Saved entries/files are made.
4. Test a burst, updates/removal, quiet hours across midnight, Draw/import,
   games, guided setup and Send. Suppressed events must not replay later.
5. Lock/screen-off/background; revoke notification access; disconnect Wi-Fi;
   power off, change device or start a new look during an alert. Never
   restore an old look or start frames on a new/off device.
6. Press the foreground notification's Stop, swipe Glyph from recents and
   kill/relaunch its process. Monitoring must remain off until explicitly
   enabled again, even though app choices are remembered.

Partial Pixel 8/WLED verification was performed on 7 October 2026; see
[device QA](DEVICE_QA_2026_10_07.md) for completed checks, bugs fixed and
remaining checks/cleanup. The release gate above is not yet complete.
