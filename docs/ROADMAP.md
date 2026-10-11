# Glyph roadmap & launch plan

Glyph is a free, open-source (MIT) community project. Success = people
using it, starring it, sharing their setups and contributing art and code.
This plan merges product and marketing into one timeline, ordered for the
most reach and community, based on research (October 2026) into what
pixel-display owners want, which displays they own and where they talk.

**Status, 11 October 2026.** v1.4.0+12 is published (11 October). It adds the
device setup wizard, automatic device time, Home Assistant blueprints and
forecast and air quality Glance cards. The library has 1,209 looks, 62
procedural generators, 329 sprites and 22 categories.

**Latest release: v1.4.0+12**
([notes](https://github.com/spandan-kumar/glyph/releases/tag/v1.4.0)). The
wizard covers Wi-Fi join, panel size, a three-tap wiring test, grids of equal
panels up to WLED's 18-panel limit, and apply with undo. Home Assistant
blueprints live in `homeassistant/` ([guide](HOME_ASSISTANT.md)). Crypto was
dropped: CoinGecko needs an API key and the keyless alternatives forbid
redistribution. Planes overhead is deferred by the maintainer.

**Known gaps in this release.** It shipped without a never-configured-ESP32
check (no spare hardware). Panel grids and iOS have automated coverage only;
the iOS test plan is [QA_IOS.md](QA_IOS.md). v1.3.6 QA is in
[the QA record](QA_1_3_6.md). [PLAN.md](PLAN.md) owns release gates.

**Strategy.** Refresh the screenshots and listing, publish the privacy and
security policies, film the hero video, then soft-launch to r/WLED with the
setup wizard as the lead. Wider posts follow once feedback is triaged and the
hardware QA below is done or honestly disclosed as missing. Distribution is
GitHub Releases and Obtainium; F-Droid later. The Play Store is not planned
yet. Later display adapters each create a new community launch; dates stay
provisional until hardware and protocol checks pass.

**Privacy promise.** Free, no account and no Glyph backend. Rendering,
creations and notification contents stay local. Optional weather and air quality
feeds contact Open-Meteo; remote catalog checks contact the
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
| 1 | Notifications / smart-home values on the display | AWTRIX, WLED, Pixoo | logo Alerts shipped in v1.3.3; Home Assistant blueprints (trigger Saved looks and Shows from automations) shipped in v1.4.0; entity watcher later |
| 2 | Weather (now, forecast, air quality) | Tidbyt, AWTRIX | current weather (v1.3.3) plus forecast and air quality cards (v1.4.0, Open-Meteo) shipped |
| 3 | Planes overhead (top Tidbyt request) | Tidbyt | deferred by the maintainer (no suitable free feed validated) |
| 4 | Sports scores | Tidbyt | skipped (free APIs keep dying) |
| 5 | Panel setup/mapping is confusing | WLED | setup wizard shipped in v1.4.0 (Wi-Fi, size, wiring test, panel grids, undo); fresh-ESP32 and real multi-panel QA pending hardware |
| 6 | Local, no cloud, no account | Pixoo, LaMetric, Tidbyt | core works locally; future external feeds explicitly optional |
| 7 | Easy custom pixel art | WLED | yes |
| 8 | Now Playing album art | Tidbyt, Pixoo | yes |
| 9 | Content rotation with a UI, not YAML | WLED, Tidbyt | device Shows shipped; phone Rotations shipped in v1.3.3 |
| 10 | Counters (days until/since) | Tidbyt, AWTRIX | shipped in v1.3.3 (phone timezone) |
| 11 | Busy light, night modes | Tidbyt, AWTRIX | Routines and logo Alerts shipped |
| 12 | Stocks/crypto | Tidbyt | stocks skipped; crypto dropped (CoinGecko needs a key, keyless alternatives forbid redistribution), see GLANCE.md |
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

Re-dated on Sunday 11 October 2026. Dates are targets. Items that need
hardware or Apple setup have no date until the equipment exists.

### Done by 11 October

- [x] MIT LICENSE; signed release workflow; APK and SHA-256 published.
- [x] README intro GIF, badges, supported WLED/panel list, community links.
- [x] Social preview asset (`docs/media/social_preview.png`) and GitHub topics.
- [x] CONTRIBUTING, sprite agent skill, issue forms, PR template and
      13 `good first issue`s (#7–#19).
- [x] Discussions on; Glyph Discord https://discord.gg/9EeCFZAFvk
- [x] Public roadmap board: https://github.com/users/spandan-kumar/projects/4
- [x] In-app feedback, animation requests, sharing link, What's new and
      Discord/roadmap links in the Glyph menu.
- [x] CI (analyze + test), tagged APK/checksum releases, release-note
      categories and Dependabot; Discord release announcements.
- [x] v1.3.2 polish bundle (#20 to #24), v1.3.3 Alerts/Glance/Rotations,
      v1.3.6 signed catalog delivery.
- [x] **v1.4.0** (11 Oct): setup wizard with panel grids, automatic device
      time, Home Assistant blueprints, forecast and air quality cards.
- [x] Home Assistant blueprint built and documented (`homeassistant/`).

### Week 1: assets and policies (12–18 Oct)

- [ ] Privacy policy ([PRIVACY.md](PRIVACY.md), being written) and security
      policy (`SECURITY.md`, being written); link both from README and the app.
- [ ] Refreshed screenshots and store listing for 1.4.0 (in progress).
- [ ] Hero video 30–45 s (vertical + 16:9) and feature clips (setup wizard
      wiring test, Now Playing, swipe channels, draw live, a game, boot
      intro). Needs maintainer footage. Film in a dark room at a slow shutter
      so LEDs don't flicker; a diffuser photographs better.
- [ ] Confirm the social preview is configured in GitHub repository settings.
- [ ] Android developer verification registration/status (external, confirm).
- [ ] Technical blog post: phone-side rendering, DDP, the WLED GIF timer bug.
- [ ] One-page creator kit: what it is, 3 clips, links, contact.

### Hardware and platform QA (no dates; blocked on equipment)

- [ ] Fresh-ESP32 check: run the wizard on a never-configured controller
      (skipped for 1.4.0, no spare hardware).
- [ ] Real multi-panel grid QA on physical panels.
- [ ] iOS build and a run of [QA_IOS.md](QA_IOS.md) (needs Apple setup).
- [ ] v1.4.x fixes from whatever these find; say in posts that grids and iOS
      were covered by automated tests only until then.

### Week 2: soft launch to the core (19–25 Oct, once screenshots and video exist)

- [ ] **r/WLED** (~52k) video post (draft below). Reply to every comment for
      48 h. Lead with the setup wizard. Ask for non-16×16 and multi-panel
      feedback, since those are the least tested.
- [ ] PR to the **WLED docs compatible-software list** (draft below).
- [ ] **WLED forum** (*Projects* and *Integrations*) and the WLED Discord.
- [ ] Post in Glyph Discord #announcements.

### Weeks 3–4: feedback and the Home Assistant crowd (26 Oct – 8 Nov)

- [ ] Triage r/WLED feedback onto the board; ship v1.4.1 fixes.
- [ ] **r/homeassistant** (~388k) + HA forum *Share your Projects*: lead with
      the blueprint and local, no-cloud control. Needs a live-HA check first
      (see [HOME_ASSISTANT.md](HOME_ASSISTANT.md)).
- [ ] Optional daily catalog checks and signed catalog regression: keep
      [CATALOG_DELIVERY.md](CATALOG_DELIVERY.md) current.
- [ ] **Sun 8 Nov: Diwali** clip on r/WLED and Discord.

### Weeks 5–6: wider launch (target Tue 10 – Thu 12 Nov, if gates pass)

One 72-hour window. Posts show only shipped features; move the window if
the soft launch turns up serious bugs.

- [ ] **r/esp32** (~109k), **r/arduino** (~767k), **r/led**: lead with how it
      works (phone renders, DDP, any ESP).
- [ ] **r/androidapps** (~560k): screenshots + clip.
- [ ] **r/FlutterDev** (~155k): the technical write-up.
- [ ] **Hackaday tip** (tips@hackaday.com): draft below.
- [ ] **Show HN**: weekday morning US time, with the blog post.
- [ ] **awesome-flutter** PR (`SOURCE.md`, bottom of the category, with a GIF).
- [ ] **F-Droid** submission with an honest AI-assistance disclosure
      (F-Droid's interim policy allows reviewed AI help; IzzyOnDroid doesn't,
      so skip it). Obtainium badge already live. The Play Store is not planned
      yet; revisit after the F-Droid submission.

### Weeks 7–8: amplify (16–29 Nov)

- [ ] Pitch **5 YouTubers** (WLED/Home Assistant/maker space, e.g. DrZzs, The
      Hook Up, Everything Smart Home, QuinLED, Andreas Spiess, Core
      Electronics, Adafruit) with the creator kit. One video beats everything.
- [ ] **r/PixelArt** (2.7M): art made in Glyph on a real matrix; app link only
      in a comment.
- [ ] First **monthly community pack** + "you asked, we built" post.

### Weeks 9–11: v1.5 "AWTRIX" (30 Nov – 20 Dec, provisional)

- [ ] Generic **Art-Net / E1.31 sender**, then **AWTRIX NG** on Ulanzi TC001
      (Art-Net live on UDP 6454, GIF upload to `/ICONS`, mDNS
      `_awtrixng._tcp`). Also covers ESPHome E1.31 matrices and DIY controllers.
- [ ] **Christmas pack** (early Dec).
- [ ] Launch to the AWTRIX/Home Assistant crowd (HA forum, AWTRIX GitHub
      discussions) and a r/homeassistant follow-up.

### Weeks 12–14: v1.6 "Pixoo" (21 Dec – 10 Jan, provisional)

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
- [ ] **iOS** release (the build and QA run are in the hardware list above).

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
- **Distribution:** GitHub Releases + Obtainium now; F-Droid later.
  The Play Store is not planned yet.

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

Written for v1.4.0. Replace the bracketed placeholders. Plain claims only:
Android first, free, MIT. Say plainly that grids and iOS have had automated
tests but no physical QA yet. Do not post anything until the screenshots and
video exist.

### r/WLED (soft launch)

> **Title:** Free, open-source Android app that sets up a WLED matrix for you
> (size, wiring, panel grids) and has 1,200+ animations
>
> [video link]
>
> I got tired of fixing 2D settings by hand every time I built a matrix, so
> the Glyph setup wizard does it: it joins the controller to your Wi-Fi,
> asks for the panel size, lights up three corners so you tap the one that
> is first, works out the wiring, and writes the 2D layout. It handles grids
> of equal panels up to WLED's 18-panel limit, and it keeps a snapshot so you
> can undo the change.
>
> After setup it is a content app. Your phone draws every frame and streams
> it, or sends a GIF to the controller so it plays without the phone.
>
> - 1,200+ original animations plus public-domain pieces (1928 Steamboat
>   Willie, The Starry Night)
> - Now Playing album art, pixel editor that draws live, text and clocks,
>   music visualisers, seven games
> - Shows and schedules that run on the device
> - Weather, forecast and air quality cards (Open-Meteo, optional)
> - Free, MIT licensed, no account, no Glyph server. Android first.
>
> Honest limits: I had no spare ESP32, so the wizard has not been run on a
> never-configured controller, and grids are tested in software only. iOS is
> not out yet. If you try it on a multi-panel build, please tell me what
> broke.
>
> APK: [release link] (also on Obtainium) · Code: [repo] · Discord: [invite]

### WLED forum, Projects

> **Title:** Glyph: a free Android app with a setup wizard and a content
> library for WLED matrices
>
> Glyph is an MIT-licensed Android app for WLED displays. The phone renders
> every frame. It either streams over DDP or bakes a GIF and uploads it for
> the Image effect.
>
> v1.4.0 adds a setup wizard: Wi-Fi join, panel size, a three-tap wiring test
> and grids of equal panels up to the 18-panel limit, with a config snapshot
> and undo. The rest is a library of 1,200+ looks, a pixel editor, clocks,
> Now Playing and Shows.
>
> Notes for people who care about internals: streamed frames get gamma and
> white balance in the app because live mode skips WLED's, and device GIFs
> cap every frame at one second because of the carried-over frame delay in
> the GIF loader. Grids and the never-configured-device path have only
> automated tests so far. Feedback on multi-panel layouts is the most useful
> thing I could get. Code: [repo] · Release: [release link] · Video: [video link]

### Glyph Discord #announcements

> **Glyph 1.4.0 is out.**
> The setup wizard is the headline: join Wi-Fi, set the panel size, tap
> through a three-corner wiring test, build grids of up to 18 panels, and
> undo if it goes wrong. Also new: the controller's clock sets itself,
> Home Assistant blueprints (docs/HOME_ASSISTANT.md), and forecast and air
> quality cards. Crypto prices were dropped (the providers need keys or forbid
> redistribution). Not tested on real multi-panel builds or a fresh ESP32
> yet, so tell us in #help what you see.
> Download: [release link]

### r/homeassistant

> **Title:** Blueprints to trigger looks on a WLED pixel matrix from
> automations, local only, no cloud
>
> I made an Android app called Glyph for WLED matrices. It has a Saved look
> and Shows model, and I added Home Assistant blueprints that trigger them by
> name from automations (door opens, washer finishes, presence changes). The
> blueprints are in `homeassistant/` with a guide in docs/HOME_ASSISTANT.md.
> Everything runs on your network: Home Assistant talks to the controller,
> and Glyph has no account and no server.
>
> It is free and MIT licensed, Android first. Glyph also has a setup wizard
> for the matrix itself, if you are still wiring one up. Watching Home
> Assistant entities directly is not built; the blueprints trigger existing
> looks only. Feedback on the blueprint inputs is welcome.
>
> Guide: [link] · Code: [repo] · Video: [video link]

### PR to wled/WLED-Docs, compatible software

The kno.wled.ge page is https://kno.wled.ge/basics/compatible-software/. Its
source should be `docs/basics/compatible-software.md` in the `wled/WLED-Docs`
repo (default branch `main`). Check the file name and read CONTRIBUTING.md and
STYLE_GUIDE.md first, and add the entry under the controllers group,
matching the existing format.

> **Title:** Add Glyph to compatible software (controllers)
>
> Adds Glyph, a free open-source (MIT) Android app for WLED displays, to the
> controllers list on the compatible software page.
>
> What it does with WLED: uses the JSON API for state, presets and file
> upload, streams frames over DDP, and uploads GIFs for the Image effect. It
> includes a 2D setup wizard (size, wiring, panel grids) that writes the
> LED/2D settings and restores a snapshot on undo.
>
> Link: https://github.com/spandan-kumar/glyph
> Tested with WLED 16.0.1. I am the author. Happy to adjust wording or move
> the entry.

### Hackaday tip

> **Subject:** Open-source phone app sets up and drives WLED LED matrices
> (and found a WLED GIF timing bug)
>
> Glyph is a free Android app (MIT). The phone renders every frame and
> streams it over DDP, so even an ESP8266 runs animations, games and live
> album art. A new setup wizard configures the 2D layout, including grids of
> panels, from a three-tap wiring test. While building it I found WLED's GIF
> player carries one file's frame delay into the next, which can blank the
> display for minutes; the app caps frames to work around it.
> Video: [video link] Code: [repo]

### Show HN

> **Show HN: Glyph, an open-source Android app that sets up and drives WLED matrices**
>
> First comment: I build with LED matrices and kept fixing 2D settings by
> hand, so v1.4.0 has a setup wizard (Wi-Fi, size, three-tap wiring test,
> panel grids, undo). The rest is a content app: the phone renders frames in
> pure Dart and either streams them over DDP or uploads a baked GIF. Stack:
> Flutter, a pure-Dart engine, a custom GIF encoder. Hard parts: LED colour
> accuracy at low brightness, seamless GIF loops, WLED's carried-over GIF
> frame delay. Limits: Android only for now, grids and the fresh-device path
> are untested on real hardware, and I have no analytics, so I do not know
> who uses it. Code: [repo]. Feedback welcome.
