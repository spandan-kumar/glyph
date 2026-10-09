# Glyph roadmap & launch plan

Glyph is a free, open-source (MIT) community project. Success = people
using it, starring it, sharing their setups and contributing art and code.
This plan merges product and marketing into one timeline, ordered for the
most reach and community, based on research (October 2026) into what
pixel-display owners want, which displays they own and where they talk.

**Status, 9 October 2026.** v1.3.5+10 is published. v1.3.2 shipped the
bug/polish bundle; v1.3.3 shipped logo Alerts, weather/day-counter Glance
cards and phone Rotations; v1.3.4–1.3.5 added interaction polish and lower
resource use. The library still has 1,209 looks, 62 procedural generators,
329 sprites and 22 categories.

**Next release: v1.3.6+11.** Activate the signed GitHub Pages catalog with
manual checks and optional foreground daily checks, fix background Music
activity pauses, and preserve complete Send content. The source and hosting
are prepared and the signed Pages catalog is live; phone/controller QA is deferred by the
maintainer, and the release tag waits for it. [PLAN.md](PLAN.md) owns the
release gates and implementation details.

**Strategy.** Soft-launch the shipped WLED product, then prioritize the device
setup wizard and an independent Home Assistant Saved-trigger blueprint.
Weather, counters, notifications and phone Rotations are shipped foundations,
not future v1.4 promises. Additional feeds need provider validation.
The setup wizard and HA blueprint can progress independently. The seasonal launch
window is a target, conditional on readiness. Later display adapters each
create a new community launch; dates remain provisional until hardware and
protocol checks pass.

**Privacy promise.** Free, no account and no Glyph backend. Rendering,
creations and notification contents stay local. Optional weather/aircraft/
market feeds contact external providers; remote catalog checks contact the
static host. Say what each feature sends and whether it needs the phone and
internet, rather than promising that all future features are offline.

---

## 1. Positioning

**Tagline:** *Your LED matrix, alive — 1,200+ animations, pixel art, clocks,
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
| Content no one else has | Scroll the library; 1,209 animations, public-domain classics (1928 Steamboat Willie, The Starry Night) |
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
| 1 | Notifications / smart-home values on the display | AWTRIX, WLED, Pixoo | logo Alerts shipped in v1.3.3; HA entity watcher later |
| 2 | Weather (now, forecast, air quality) | Tidbyt, AWTRIX | current weather shipped; forecast/air quality after provider validation |
| 3 | Planes overhead (top Tidbyt request) | Tidbyt | candidate after Glance foundation/provider checks |
| 4 | Sports scores | Tidbyt | skipped (free APIs keep dying) |
| 5 | Panel setup/mapping is confusing | WLED | orientation fix shipped; full wizard independently planned |
| 6 | Local, no cloud, no account | Pixoo, LaMetric, Tidbyt | core works locally; future external feeds explicitly optional |
| 7 | Easy custom pixel art | WLED | yes |
| 8 | Now Playing album art | Tidbyt, Pixoo | yes |
| 9 | Content rotation with a UI, not YAML | WLED, Tidbyt | device Shows shipped; phone Rotations shipped in v1.3.3 |
| 10 | Counters (days until/since) | Tidbyt, AWTRIX | shipped in v1.3.3 (phone timezone) |
| 11 | Busy light, night modes | Tidbyt, AWTRIX | Routines and logo Alerts shipped |
| 12 | Stocks/crypto | Tidbyt | after core Glance; provider/usage validation required |
| 13 | Calendar, transit, RSS | Tidbyt | later |
| 14 | Non-Latin text | AWTRIX, WLED | gap → 2027 |
| 15 | Ambient scenes | Tidbyt | yes |

---

## 3. Feedback channels and how they connect

No backend: everything routes to GitHub and one Discord, and the app links
straight into them.

| Channel | Purpose | Integration |
|---|---|---|
| **In-app "Send feedback"** (Glyph menu on every tab, and after errors) | Bug reports and ideas from people who'd never find GitHub | Opens a prefilled GitHub issue form in the browser with app version, phone model, WLED version, panel size and the last error; the person sees everything before sending. Fallback: copy diagnostics to share anywhere. |
| **In-app "Suggest an animation"** | Content requests | Opens the *Animation request* issue form |
| **In-app "Share your setup"** | Social proof | Opens Discord’s #show-your-setup in v1.3.2 (#22). Creations already share as GIF or `.glyph`; a general Stage clip is still planned |
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

Verified repository/release work:

- [x] MIT LICENSE.
- [x] Release-signing configuration and CI secrets used by the successful
      v1.3.1 release job (4 Oct UTC / 5 Oct IST); APK and SHA-256 published.
      Keep the release key stable for future updates.
- [x] README intro GIF/screenshots, release/license/Obtainium badges,
      supported WLED/panel list, and community/roadmap links.
- [x] Social preview asset (`docs/media/social_preview.png`) and GitHub topics.
- [ ] Confirm the social preview is configured in GitHub repository settings;
      the asset's presence alone does not verify that setting.
- [x] CONTRIBUTING, sprite agent skill, issue forms, PR template and
      13 `good first issue`s (#7–#19).
- [x] Discussions on. Glyph Discord: https://discord.gg/9EeCFZAFvk
- [x] Public roadmap board: https://github.com/users/spandan-kumar/projects/4
- [x] Discord webhook setup recorded in the existing plan; release
      announcements are implemented in the workflows. Other webhook
      delivery has not been re-verified by this reconciliation.
- [x] In-app feedback, animation requests, sharing link, What's new and
      Discord/roadmap links in the Glyph menu. Refinements are in #20–#24.
- [x] CI (analyze + test), tagged APK/checksum releases, release-note
      categories and Dependabot.

External status to confirm (not infer from repository files):

- [ ] Android developer verification registration/status.
- [ ] Play account/closed-test start and tester eligibility. Record the
      actual start date before calculating a production application date.

Remaining launch assets:

- [ ] Hero video 30–45 s (vertical + 16:9) and feature clips (Now Playing,
      swipe channels, draw live, a game, boot intro). Film in a dark room at
      a slow shutter so LEDs don't flicker; a diffuser photographs better.
- [ ] Technical blog post: phone-side rendering, DDP, the WLED GIF timer bug.
- [ ] One-page creator kit: what it is, 3 clips, links, contact.

### Week 1 — Soft launch to the core (12–18 Oct)

- [ ] **Tue 13 Oct: r/WLED** (~52k) video post (draft below). Reply to every
      comment for 48 h. Ask for Play testers and non-16×16 feedback.
- [ ] PR to the **WLED docs compatible-software list** (kno.wled.ge,
      `wled/WLED-Docs`): permanent, high-intent traffic.
- [ ] **WLED forum** (*Projects* and *Integrations*) and the WLED Discord.
- [x] Implement the known polish bundle for v1.3.2 (7 Oct):
      [#20](https://github.com/spandan-kumar/glyph/issues/20) collapsed-Stage Send,
      [#21](https://github.com/spandan-kumar/glyph/issues/21) sharing frequency,
      [#22](https://github.com/spandan-kumar/glyph/issues/22) Discord sharing,
      [#23](https://github.com/spandan-kumar/glyph/issues/23) system intro in Routines,
      [#24](https://github.com/spandan-kumar/glyph/issues/24) unchanged re-send.
      All five and audit fixes A1–A3 are bundled in v1.3.2+7 with regression
      coverage. Actions builds/publishes the APK and checksum; physical
      Android/controller QA was not performed during release preparation.

### Weeks 2–3 — Catalog and device setup (19 Oct – 1 Nov target)

Confirmed product answers and remaining proposals are recorded in [PLAN.md](PLAN.md).
Remaining work builds on the shipped features:

1. **Signed catalog delivery** — activate the v1.3.6 production verification
   key, protected signing and Pages hosting. Verify the public artifact,
   caching and optional daily cadence; finish deferred phone QA before
   releasing the app (see [delivery runbook](CATALOG_DELIVERY.md)).
2. **Device setup wizard** — the next product priority: size, start corner,
   serpentine wiring, tiling and visible corner/arrow tests, with configuration
   snapshot/write/reconnect/restore.
3. **Regression coverage** — Alerts, Glance and phone Rotations shipped in
   v1.3.3. Keep interruption/restoration, permission revocation, freshness,
   foreground/background transitions and phone-timezone counters working.
   The source has automated coverage and prior phone/controller QA; visual
   checks and new catalog phone QA must not be inferred from those tests.

Independent work, ship when verified:

- **Panel setup wizard** — size presets, start corner, serpentine, tiling,
  live corner/arrow tests and WLED config snapshot/write/reconnect/restore.
- **Home Assistant blueprint** — list Saved look IDs and trigger them from
  automations. Entity watching is a later feature.
- **Seasonal promotion** — Halloween + Diwali packs shipped in v1.3.1;
  film clips for 24 Oct. An automatic seasonal Routine remains planned.

Follow-on candidates: forecast/air quality, sunrise/sunset/moon phase,
crypto and planes overhead. Verify each provider's availability, coverage,
usage limits and required disclosures before assigning it to a release.
Aircraft route data is not promised before feed validation.

Apply for Play production only after the actual required closed-test period
and account requirements are confirmed. The old ~27 Oct estimate assumed
a test start that has not been verified.

### Week 4 — Wider launch (2–8 Nov target)

Target one 72-hour window, **Tue 3 – Thu 5 Nov**, if the release gates in
PLAN.md pass. Otherwise move the launch; posts must show only shipped
features. This is a promotion target; ship only features that meet their gates:

- [ ] **r/homeassistant** (~388k) + HA forum *Share your Projects*: lead with
      notifications/weather actually shipped, the HA blueprint if ready, and
      local rendering with explicit optional internet feeds.
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
- [ ] Curated **Community shelf** fed by reviewed GitHub PRs through the
      remote catalog; depends on the delivery track in PLAN.md.
- [ ] **Home Assistant entity watcher** (URL + token → Glance cards/alerts).
- [ ] **Non-Latin fonts** (Devanagari, Cyrillic, …).
- [ ] **iDotMatrix BLE** panels (experimental).
- [ ] **Live matrix preview in the browser** (idea): share a link that shows
      your matrix live in any browser, streamed peer-to-peer from the phone
      with PeerJS/WebRTC — no Glyph server, a static viewer page draws the
      LED dots. For showing friends, people without hardware, embeds.
- [ ] **iOS** build.

Not planned: AI image generation (paid cloud keys), sports scores (fragile
APIs), a full web/desktop editor/controller (PixelForge covers the browser).
The browser preview above is a viewer-only idea, not a web app commitment.

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

1. Shipped: CI on PRs/main runs `flutter analyze` + `flutter test`.
2. Shipped: tag `v*` → signed arm64 APK + sha256 on GitHub Releases
   (replaces committing APKs to `release/`).
3. Shipped: release notes from PR labels (`.github/release.yml`): *New animations*
   crediting artists, *Community requests* crediting reporters.
4. Shipped: tagged/manual release notes link to Glyph Discord. Planned:
   add clip links and Mastodon/Bluesky delivery.
5. GitHub → Discord #github-feed webhook setup recorded; delivery/settings
   need external verification when auditing the community setup.
6. Shipped: `fastlane/metadata/android/en-US/` listing/changelogs and release
   notes from versionCode. Planned: enforce a changelog in CI (currently only
   warns when missing), Play/F-Droid distribution and closed-track uploads.
7. Shipped: Dependabot for `pub`, `gradle`, `github-actions`.
8. Shipped: issue forms + PR template; in-app feedback URLs preselect
   `community` labels (not a general issue auto-labelling workflow).

---

## 8. Ready-to-post drafts

### r/WLED (soft launch)

> **I made a free, open-source app for WLED matrices — 1,200+ animations,
> album art from Spotify, games, pixel editor**
>
> [video]
>
> I wanted my 16×16 matrix to feel alive without fiddling, so I built Glyph.
> Your phone draws every frame and streams it, so it works on any ESP
> running WLED, or it saves animations to the device so they play without
> the phone.
>
> - 1,200+ original animations, plus public-domain classics (1928
>   Steamboat Willie, The Starry Night)
> - Now Playing: your music's album art with a progress bar
> - Pixel editor that draws live on the matrix, scrolling text, clocks that
>   run on the device
> - Music visualiser, 7 games with your phone as the controller
> - Shows and schedules that run without your phone
> - Local rendering, no account or Glyph backend. MIT licensed.
>
> Android APK: [release] · Code: [repo] · Discord: [invite]
>
> Would love feedback, especially from people with non-16×16 panels. Want to
> help get it on the Play Store? I need testers — reply or DM.

### Hackaday tip

Add planes to this draft only after that feature ships.

> **Subject:** Open-source phone app renders every frame for any WLED LED
> matrix (and found a WLED GIF timing bug)
>
> Glyph is a free Android app that turns a cheap WS2812B matrix into a pixel
> display: the phone renders and streams frames over DDP, so even an ESP8266
> runs animations, games and live album art.
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
