# Panel day: Thu 6 Nov 2026

One session with the 16×16 display back on the network: film the launch
clips, run the size test promised on wled/WLED-Docs#383, phone-test the
latest release, then put the device back exactly as it was. Order matters:
film first while the layout is the real one.

## 0. Before anything (agent)

- Discover the display on the LAN (sweep `/json/info`; don't hardcode the IP;
  sandboxed `curl` can't reach the LAN here).
- Snapshot `/json/state`, `/presets.json`, `/cfg.json` and the file list into
  the scratchpad. Nothing changes on the device before this.

## 1. Film (maintainer, about 45 minutes)

Setup and camera settings: [recording-brief.md](recording-brief.md); shot
timings: [video-storyboard.md](video-storyboard.md). Latest release on the
phone, Do Not Disturb on, brightness 10–25%, tripod, locked exposure.

| Clip | What | Looks to use |
|---|---|---|
| **A** (20 s, most important) | Swipe the Stage 2–3 times → tweak a knob → **Send** → phone off → panel keeps playing for 10 s | Ocean Plasma, Hyperdrive, then **Diwali Fireworks** or **Diya Glow** for the Send (8 Nov is Diwali) |
| **B** (15 s) | Device → Set up display → wiring questions → upright arrow check | (setup frames) |
| **C** (12 s, optional) | Make → Now Playing with a cover you may show; or a Glance weather card | — |

Film vertical and landscape; keep 2 s before and after each action. Copy
the raw files somewhere the agent can read (e.g. `~/glyph-clips/`).

## 2. Size test (agent, about 45 minutes, asks before each change)

softhack007's method: WS281x output is send-only, so set the output's LED
count and a matching 2D layout, then watch WLED's live preview (the star
icon); keep it at most 1,024 LEDs; "use main segment only" in Sync settings
may be needed.

For **32×32, 32×8 and 8×8**: set the layout (`/settings/2D`, see
AGENTS.md), then stream two looks and Send one GIF from the phone, and
capture the live preview. Note orientation, scaling and anything wrong.
Results go to `docs/QA_VIRTUAL_SIZES.md`.

## 3. Phone test (agent)

With the phone on adb: install the latest release over the current app and
check favourites, Rotations and recents that pointed at removed looks are
skipped cleanly (no crash, no broken tiles). Also try the first-play
"Can't see it?" path if the display can be made unreachable briefly.

## 4. Restore (agent)

Put back the snapshot's config and presets, delete only files the tests
created, and confirm a zero diff against the snapshot before calling it done.

## 5. Same day or Friday

- Cut clip A (and B); put clip A in the README and the site.
- Add a forum reply with clip A under the 3 Nov Projects post.
- Send the small-channel pitches ([send-kit-thursday.md](send-kit-thursday.md), Friday section).
- Draft the size-test comment for wled/WLED-Docs#383.
