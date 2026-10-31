# Glyph outreach plan

Owner: outreach lead (agent), approved by the maintainer. Written 18 October
2026 from four research passes (communities, market, amplifiers, funnel
audit). This file is the plan of record for launch and growth; ROADMAP.md
keeps the product timeline and links here.

## Where we start

- 2 stars, about 50 APK downloads ever, 19 unique repo visitors in 14 days.
  Nothing has been launched publicly. We start from zero, which means every
  first impression is still ours to make.
- The product is far ahead of its shopfront: 1,236 looks, setup wizard,
  live drawing, Now Playing, games, Home Assistant blueprints, a working
  no-device mode. The README hero is a boot logo, numbers disagree across
  documents, screenshots show iPhone chrome, and there is no video of a real
  panel.

## Who needs this (in order)

| # | Audience | Size signal | What they want | Our proof |
|---|---|---|---|---|
| 1 | **WLED matrix owners** | r/WLED ~71k (+27%/yr); 33.9k HA installs run the WLED integration | Content without fiddling; 2D setup that isn't a puzzle | Setup wizard ("which corner lit up?"), 1,200+ looks, Send and it plays alone |
| 2 | **Makers about to build one** | r/esp32 223k (+51%), r/arduino 788k | A reason to build; a $40–80 weekend project that ends somewhere fun | "Build a 16×16, install WLED, Glyph does the rest" |
| 3 | **Home Assistant users** | 607k on r/homeassistant; 704k active HA installs | Local, no-cloud display for alerts and info | Blueprints, Routines, Glance, no account |
| 4 | **FOSS Android users** | r/fossdroid 107k (+41%) | Open, no tracking, F-Droid/Obtainium | MIT, no analytics, Obtainium today, F-Droid in January |
| 5 | **Pixel artists** | r/PixelArt 2.7M | Their art glowing on real hardware | Live drawing on the panel (art-first posts only) |

Not now: Divoom/Tidbyt/Ulanzi owners (no adapter yet), iOS users.

## Positioning

**One line:** *Set up your WLED matrix in three taps, then fill it with
1,200+ original animations. Free, open source, no account.*

**Why this line.** Research found no large open-source rival. Never compare
Glyph with, or criticise, other WLED pixel-art apps in public. WLED 16 ships
PixelForge (image→GIF and scrolling text), so "pixel art for WLED" alone is
not new. What nobody else has is the full journey: a wired-up panel becomes
a finished display, with content and no cloud.

**Have this answer ready** ("how is this different from PixelForge / the WLED
app?"): "Use them too. Glyph is a phone app that sets up the 2D layout for
you, brings a 1,200-look library, draws and plays games live, and puts your
music's album art on the panel. It talks to WLED's normal API, so nothing
else changes."

**Never claim:** first or only; replacing the WLED app; iOS; Pixoo, Tidbyt or
Ulanzi support; "all original art" is now accurate; say *MIT-licensed code; original, CC0 and public-domain art*; tested multi-panel grids or fresh-controller setup until hardware QA
is done.

**Tone:** a maker showing a friend. Author says "I made this" up front.
Video first. Honest limits in every long post.

## Strategy in one paragraph

Fix the shopfront first, because a launch only gets one first look. Then go
where owners already are (WLED forum, Home Assistant community, r/WLED) and
earn feedback and the first real setups. Use that proof for a wider 72-hour
window in maker, Android and FOSS spaces. Then let creators carry it into
the holiday build season, when people buy panels. F-Droid approval becomes
a second launch moment ("now on F-Droid"). Google Play is deferred by the
maintainer (18 Oct); it is where most Android reach is (WLED Native: 100K+
Play installs versus ~4.4K GitHub downloads), so revisit it in January with
the launch results in hand.

## The funnel and what breaks it

| Stage | Today | Fix (before launch) |
|---|---|---|
| **See** a post | No video of a real panel | 3 short clips (below) |
| **Land** on repo/site | Boot-logo hero, requirements far down, contributor links beside Download | README first screen: clip → Download → "Android 7+ · 64-bit · WLED" → "No device yet? Try it anyway" |
| **Trust** | Numbers disagree (1,100+ / 1,200+ / 1,236), iPhone screenshots | One fact sheet; Android screenshots; About text updated |
| **Install** | Release page explains the latest fix, not the app; sideload steps stop at "open it" | Evergreen install block on every release; site with a big download button |
| **First light** | 5.6 s splash; no-device mode hidden behind "Just looking around" | Shorter skippable intro; "Try without a device" |
| **Share** | Share leads to a Discord invite; no artifact | Share sheet with a GIF/clip + caption + link ("Made with Glyph") |
| **Return** | What's new, seasonal picks (good) | Seasonal packs on a calendar; Obtainium/update link in Help |

## Assets we need

| Asset | Who | Notes |
|---|---|---|
| **Clip A, 20 s vertical:** swipe channels, panel changes; Send; phone off; panel keeps playing | Maintainer films | The single most important asset. Original/CC0 art only. Storyboard: `video-storyboard.md` |
| **Clip B, 15 s:** "Which corner lit up?" wiring test → upright arrow | Maintainer films | Lead for r/WLED and the WLED forum |
| **Clip C, 12 s:** album art + progress bar on the panel | Maintainer films | Lead for Shorts/Reels and r/androidapps; creator-owned cover |
| Landing page at `spandan-kumar.github.io/glyph` | Agent | `website/` exists; must ship alongside the catalog files on Pages |
| Android screenshots, feature graphic that says "for WLED" | Agent + phone | Feature graphic done 22 Oct. Screenshots still show iPhone chrome: retake on the Pixel over adb |
| Fact sheet (counts, requirements, tested hardware) | Agent | Single source for every post |
| Channel copy | Agent | `posts.md` |
| Creator kit refresh | Agent | `creator-kit.md` |

Filming tips are in `video-storyboard.md` (dim room, 10–25% brightness,
1/60 s shutter, tripod).

## Calendar

Dates are targets; a gate slips the phase, not the quality bar.

### Phase 0: shopfront (18–28 Oct)

- [x] Sync all public numbers and claims; GitHub About text (22 Oct).
- [x] README first screen; tested/expected/untested hardware table.
- [x] Evergreen install block in `release.yml` notes.
- [x] Deploy the landing page with the catalog on Pages.
- [x] App: "Try without a device", short skippable intro, share sheet with
      caption + link (shipped in 1.4.10, phone-tested 19 Oct).
- [x] **PR to WLED-Docs compatible-software page**: opened 19 Oct as [wled/WLED-Docs#383](https://github.com/wled/WLED-Docs/pull/383) (one alphabetical row, no count). Answer review comments within a day.
      **20 Oct:** WLED maintainers (softhack007, DedeHai) asked for a store
      link instead of sideloading, flagged AI-built code and 16×16-only
      testing, and asked where the animations come from. We moved
      the row to *Sources* with "Tested on a 16×16 panel so far", offered to
      wait for F-Droid, and answered plainly. The large third-party collection
      has since been removed (20 Oct). Lessons: lead with the
      setup wizard, not the count; disclose AI assistance up front; get
      F-Droid live and non-16×16 testers before wide posts.
- [ ] Film clips A–C. Without clip A, Phase 1 moves.
- [ ] Join the WLED Discord now and help in #help for a week before
      mentioning Glyph; ask a mod where project posts belong. Frame the
      WLED-Docs PR as "fills the matrix-app gap, complements PixelForge".
- [ ] Read each target sub's rules by hand (agents can't reach Reddit);
      check r/WLED's top matrix posts of the year.
- [ ] Fresh-ESP32 check before 29 Oct if any spare controller is available;
      otherwise keep saying it plainly in every post.
- [x] No trademarked characters in screenshots, the site, clips or the first
      catalog screen people see (third-party collection removed in 1.4.11).

### Phase 1: owners, creators and vendors (3 – 14 Nov)

Re-dated 31 Oct: nothing went out on 29 Oct, the volunteer footage didn't
arrive, and the maintainer's panel is back on Thu 6 Nov. Clips are filmed on
the maintainer's own panel that day ([panel-day.md](panel-day.md)).

- **Tue 3 Nov (no clip needed):** WLED forum *Projects* post with screenshots,
  the reply in thread 15553, the Apollo email, the QuinLED Discord post, and
  Glyph Discord #announcements ([send-kit-thursday.md](send-kit-thursday.md)
  items 1–4).
- **Wed 4 Nov:** HA community *Share your Projects* + both blueprints in
  *Blueprints Exchange* (marked beta until the live-HA check), after the
  Home Assistant 2026.11 release.
- **Thu 6 Nov: panel day.** Film clips A–C (one look for Diwali), run the
  32×32 / 32×8 / 8×8 live-preview size test, phone-test 1.4.12 over old data,
  then restore the device.
- **Fri 7 Nov:** cut the clips; clip A goes into the README, the site and a
  reply on the forum post; pitch the small channels (Starlit Electronics
  first, then Jason Winfield, MyBritishComputerGuy, an Electriangle comment).
- **Sun 8 Nov, Diwali: r/WLED, the main shot.** Lead with clip A; clip B in
  the body; the size-test results let it say more than "16×16 only". Reply to
  every comment for 48 h.
- **Tue 10 – Thu 12 Nov:** triage feedback and ship fixes; post the size-test
  results on wled/WLED-Docs#383; pitch the mid channels (Smart Home Junkie and
  haus:automation with the Awtrix-alternative angle, DrZzs, Andy Huot,
  ResinChem Tech, Make It Work) with the r/WLED result attached.

### Phase 2: wide window (Tue 17 – Thu 19 Nov), kept small

Three strong venues beat ten thin ones. Budget two hours a day for replies.

- **Tue 17 Nov:** r/homeassistant (*Show & Tell*), r/esp32 (*I made a thing!*).
- **Wed 18 Nov:** r/androidapps (developer format), if replies from Tue are
  under control. r/fossdroid waits for the F-Droid listing (January).
- **Thu 19 Nov:** Hackaday tip (engineering hook: the phone renders every
  frame; the WLED GIF frame-delay quirk).
- **When time allows (not on a date):** r/coolgithubprojects,
  r/FlutterDev with the engineering write-up, Lemmy, Mastodon/Bluesky.
- **Show HN only if a real story emerges** (a creator video, a striking
  build); then a Sunday at 12:00 UTC. WLED-matrix Show HNs without a story
  got 1–3 points.

### Phase 3: the build season (20 Nov – 6 Dec)

People buy panels for Black Friday (27 Nov) and holiday builds. Push the
"$40 weekend build, Glyph does the rest" angle.

- Pitch Chris Maher and Core Electronics with the polished clip and any
  coverage so far.
- Follow up once with creators who haven't replied; send clips to anyone
  who covers it.
- Adafruit blog tip; AlternativeTo listing; r/PixelArt art post (art first,
  app link in a comment).
- "What to build this holiday": a parts list + Glyph, posted to Discussions
  and the forum and used as a reply in Reddit threads.

### Phase 4: second wave (December)

- January: F-Droid resubmission (its three-month rule); "now on F-Droid" for
  r/fossdroid, Lemmy and Mastodon.
- Christmas pack (early Dec), New Year countdown; year-in-review post.
- Next display adapter (AWTRIX NG / Art-Net) gets its own mini-launch.

### Always on

- Reply to every comment within 24 h in launch weeks.
- A seasonal pack + clip a week before each festival.
- Monthly community pack crediting artists; "you asked, we built".
- Answer new "how do I show GIFs / set up a 2D matrix" threads with real
  help (one reply bank in `posts.md`).
- Keep the 13 good-first-issues fresh for Hacktoberfest-style contributors.

## Distribution

| Channel | Role | Status |
|---|---|---|
| GitHub Releases + Obtainium | Trust, early adopters | Live |
| F-Droid | FOSS trust, r/fossdroid post | MR !53046 closed 19 Oct (needs three months of history); resubmit ~3 Jan 2027 |
| Google Play | Reach | Deferred by the maintainer (18 Oct); revisit January 2027. $25, ID verification, 12 testers × 14 days for new personal accounts; check the notification-listener policy before submitting |
| Landing page | Search, non-GitHub visitors | Built, undeployed |

Google's developer verification is enforced only for store installs in four
countries so far; sideloading is untouched until a 2027 global rollout, when
registering the package and signing keys will be needed to stay installable.

**Decisions taken (18 Oct):** no Play Store for now; maintainer films clips
A–C by 25 Oct; headline "1,200+ original animations", setup wizard leads (footage
uses only original/CC0 art); landing page at the GitHub Pages root alongside the catalog.

**20 Oct:** removed animations that weren't original, CC0 or public domain
from all public builds; the library is 1,236 looks.

**22 Oct:** F-Droid is out until January (its three-month rule), and a WLED
maintainer said they only install from Google Play. The maintainer kept Play
off for now; r/fossdroid moves to the F-Droid launch in January. Clips A–C
by 25 Oct keep r/WLED on 31 Oct. The virtual size test on the maintainer's
panel is approved.

## Product-led growth (build in this order)

1. **Share with caption + link** from creations and the Stage (S).
2. **Setup postcard:** after setup, a shareable image of the panel size and
   first look, no network details (S–M).
3. **Stage loop export to GIF/MP4** for Reels/Shorts (M–L). Short-form is
   where pixel-LED clips reach millions; let users make them.
4. **Look recipes / remix packs** with creator credit (M).

## Metrics (public counts only; no analytics, ever)

The numbers that matter for a niche hardware app are gatekeeper wins and
real setups, not stars. Check weekly; log every post in
`docs/launch/results.md` (date, venue, link, comments, then GitHub traffic and
download deltas for the following 7 days).

| Weekly check | 30 days | 90 days |
|---|---|---|
| **Creator videos** (published) | 1 | 3 |
| **Vendor/doc links landed** (WLED docs, kit makers) | 2 | 5 |
| **Setups shared** (Discord, Discussions, Reddit) | 10 | 40 |
| Issues from real hardware | 10 | 30 |
| Downloads (GitHub + F-Droid; Obtainium undercounts) | 400 | 2,000 |
| Stars | 100 | 400 |

Tronbyt got a Hackaday article and has 221 stars, so these are deliberately
modest. One creator video is worth more than every post combined.

## Rules of engagement

- The maintainer approves every public post, email and PR before it goes
  out. Agents draft; humans send.
- One post per venue per launch; no cross-posting the same text on the same
  day across overlapping subs.
- Say "I made this". Disclose limits. Never argue with critics; thank them,
  fix it, report back.
- AI assistance: never hidden, never the headline; answer plainly if asked
  (F-Droid MR already discloses it). Skip venues that ban AI-assisted
  projects.
- The thing most likely to blow up a thread is "it didn't work on my grid".
  Invite it and fix it in public. If asked where the animations come from:
  original, CC0 or public domain (reply bank).
