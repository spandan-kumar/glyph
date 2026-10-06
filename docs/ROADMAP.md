# Glyph roadmap & launch plan

Glyph is a free, open-source (MIT) community project. Success = people
using it, starring it, sharing their setups and contributing art and code.
This plan merges product and marketing into one timeline, ordered for the
most reach and community, based on research (October 2026) into what
pixel-display owners want, which displays they own and where they talk.

**Strategy in one paragraph.** Soft-launch now to the core WLED audience
with what already exists (it's the strongest app in that niche) and use
their feedback to shape v1.4. Ship v1.4 with the features that make great
videos for *bigger* audiences — notifications, weather, planes overhead —
plus a setup wizard so the influx of newcomers doesn't bounce. Big launch
with v1.4 in Diwali/Halloween season. Then add a new display every few
weeks (AWTRIX, Divoom, Tronbyt); each one is a fresh launch into a new
community. Everything is local, private and free — that's the story.

---

## 1. Positioning

**Tagline:** *Your LED matrix, alive — 1,100+ animations, pixel art, clocks,
games and your music's album art, from your phone. Free, local, no account.*

**Audiences, in priority order**

1. **WLED matrix owners** (16×16, 8×32, 32×32, HUB75) — have hardware, want
   content without fiddling. Core.
2. **Makers about to build one** (ESP32/Arduino crowd) — Glyph is a reason
   to build a matrix.
3. **Home Assistant users** — want info and alerts on a pixel display.
4. **Other pixel displays** — AWTRIX/Ulanzi TC001, Divoom Pixoo,
   Tidbyt/Tronbyt, iDotMatrix — as adapters ship.

**Lead with proof, not adjectives**

| Claim | Show it |
|---|---|
| Content no one else has | Scroll the library; 1,163 animations, public-domain classics (1928 Steamboat Willie, The Starry Night) |
| Album art on your matrix | Spotify plays → cover appears with a moving progress bar |
| It just works | Plug in, app finds the device, first animation in seconds |
| Works on any ESP | The phone renders; even an ESP8266 streams 40 fps |
| Local, no account | vs Divoom/LaMetric accounts and Tidbyt's shutdown |
| Free forever | MIT, no subscription (vs Pipplee's) |

Tone: a maker showing a friend something cool. Short, visual, honest.

**Competition.** WLED 16's built-in PixelForge (browser paint/GIF/text) and
Pipplee (~1k Android installs, $2.50/yr) cover basic editing and GIFs, so
Glyph differentiates on content, glanceable info and multi-display support.

---

## 2. What people ask for

Ranked from forum, Reddit and GitHub evidence.

| # | Need | Who | Glyph |
|---|---|---|---|
| 1 | Notifications / smart-home values on the display | AWTRIX, WLED, Pixoo | gap → v1.4 |
| 2 | Weather (now, forecast, air quality) | Tidbyt, AWTRIX | gap → v1.4 |
| 3 | Planes overhead (top Tidbyt request) | Tidbyt | gap → v1.4 |
| 4 | Sports scores | Tidbyt | skipped (free APIs keep dying) |
| 5 | Matrix setup/mapping is confusing | WLED | partial → v1.4 wizard |
| 6 | Local, no cloud, no account | Pixoo, LaMetric, Tidbyt | yes |
| 7 | Easy custom pixel art | WLED | yes |
| 8 | Now Playing album art | Tidbyt, Pixoo | yes |
| 9 | Content rotation with a UI, not YAML | WLED, Tidbyt | partial (Shows) → Glance cards in Shows |
| 10 | Counters (days until/since) | Tidbyt, AWTRIX | partial → v1.4 |
| 11 | Busy light, night modes | Tidbyt, AWTRIX | partial (Routines) → notifications |
| 12 | Stocks/crypto | Tidbyt | gap → v1.4 |
| 13 | Calendar, transit, RSS | Tidbyt | later |
| 14 | Non-Latin text | AWTRIX, WLED | gap → 2027 |
| 15 | Ambient scenes | Tidbyt | yes |

---

## 3. Feedback channels and how they connect

No backend: everything routes to GitHub and one Discord, and the app links
straight into them.

| Channel | Purpose | Integration |
|---|---|---|
| **In-app "Send feedback"** (Device tab, and after errors) | Bug reports and ideas from people who'd never find GitHub | Opens a prefilled GitHub issue form in the browser with app version, phone model, WLED version, panel size and the last error; the person sees everything before sending. Fallback: copy diagnostics to share anywhere. |
| **In-app "Suggest an animation"** | Content requests | Opens the *Animation request* issue form |
| **In-app "Share your setup"** | Social proof | Opens Discussions *Show your setup*; also the system share sheet with a clip of the stage |
| **In-app "What's new"** | Close the loop | Release notes shown once after each update, crediting contributors and "you asked, we built" items |
| **GitHub Issues** (forms: bug, animation request, display support request) | Tracked work | Labels drive release notes; 👍 on display requests = demand voting |
| **GitHub Discussions** (Show your setup, Ideas, Q&A, Announcements) | Community, voting, support | Ideas sorted by 👍; top ideas promoted to issues monthly |
| **Public roadmap** (GitHub Project board) | Transparency | Ideas → Planned → Building → Shipped; linked from README and the app |
| **Glyph Discord** | Real-time help, showcase, testers | #announcements, #show-your-setup (forum), #help, #ideas, #beta-testers, #github-feed (webhook: releases, issues, PRs); linked from app and README |
| **WLED Discord/forum, r/WLED** | Where users already are | Monitor weekly; answer and point to issues |
| **Play / F-Droid reviews** | Public sentiment | Reply to every review; bugs become issues |

**Loop cadence (sustainable solo):**

- Daily in launch weeks, then 3×/week: triage issues, reply on Reddit/Discord.
- Weekly: label and prioritise; short #announcements update.
- Monthly: promote top ideas to the roadmap; ship a community animation
  pack crediting artists; post "you asked, we built".

---

## 4. Timeline

Starting Monday 5 October 2026.

### Week 0 — Launch-ready (5–11 Oct)

Blockers:

- [ ] Add the **MIT LICENSE**.
- [ ] **Release signing** (keystore in CI secrets); the APK is debug-signed today.
- [ ] Register for **Android developer verification** (sideload checks roll
      out 2026–27).

Repo & community:

- [ ] README: hero GIF (matrix + phone), badges (release, license, Obtainium),
      "works with" list (WLED versions, panel sizes, HUB75 via WLED's HUB75
      builds), links to Discord, Discussions and the roadmap board.
- [ ] Social preview image (1280×640); GitHub topics: `wled`, `led-matrix`,
      `pixel-art`, `ddp`, `flutter`, `esp32`, `home-automation`.
- [ ] `CONTRIBUTING.md` with a 5-minute "add your sprite" guide; issue forms
      (bug, animation request, display request); PR template; 10–15
      `good first issue`s (sprites, festival packs, translations, fonts) —
      13 open: #7–#19.
- [x] Discussions on. Glyph Discord: https://discord.gg/9EeCFZAFvk
- [x] Public roadmap board: https://github.com/users/spandan-kumar/projects/4
- [x] Discord webhooks (#announcements for releases, #github-feed for
      issues, PRs, stars).
- [ ] In-app feedback links: Send feedback, Suggest an animation, Share your
      setup, What's new.
- [ ] CI (analyze + test on PRs) and tag → signed release with sha256.

Assets:

- [ ] Hero video 30–45 s (vertical + 16:9) and feature clips (Now Playing,
      swipe channels, draw live, a game, boot intro). Film in a dark room at
      a slow shutter so LEDs don't flicker; a diffuser photographs better.
- [ ] Technical blog post: phone-side rendering, DDP, the WLED GIF timer bug.
- [ ] One-page creator kit: what it is, 3 clips, links, contact.
- [ ] Start the **Play closed test** (new personal accounts need 12+ testers
      opted in for 14 consecutive days).

### Week 1 — Soft launch to the core (12–18 Oct)

- [ ] **Tue 13 Oct: r/WLED** (~52k) video post (draft below). Reply to every
      comment for 48 h. Ask for Play testers and non-16×16 feedback.
- [ ] PR to the **WLED docs compatible-software list** (kno.wled.ge,
      `wled/WLED-Docs`): permanent, high-intent traffic.
- [ ] **WLED forum** (*Projects* and *Integrations*) and the WLED Discord.
- [ ] Fix what people report; ship **1.3.x** within the week.

### Weeks 2–3 — Build v1.4 "glance" (19 Oct – 1 Nov)

In this order; each one is a clip for the big launch:

1. **Halloween + Diwali packs** (release Thu 22 Oct as 1.3.x, clips Sat
   24 Oct) and a Routine that rotates seasonal packs automatically.
2. **Notifications on the matrix** — Notification access is already granted
   for Now Playing. App icon + short scroll for chosen apps (messages,
   calls, calendar, doorbell), then back to what was playing. Per-app
   filters, quiet hours.
3. **Glance cards** — weather (Open-Meteo, no key), days-until, crypto
   (CoinGecko), sunrise/sunset, moon phase; standalone or timed items in Shows.
4. **Planes overhead** — nearest aircraft from a free ADS-B feed
   (adsb.lol / airplanes.live): callsign, route, altitude. Best demo clip.
5. **Panel setup wizard** — presets (8×32, 16×16, 32×32, 64×32 HUB75,
   custom), start corner, serpentine, N×M tiling, live corner/arrow test
   pattern; writes WLED's 2D config (snapshot + restore). Stops newcomers
   bouncing during the big launch.
6. **Home Assistant blueprint** — "Use in Home Assistant" lists Saved looks'
   IDs; a blueprint triggers them from automations.

Apply for **Play production** when the 14-day closed test completes
(~27 Oct).

### Week 4 — Big launch with v1.4 (2–8 Nov)

One 72-hour window, **Tue 3 – Thu 5 Nov** (a cluster can reach GitHub
Trending):

- [ ] **r/homeassistant** (~388k) + HA forum *Share your Projects*: lead with
      notifications, weather, the HA blueprint, local-only.
- [ ] **r/esp32** (~109k), **r/arduino** (~767k), **r/led**: lead with how it
      works (phone renders, DDP, any ESP).
- [ ] **r/androidapps** (~560k): screenshots + clip.
- [ ] **r/FlutterDev** (~155k): the technical write-up.
- [ ] **Hackaday tip** (tips@hackaday.com): draft below.
- [ ] **Show HN**: weekday morning US time, with the blog post.
- [ ] **awesome-flutter** PR (`SOURCE.md`, bottom of the category, with a GIF).
- [ ] **F-Droid** submission with an honest AI-assistance disclosure
      (F-Droid's interim policy allows reviewed AI help; IzzyOnDroid doesn't,
      so skip it). Obtainium badge already live.
- [ ] **Sun 8 Nov: Diwali** clip on r/WLED and Discord.

### Weeks 5–6 — Amplify (9–22 Nov)

- [ ] Pitch **5 YouTubers** (WLED/Home Assistant/maker space, e.g. DrZzs, The
      Hook Up, Everything Smart Home, QuinLED, Andreas Spiess, Core
      Electronics, Adafruit) with the creator kit. One video beats everything.
- [ ] **r/PixelArt** (2.7M): art made in Glyph on a real matrix; app link only
      in a comment.
- [ ] First **monthly community pack** + "you asked, we built" post.
- [ ] Triage launch feedback onto the board; ship 1.4.x fixes.

### Weeks 7–9 — v1.5 "AWTRIX" (23 Nov – 13 Dec)

- [ ] Generic **Art-Net / E1.31 sender**, then **AWTRIX NG** on Ulanzi TC001
      (Art-Net live on UDP 6454, GIF upload to `/ICONS`, mDNS
      `_awtrixng._tcp`). Also covers ESPHome E1.31 matrices and DIY controllers.
- [ ] **Christmas pack** (early Dec).
- [ ] Launch to the AWTRIX/Home Assistant crowd (HA forum, AWTRIX GitHub
      discussions) and a r/homeassistant follow-up.

### Weeks 10–12 — v1.6 "Pixoo" (14 Dec – 3 Jan)

- [ ] **Divoom Pixoo 64/16** — HTTP `Draw/SendHttpGif` upload (16/32/64 px,
      < 60 frames, loops on its own); upload only (live is ~1 fps).
- [ ] **New Year countdown** pack; year-in-review post (stars, contributors,
      community art).
- [ ] Launch to Divoom owners (Pixoo HA integration threads, Divoom subreddit).

### Q1 2027 — Wider and deeper

- [ ] **Tronbyt** (Tidbyt replacement): push animated WebP to a self-hosted
      server (`POST /v0/devices/{id}/push`); needs a Dart WebP encoder. Launch
      in r/tidbyt and Tronbyt GitHub.
- [ ] **Share & import creations** + a curated **Community shelf** fed by
      GitHub PRs through the remote catalog.
- [ ] **Home Assistant entity watcher** (URL + token → Glance cards/alerts).
- [ ] **Non-Latin fonts** (Devanagari, Cyrillic, …).
- [ ] **iDotMatrix BLE** panels (experimental).
- [ ] **Live matrix preview in the browser** (idea): share a link that shows
      your matrix live in any browser, streamed peer-to-peer from the phone
      with PeerJS/WebRTC — no Glyph server, a static viewer page draws the
      LED dots. For showing friends, people without hardware, embeds.
- [ ] **iOS** build.

Not planned: AI image generation (paid cloud keys), sports scores (fragile
APIs), web/desktop (PixelForge covers the browser).

### Always on

| Cadence | Do |
|---|---|
| Every 2–3 weeks | Release with GIFs in the notes; repost where it landed well |
| Each new display | Its own mini-launch in that community |
| A week before festivals | Seasonal pack + clip (Halloween, Diwali, Christmas, New Year, Holi, Eid…) |
| Monthly | Community pack, ideas review, "you asked, we built" |

---

## 5. Channel playbook

- **Reddit:** video first, phone in shot, "free and open source" in the
  title, links in the body, reply fast. Check each sub's rules on the day.
  r/selfhosted only allows projects under 3 months old on *New Project Friday*.
- **Forums (WLED, Home Assistant):** longer and technical: how it works,
  what's next, ask for feedback.
- **Hackaday / Hacker News:** lead with the engineering (phone-side
  rendering, LED colour accuracy, the WLED GIF timer bug).
- **YouTube creators:** short personal email: why *their* viewers care, the
  hero video, the repo. Five good pitches, not fifty.
- **Distribution:** GitHub Releases + Obtainium now; Play (closed →
  production); F-Droid.

---

## 6. Metrics

Public counts only — Glyph has no in-app analytics and stays that way.

| Metric | Source | 30 days | 90 days |
|---|---|---|---|
| GitHub stars | repo | 300 | 1,000+ |
| Downloads | release assets + Play | 500 | 3,000 |
| Discord members | Discord | 100 | 400 |
| Contributors (art + code) | merged PRs | 3 | 10 |
| Setups shared | Discussions + Discord | 10 | 40 |
| Feedback → shipped | issues closed with `community` label | 5 | 20 |

Targets are guesses for a niche project; watch which channel moves the
numbers and double down there.

---

## 7. Automations

1. CI on every PR: `flutter analyze` + `flutter test`.
2. Tag `v*` → signed split APKs + sha256 on a GitHub release (replaces
   committing APKs to `release/`).
3. Release notes from PR labels (`.github/release.yml`): *New animations*
   crediting artists, *Community requests* crediting reporters.
4. On release published: post notes + a clip link to the Glyph Discord,
   Mastodon and Bluesky.
5. GitHub → Discord #github-feed webhook (issues, PRs, releases).
6. `fastlane/metadata/android/en-US/` shared by Play and F-Droid; CI checks a
   changelog exists for each versionCode; Play closed-track upload from the tag.
7. Dependabot for `pub`, `gradle`, `github-actions`.
8. Issue forms + PR template; auto-label `community` on issues opened from
   the in-app feedback link.

---

## 8. Ready-to-post drafts

### r/WLED (soft launch)

> **I made a free, open-source app for WLED matrices — 1,100+ animations,
> album art from Spotify, games, pixel editor**
>
> [video]
>
> I wanted my 16×16 matrix to feel alive without fiddling, so I built Glyph.
> Your phone draws every frame and streams it, so it works on any ESP
> running WLED, or it saves animations to the device so they play without
> the phone.
>
> - 1,100+ original animations, plus public-domain classics (1928
>   Steamboat Willie, The Starry Night)
> - Now Playing: your music's album art with a progress bar
> - Pixel editor that draws live on the matrix, scrolling text, clocks that
>   run on the device
> - Music visualiser, 7 games with your phone as the controller
> - Shows and schedules that run without your phone
> - Local only: no account, no cloud. MIT licensed.
>
> Android APK: [release] · Code: [repo] · Discord: [invite]
>
> Would love feedback, especially from people with non-16×16 panels. Want to
> help get it on the Play Store? I need testers — reply or DM.

### Hackaday tip

> **Subject:** Open-source phone app renders every frame for any WLED LED
> matrix (and found a WLED GIF timing bug)
>
> Glyph is a free Android app that turns a cheap WS2812B matrix into a pixel
> display: the phone renders and streams frames over DDP, so even an ESP8266
> runs 40 fps animations, games, live album art and planes flying overhead.
> While building it we found WLED's GIF player carries one file's frame
> timer into the next, blanking the display for minutes; the app works
> around it. Video: […] Code (MIT): […]

### Show HN

> **Show HN: Glyph – open-source phone app that turns a $15 LED matrix into a
> pixel display**
>
> First comment: why phone-side rendering (any ESP, one engine for previews
> and LEDs), the stack (Flutter, pure-Dart engine, custom GIF encoder), what
> was hard (LED colour accuracy at low brightness, seamless GIF loops, WLED
> quirks), and what's next (AWTRIX, Divoom, Tronbyt).
