# Glyph UX — "Lightbox"

Before Lightbox, the app was a tabbed catalogue: grid of cards → bottom
"now playing" bar → sheet. The current app uses the Stage, channels and
studio described here because there is a **physical object** in the room.
It should feel like a remote for a beautiful lamp. Reconciled for v1.3.1 on
7 October 2026; these journeys express intent, not proof that every gesture
or animation below is implemented. See [the engineering plan](../PLAN.md)
for shipped scope and upcoming live information work.

> **v1.2 naming:** the destinations are **Display** (was Tune), **Make** and
> **Device** (was Matrix). User-facing copy says *device*, not *matrix*;
> "Keep" is now **Send** (to device) and kept items are **Saved**. Geometry is
> sharp: rectangles with 1–3 px radii; only LED dots and rotary knobs are
> round.

**North star:** *the matrix is the hero; the phone is its remote.* Every
screen keeps the matrix visible, every action shows up on it instantly, and
the app's own light comes from what the matrix is showing.

---

## 1. Who and why

| Person | Moment | What they want |
|---|---|---|
| New owner | Just flashed WLED, panel on the desk | "Make it do something cool, now." |
| Evening user | On the sofa | Flip through looks until one fits the mood. |
| Maker | Has an idea | Draw / write / bring a GIF and see it live. |
| Host | Friends over | Party mode, music reacting, a game. |
| Set-and-forget | Wants it to just run | Send favourites to the device, routines by time of day. |

## 2. Journeys and aha moments

### J1 — First run (target: something on the matrix in < 30 s)
1. **Welcome.** Full-black screen; the word *glyph* assembles itself out of
   LED dots (our pixel font), one line: "Your matrix, alive." → **Find my
   device**. Secondary: *Just looking around* (browse without hardware).
2. **Searching.** A slow radar sweep drawn in LED dots. Found devices appear
   as small glowing panels with their names. If none in ~6 s: "Can't see it?"
   → enter address / scan / help copy (same Wi-Fi, WLED 0.14+).
3. **Connect → AHA #1 "Hello".** The device plays the Glyph intro,
   mirrored on the phone. Copy: **"Look up."** Buttons: *Looks right* /
   *Something looks off*.
4. *Something looks off* → **Guided fix**, no jargon: show a big arrow on the
   matrix and ask "Which way is the arrow pointing?" (4 big arrow buttons) then
   "Is it mirrored?" — we set rotation/flip from the answers and re-test.
5. **Pick a first vibe.** Three big live tiles: *Calm*, *Party*, *Classic*.
   Tapping plays it immediately on the matrix → lands on Display with that
   channel first. Onboarding is never shown again (stored flag); reachable
   from Device → "Add a device" (search and orientation check).

### J2 — Evening flip-through (core loop)
- Home = **Display**. The **Stage** (a faithful live mirror of the matrix, with
  LED bloom) sits at the top.
- **AHA #2 "Channel surf":** swipe left/right on the Stage → next/previous
  animation in the current channel, instantly on the matrix, with a haptic
  tick and the title sliding in like a TV channel caption. A subtle "‹ swipe ›"
  hint shows the first two times only.
- **AHA #3 "The room glows":** the whole app background is lit by the colours
  currently on the matrix (sampled from the frame, smoothed). Fire = warm
  room; ocean = cool room. Nothing else in the UI is coloured by default.
- Below the Stage: **Channels** — horizontal rails (not one big grid):
  *Right now* (time-of-day + season picks), *Famous Classics*, *Pixel Pals*,
  *Calm*, *Party*, *Space*, *Your favourites*, *Made by you*, …
  Tapping a tile **tunes in** (tile → Stage transition), and the channel
  becomes the surf order.
- Scrolling down collapses the Stage into a **mini-stage** pinned at the top
  (live thumbnail, title, ‹ ›). There is no bottom "now playing" bar.
- **Search** lives behind a search glyph at the top (and pull-down). Results
  are instant; suggestion tokens are moods ("cozy", "spooky", "space").
- **AHA #7 "Surprise me":** dice button (and shake the phone) — LED
  slot-machine shuffle on the Stage, lands on a random pick.

### J3 — Make it mine
- Tap the title under the Stage → **Tweak** panel slides up (Stage stays
  visible above it). Looks like the control surface of a synth:
  - **Colour**: a strip of palette chips you swipe through; the matrix
    changes as each centres (AHA #4).
  - **Knobs**: one rotary knob per parameter (speed, density, …) with
    detent haptics; drag up/down or around to turn.
  - **Brightness**: one fader.
- Changes stream live. No "apply" buttons.

### J4 — Send it (set-and-forget)
- **Send** stays reachable in the collapsed Stage while browsing. The compact
  control shares the full Stage's status and is hidden when disconnected,
  unsupported or playing a live-only look.
- Sending checks the baked GIF first. Identical content already saved on the
  device says **“Already on your device”** with **Play it**; it leaves playback
  alone and has no upload or beam. Changed content still sends.
- **Send** button (under the Stage) → **AHA #5 "Beam":** dots stream from the
  phone Stage up into a small device glyph; it lights; toast: **"Sent to your
  device. It keeps playing without your phone."**
- **Show it off** opens Discord after the first new Send, then only after both
  ten more new Sends and a week. This policy survives app restarts; unchanged
  re-sends never invite.
- Device tab shows what lives on the matrix as **"Saved"** tiles, groups them
  into **Shows** (playlists: "plays one after another") and **Routines**
  (schedules written as sentences: *"Weekdays at 7:00 → Sunrise"*).
  The system intro stays hidden. A chosen power-on look remains editable and
  runs after the intro; devices without one offer “Choose a power-on look”.
- Never say preset, segment, DDP, realtime, FS, effect id in primary UI.
  (Advanced details can live behind "Details".)

### J5 — Create
- **Make** is a studio, not a menu: big live tiles that *demo themselves*
  (the Draw tile shows a pixel being drawn, Write shows scrolling text, Clock
  ticks, Music bars bounce, Play shows Snake…).
- **AHA #6 "Draw live":** when a matrix is connected, live mirror is ON by
  default — the first stroke appears on the matrix immediately, with a tiny
  "on your device" pulse next to the canvas.
- *Made by you* appears as a rail on Display too.

### J6 — Party
- *Party* channel, Music (visualiser), Play (games) are one tap away from
  Make. Music shows "Listening…" with a live level ring; games go full-screen
  with the matrix mirror on top.

## 3. Information architecture

```
Onboarding (first run only)
└─ Shell: floating Dock — [ Display ] [ Make ] [ Device ]
   ├─ Display  Stage + transport + Channels; Search; Tweak panel
   ├─ Make     Studio tiles (Draw, Write, Clock, Timer, Bring a GIF, Music,
   │           Now Playing, Play)
   │           + Made by you
   └─ Device   Device hub: the panel, power, brightness, Saved / Shows /
               Routines / Storage, switch device, layout fix, rename, group
```

The Dock is a small floating island: a centred, sharp-cornered panel with
a blurred background and shadow. Tab names are drawn in Glyph's LED pixel
font; the active tab sits on a raised block with a lit underline in the
room colour that slides between tabs.

## 4. Visual language

**Concept:** a dark room with a light source. Matte warm-black surfaces, thin
hairlines like an instrument panel, type that feels printed on hardware, and
colour that comes only from the LEDs.

### Colour tokens (`lib/ui/design/tokens.dart`)
| Token | Hex | Use |
|---|---|---|
| `ink` | #0B0A09 | app background (under the ambient glow) |
| `panel` | #131210 | panels, sheets |
| `raised` | #1B1917 | controls, knobs, chips |
| `line` | #2B2723 | hairlines, borders (1 px) |
| `text` | #F3EFE8 | primary text |
| `text2` | #A39C91 | secondary |
| `text3` | #6B655C | tertiary, labels |
| `ledOff` | #1D1A17 | unlit LED dots |
| `phosphor` | #FFB547 | fallback accent (warm amber) when nothing plays |
| `ambient` | dynamic | sampled from the current frame |
| `danger` | #FF6A5C | destructive |
| `ok` | #7BE0A0 | connected/success dots |

No purple→cyan gradients. No coloured card backgrounds. Accent colour for
active controls = current ambient colour (falls back to phosphor).

### Type
- **Display/titles:** Bricolage Grotesque, optical size 48–72, weight 700–800,
  width 85–90 (slightly condensed), tight tracking (−1 to −2%).
- **Body:** Bricolage Grotesque opsz 14, weight 400–500.
- **Labels/metadata:** DM Mono, 11–12 px, UPPERCASE, +8% tracking, `text3`.
- **LED headings:** channel names and big numbers rendered as lit dots with
  our bitmap fonts (`LedText`), e.g. section titles on Display.

### Shape, depth, motion
- Radii: 2 (controls, panels), 3 (sheets), 1 (LED tiles). Everything reads
  as crisp rectangles — the pixel grid is the motif. Only LED dots, status
  dots and rotary knobs are round.
- Depth via hairlines and slightly lighter surfaces, not drop shadows.
  The only "glow" in the app is LED bloom and the ambient backdrop.
- Motion: 180–260 ms, `Curves.easeOutCubic` / emphasized; Stage transitions
  feel physical (tile flies to Stage; channel captions slide).
- Haptics: `selectionClick` on channel change & knob detents,
  `lightImpact` on Send, `mediumImpact` on Surprise landing.

### Voice
Short, warm, second person. "Look up." "Sent to your device." "Can't see it?"
Labels are verbs: Display, Make, Send, Draw, Write, Bring a GIF, Play.

## 5. Component kit (`lib/ui/design/`)
- `tokens.dart`, `type.dart` (text styles), theme in `lib/ui/theme.dart`.
- `Stage` — the hero LED panel: realistic dots, bloom, bezel, optional
  device label + status dot; supports `onSwipe(int dir)` and `onTap`.
- `AmbientBackdrop` + `AmbientController` — samples the playback frame
  (~6 Hz), smooths colour, paints a soft radial light behind everything.
- `LedText` — text drawn in LED dots with our bitmap fonts.
- `LedTile` — square animation tile (live preview) + mono caption; no card.
- `Knob` — rotary control with detents/haptics; `Fader` — vertical/horizontal.
- `Dock` — floating 3-item nav.
- `MonoLabel`, `GlyphButton` (primary = filled `text` on `ink` or ambient
  outline; secondary = hairline), `Hairline`.

## 6. Original Lightbox revamp boundaries

These bounded the original UI work. The upcoming playback, notification
and Glance changes are scoped in [PLAN.md](../PLAN.md).

- No changes to engine, WLED, playback or storage logic beyond small hooks.
- Feature internals (editor tools, games, etc.) keep working; they are
  restyled to the new kit, not rebuilt.


## Notifications (next release)

Make → Notifications uses the studio's Lightbox panels, sharp toggles and
LED preview. Start with every app off. Pick installed apps by name/icon,
optionally set quiet hours, grant the shared Android notification access,
then explicitly enable monitoring while Glyph is visible. App names stay
in this settings screen. The device gets only a bouncing installed logo for
four seconds, then returns to its live or native playback.

The preview uses a selected app's logo and needs no incoming notification.
Monitoring needs the phone on the device's Wi-Fi and the foreground service;
its Stop button ends both monitoring and live playback. Removing Glyph from
recent apps ends the session. Persist app selections and quiet hours, never
persist or auto-resume monitoring. Report unavailable access, a disconnected
listener or device, and quiet hours clearly. Drawing, games, setup, import
and Send suppress alerts; mirrored devices retain their base look.


## Glance and phone Shows (next release)

Make → Glance holds locally saved Weather and Days counter cards, plus Shows
that mix cards, library looks and creations. Cards preview on LED panels before
playback. Weather has explicit place search/manual coordinates, Celsius/
Fahrenheit, timestamped readings and clear OLD/unavailable states. Disclose
Open-Meteo requests before search; provide provider/data attribution. Counters
use the phone timezone only, with Until/Since and a civil date.

Use **Show on device** and **Needs your phone** for live cards/Shows, with a
visible background toggle (off per run). Show order, duration and unavailable
references are editable. Device → Shows labels its existing autonomous Shows
**Runs on your device** and links to phone Shows. Never convert a device Show
or claim a live counter can be sent as a self-updating GIF. Alert logos pause
phone-Show durations, then resume the same instance. See [Glance QA](../GLANCE.md).


## New animations (next release)

Glyph menu → New animations explains the static catalog host and offline
availability, shows the last check/content revision, and offers **Check for
new animations**. **Daily automatic checks** is off by default; enabling it
allows one check per 24 hours while Glyph is open, including on resume when
due. A failure keeps the library available and waits until the next daily
check; manual retry remains available. No background service or alerts.

Updates refresh rails, open channel pages, search and phone-Show pickers.
Keep the selected channel, favourites/recents, active generator and its
palette/parameters. Show compatible content with an optional skipped-entry
details sheet. Disclose that Glyph sends no device details, notifications
or analytics. A build without a configured host explains that catalog
delivery is being prepared and keeps the bundled library available.
