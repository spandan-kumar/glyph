# Glance and rotations

Implemented in this checkout, unreleased. Open **Make → Glance**.

- Weather cards use a manually searched place or named coordinates, Celsius
  or Fahrenheit, and the chosen place's local day. No GPS permission.
  The settings disclose that searches and refreshes send place/coordinates to
  Open-Meteo, with Open-Meteo, CC BY 4.0 and GeoNames attribution links.
- Counters count calendar days until/since a date in the **phone's timezone**.
  Card titles alternate with their labels (and, for weather, today's high/low as `H 24 L 17`) on the display; every text scrolls long enough to show its last letters. Today, past dates and future since-dates have explicit labels. Counts update
  at local midnight and follow timezone changes/travel. Counters work offline.
- A **rotation** is a rotation of your cards and looks that plays live from
  your phone. It stores ordered card/library/creation references with
  3–120 second durations, loops, and preserves library parameters, palette
  and speed. It needs the phone. Device Shows (WLED playlists) stay separate
  and run on the device by themselves. Stored data keeps the original `shows`
  key, so older saves load unchanged.
- Cards and rotations use **Show on device**, never Send or a baked GIF.
  Background playback is opt-in per run and never restored after restart.
  Stop, device switching, power off, connection loss and app backgrounding
  without opt-in stop the session. WLED leaves realtime mode, or falls back
  after its realtime timeout when unreachable/process-killed.
- Notification logos overlay a rotation without replacing its effect instance;
  its duration clock pauses during the alert, then resumes. Other media keeps
  following its normal timeline. Mirrored devices keep their base frames.

## Implementation

`GlanceStore` persists `{version: 1, cards, shows}` independently of the weather
cache. Entries it cannot read (newer versions, damage) are kept as raw JSON and
written back unchanged; a file that cannot be parsed at all is copied to
`glance.cards-shows.v1.unreadable` before anything is written. Nothing is
truncated on load (the 24-card / 12-rotation caps apply only when adding), saves
wait for load to finish, and listeners are notified only after a successful
write (a failed write throws and leaves state unchanged).
`WeatherService` owns refreshes outside rendering, shares requests per
coordinates/timezone between owners, and fetches current temperature/condition/
day plus today's high/low every 15 minutes while in use; places due together share one request per
timezone (comma-separated coordinates). With a good cached value failures back
off 15/30/60 minutes; with none, retries come after 10 s, 30 s, 60 s, then every
15 minutes. A 429's Retry-After is honoured; 5xx and timeouts are transient.
Explicit retries have a one-minute floor. Requests identify as
`Glyph/<version> (+repo URL)`; HTTP responses have a 12-second timeout (which
aborts the request), a connection timeout and a 64 KiB limit. The cache is
least-recently-used, and eviction never resets an active backoff. Invalid/missing current fields
never become zero. Optional daily values require Celsius units.

Last good readings are timestamped and cached (up to 32 places). A failed
refresh, or a reading fetched 45 minutes ago, shows stale/OLD (age is measured
from the fetch, not from Open-Meteo's 15-minute observation bucket);
observations or cache aged two hours become unavailable. Unavailable weather and deleted/unsupported
rotation entries are skipped. Entry durations run on the wall clock and do not
count time while an alert has the display. With no available entries, a rotation displays `--`
and retries a bounded scan every three seconds. Deleting a card preserves
rotation references so the editor can expose an unavailable item explicitly.

The pure Dart generators consume snapshots and clock values. Counters use
civil-date arithmetic instead of elapsed 24-hour periods across daylight-saving
changes. The UI reports weather observation time in the phone's local timezone.
Weather data: [Open-Meteo API](https://open-meteo.com/en/docs),
[terms](https://open-meteo.com/en/terms). The free endpoint is suitable for
Glyph's current free, noncommercial distribution; revisit provider terms if
that distribution changes.

## Verification and hardware gate

Automated tests cover local midnight/DST boundaries, leap days, serialization,
invalid fields, response limits, shared refresh, backoff, cache reload/expiry,
rotation order/durations/skips/fallback recovery, alert instance preservation,
background ownership, device switching, connection loss and delayed-request
supersession. Widget tests cover explicit place search, saving cards and editing
mixed rotations at 360 px. Rendering covers 8×8, 32×8, 16×16 and 32×32.

Before release, test on Android and a WLED controller:

1. Snapshot state, presets and configuration; restore them and remove test data
   afterwards. Announce live streams before putting them on the display.
2. Check each supported panel size in bright/dim rooms, including negative
   temperatures, long titles, large counters, stale/expired weather and no data.
3. Verify native device playback returns after Stop, Wi-Fi loss, power off and
   process removal; a different selected device must never receive old cleanup.
4. Run a mixed rotation through a selected-app alert; verify entry duration pauses,
   resumes on the same look, and mirrors remain consistent.
5. Screen-off background playback, notification-monitor coexistence and the
   persistent notification's Stop button. Test denied foreground-service access
   and Android battery restrictions; background availability is best effort.
6. Refresh after airplane mode, travel/timezone changes and local midnight.
   Weather should use the chosen place's day; counters use the phone's day.

Partial Pixel 8/WLED verification was performed on 7 October 2026; see
[device QA](DEVICE_QA_2026_10_07.md). Physical readability, additional panels
and the remaining hardware checks above are still required.
