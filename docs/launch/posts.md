# Glyph launch posts

Ready-to-post drafts for the plan in [OUTREACH.md](OUTREACH.md). Drafted
18 October 2026 for v1.4.9. Nothing here has been posted. The maintainer
approves and sends every post, email and PR.

## Fact sheet (use these numbers, nowhere else)

| Fact | Say exactly |
|---|---|
| Version | v1.4.9 (check the latest release before posting) |
| Library | "13,000+ animations" (catalog: 13,597 looks) |
| Made of | 62 procedural effects, 356 sprites, public-domain "Famous Classics", plus a collection shared with permission by its creator |
| Platform | Android 7+, 64-bit ARM. Sideload the APK, or add it to Obtainium. No iOS. |
| F-Droid | Pending (merge request open). Never say "available on F-Droid". |
| Play Store | Not there yet. Don't promise a date. |
| Licence | "MIT-licensed code; artwork terms vary." Never "all original". Never name the imported collection's source. |
| Cost | Free, no account, no analytics, no Glyph server |
| Games / visualisers | Seven games, nine microphone visualisers |
| Developed on | WLED 16.0.1, ESP32, 16x16 WS2812B |
| Send to device needs | WLED 16+ on an ESP32-family chip with free storage. ESP8266 can stream, not Send. |

**Honest limits.** Put these in every long post:

- The setup wizard has not been run on a factory-fresh, never-configured
  controller. The wiring test and layout have been run on my 16x16.
- Multi-panel grids are tested in software only, not on a physical grid.
- The Home Assistant blueprints have not had a live Home Assistant run yet.
- iOS: not available.

**Links**

- Repo: https://github.com/spandan-kumar/glyph
- Latest APK: https://github.com/spandan-kumar/glyph/releases/latest
- Discord: https://discord.gg/fMbzGQd6wk
- Site: https://spandan-kumar.github.io/glyph/ [site, once live]
- Obtainium: https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/spandan-kumar/glyph

**Clips.** A = 20 s vertical, swipe, Send, phone off, panel keeps playing.
B = 15 s "Which corner lit up?" wiring test to upright arrow. C = 12 s album
art with progress bar. Use [clip A link], [clip B link], [clip C link].
Original and CC0 art only on camera.

**Before you post anything**

1. Re-read the venue's rules. Reddit rules and flairs below are not verified
   (research could not reach Reddit). Check each sub's rules page and its
   AI-assisted-project stance; skip a venue that bans them.
2. Check that the numbers still match the fact sheet and that the README first
   screen and install block are fixed (Phase 0).
3. Be present for 48 hours after each launch post. Reply to everyone.
4. One post per venue. Don't post the same text on the same day in
   overlapping subs. Each draft below takes a different angle on purpose.
5. Fix before linking: `blog-phone-renders-every-frame.md` still says 1,209
   looks, 329 sprites and 22 categories; `creator-kit.md` still says 1,200+
   looks, 1,209 and 329. Update both to the fact sheet first.

---

## 1. WLED forum, Projects

- **Venue:** https://wled.discourse.group, category Projects
- **Date:** Thu 29 Oct 2026 (Tue to Thu is best here)
- **Asset:** Clip B, plus clip A as a link
- **Flair/format to check:** Projects category; no self-promotion rule found,
  only "don't post spam". Post once.

**Title:** Glyph: a free Android app that sets up a WLED matrix and fills it

**Body:**

I made Glyph, an MIT-licensed Android app for WLED matrices. I wanted a 2D
setup that didn't mean hunting through settings pages, and a library big
enough that the panel is never boring.

[clip B link] shows the wizard's wiring test: a corner lights up, you tap
which one, it follows a run of LEDs, and then it writes the 2D layout into
WLED's own config (`POST /settings/2D`, so no reboot). It keeps a snapshot
and offers Undo.

After setup it's a content app. The phone renders every frame, then either:

- **streams** it over DDP (UDP 4048). Streamed frames skip WLED's gamma when
  `if.live.no-gc` is true, so the app applies gamma and white balance itself.
  This also means an ESP8266 can run everything but Send.
- **sends** it: bakes a seamless GIF, uploads it with `/upload`, verifies the
  file, then sets the Image effect and saves a preset. The phone can go away.

Two things I found on WLED 16.0.1 that might save someone time:

- The GIF loader never resets `currentFrameDelay` in `image_loader.cpp`, so a
  long hold in one file carries over to the next and the display looks blank
  until it runs out. Glyph caps every device frame at one second.
- `hw.led.ins` entries are rebuilt from defaults, so you have to post the full
  entry, not a patch.

What's in it: 13,000+ animations (62 procedural effects, 356 sprites, public
domain classics, and a collection shared with permission), a pixel editor that
draws live, text, clocks, seven games, and album art from whatever your phone
is playing. Code is MIT; artwork terms vary, details in the README.

Limits, plainly: I developed it on WLED 16.0.1 with an ESP32 and a 16x16
WS2812B panel. The wizard hasn't been run on a factory-fresh controller yet,
and multi-panel grids are tested in software only. Home Assistant blueprints
are in the repo but haven't had a live run. Android only, 7+ and 64-bit ARM.

Feedback from anyone with a non-16x16 panel or a grid would help most. It
isn't a replacement for the WLED app, and it works fine next to PixelForge.

Repo: https://github.com/spandan-kumar/glyph
APK: https://github.com/spandan-kumar/glyph/releases/latest
Discord: https://discord.gg/fMbzGQd6wk

---

## 2. Forum replies (answer first, Glyph second)

Date for all: Thu 29 Oct 2026. Fetched and read each thread on 18 Oct 2026.
One line of the rule applies: answer the question, mention Glyph only if it
helps, say you're the author.

### 2a. WLED forum 15261: captive portal and the WLED app (post this one)

- **Thread:** https://wled.discourse.group/t/captive-portal-and-wled-app-device-inconsistencies/15261
- **What was asked:** A teacher with 10 course participants. After joining a
  fresh ESP32's AP, the WLED app doesn't show the device until the user taps
  "use network as is" in Android's Wi-Fi menu. Any ideas? Saratoga replied that
  phones handle a no-internet AP differently; best to use a router instead.
- **Fit:** Real. Glyph's assisted connect uses Android's
  `WifiNetworkSpecifier` and binds the app to the network.
- **Caveat to keep:** not yet run on a factory-fresh controller.

**Reply:**

Saratoga has the cause right. The prompt you're dismissing in step 4 is
Android asking whether to stay on a network with no internet. If you ignore it
or answer "no", Android can route the app's traffic over mobile data, so the
app never reaches 4.3.2.1. "Use network as is" is the same answer given later.

Two things that can make a class easier:

- Turn off mobile data on the phones before the session. With no other route,
  Android has nowhere else to send the traffic.
- Apps can do this for you: on Android 10+ an app can ask for a specific Wi-Fi
  network (`WifiNetworkSpecifier`) and bind its own traffic to it, which
  removes the prompt from the user's hands.

Disclosure: I'm the author of an Android app called Glyph (free, MIT) that
does the second one in its setup wizard. I haven't been able to run it against
a factory-fresh controller yet, so treat it as untested for exactly your
case. If one of your course phones can spare ten minutes, I'd like to hear how
it goes: https://github.com/spandan-kumar/glyph

### 2b. WLED forum 15553: artist and the hospital panel (post this one)

- **Thread:** https://wled.discourse.group/t/artist-looking-for-help-in-implementing-a-design-via-wled/15553
- **What was asked:** A non-technical artist (15 Oct 2026) has a visual
  sequence and a panel from a professional manufacturer that doesn't normally
  use WLED. Dedehai replied: use GIFs, try PixelForge.
- **Fit:** Partial. Glyph can import a GIF and Send it, but only if the panel
  runs WLED 16+ on an ESP32-family chip. The first honest step is to ask the
  manufacturer what the controller is.
- **Caveat to keep:** Android only.

**Reply:**

Dedehai's GIF route is the simplest one, so here is how I'd do it end to end.

1. Export the sequence as a GIF at the panel's own pixel size (for example
   32x16).
2. Ask the manufacturer which controller is inside and which WLED version it
   runs. GIF playback (the Image effect) needs WLED 16 or newer on an ESP32,
   and some free storage on the controller.
3. Upload the GIF to the controller, set the Image effect, and set the segment
   name to the file name including `.gif`. Save it as a preset so it starts on
   power-up.

PixelForge in WLED 16 does the upload for you from the browser. If you'd
rather use an Android phone, I wrote an app called Glyph (free, MIT) that
imports a GIF, tunes it for LEDs, and sends it to the controller with the
preset made. I'm the author, and it needs an Android phone, so use whatever
suits you. Happy to answer questions here if you get stuck.

### 2c. WLED forum 14722: upload without internet (optional, low value)

- **Thread:** https://wled.discourse.group/t/upload-without-internet-access/14722
- **What was asked:** Upload GIFs for the Image effect "in the field" with no
  internet, because /edit loads a script from a CDN.
- **State:** Resolved in August 2025 (cache the ace.js file, or `curl -F` to
  `/upload`). A new reply would add little. I'd only post it if you want the
  Glyph mention on record.
- **Fit:** Real but late. Glyph uploads over local Wi-Fi with no cloud.

**Reply:**

Late addition for anyone who finds this thread: the whole flow works on a
local router with no internet. The GIF goes to the device with
`curl -F "data=@file.gif" http://<ip>/upload` (the form field is `data`, as
found above), then you set the Image effect on a segment named after the file
and save a preset.

I wrote a free Android app called Glyph (MIT, I'm the author) that does those
steps over local Wi-Fi and checks the file arrived before it switches the
display. It never touches the internet to do it. Only mentioning it because
this was the use case I had in mind: https://github.com/spandan-kumar/glyph

### 2d. WLED forum 13915: scrolling an image (skip)

- **Thread:** https://wled.discourse.group/t/scrolling-an-image-animated-image-across-a-2d-matrix/13915
- **What was asked:** How to scroll a 2-frame animation without one preset per
  frame.
- **Why skip:** Answered in January 2025 (bake the motion into the GIF, name
  the segment after the file). The poster got it working. Glyph can make and
  send a GIF, but I could not verify that it pans a large image, and replying
  to a 21-month-old solved thread would read as promotion. Skipped.

### 2e. HA community 955482: Pixel Select (post this one, optionally)

- **Thread:** https://community.home-assistant.io/t/a-small-tool-to-paint-on-adressable-led-displays-rings-and-strips/955482
- **What was asked:** Not a question. The author shared Pixel Select, a web
  tool to paint pixels. A reader couldn't get the exported UDP command to light
  WLED; it turned out to be a protocol mix-up (WARLS on 21324, Hyperion on
  19446). It works now (December 2025).
- **Fit:** Modest. The protocol confusion is something I can add to
  helpfully (DDP). A mention of Glyph is only a side note. The thread is 11
  months old, so keep it short.

**Reply:**

Nice tool, and a useful write-up of the UDP mix-up. One more option for anyone
who ends up here: WLED also takes DDP on UDP 4048. It carries a 10-byte header
with an offset and length, so a frame of any size can be split into packets of
up to 1,440 bytes, with the push flag on the last one. That avoids the
per-protocol LED limits, and WLED applies the frame when the push arrives.

I'm the author of Glyph, a free Android app for WLED matrices (MIT) that draws
on the panel live over DDP as you paint on the phone. It's matrix-focused, so
Pixel Select's rings and strips are a different job. Notes on how it frames
packets, if useful: https://github.com/spandan-kumar/glyph

---

## 3. Home Assistant community

### 3a. Share your Projects

- **Venue:** https://community.home-assistant.io, category Share your Projects
- **Date:** Fri 30 Oct 2026 (HA 2026.11 lands about 4 Nov; don't post on
  release day)
- **Asset:** Clip A (or the first 10 s of it), screenshot of Device > Saved >
  Use with Home Assistant
- **Flair/format to check:** category "Share your Projects!"; add tags such
  as `wled` and `blueprint` if the category lets you.

**Title:** Glyph: a local-only app for WLED matrices, with two blueprints for
automations

**Body:**

I made Glyph, a free Android app for WLED LED matrices, and added two Home
Assistant blueprints so automations can pick what the display shows.

[clip A link] shows the whole idea: pick a look on the phone, tap Send, and
the matrix keeps playing with the phone off. Home Assistant can then trigger
those Saved looks by name. Nothing leaves your network. There's no account,
and Glyph has no server.

What the blueprints do:

- **Show a Saved look when something happens.** Pick any trigger (doorbell,
  sunset, someone arriving). Optional: go back after a time, or stay until
  another trigger fires (the washer door opens), with a longest-wait safety.
- **Play a Show when something happens.** Same options, for a playlist of
  Saved looks.
- Quiet hours (including windows past midnight), a cooldown, and a brightness
  for the moment. Each automation snapshots what the device was doing and goes
  back to it, but only if the device still shows your look. If someone changed
  it meanwhile, it leaves their choice alone.

They use Home Assistant's built-in WLED integration (the light plus the
Preset and Playlist selects). Home Assistant 2024.10 or newer. A step by step
guide and four recipes (doorbell, laundry, timer, sunset) are in
`docs/HOME_ASSISTANT.md`.

Honest limits: I haven't had a live run on a real Home Assistant yet. I wrote
the blueprints against the integration's entities and the docs, so please
treat them as beta and tell me where the inputs confuse you. Glyph also can't
draw a Home Assistant entity (a temperature, say) on the display yet. That's
planned. For now Home Assistant chooses what plays and Glyph supplies the
looks.

The app is Android 7+ (64-bit ARM), sideloaded or through Obtainium. It's
MIT-licensed code; artwork terms vary (details in the README).

Guide: https://github.com/spandan-kumar/glyph/blob/main/docs/HOME_ASSISTANT.md
Repo: https://github.com/spandan-kumar/glyph
Discord: https://discord.gg/fMbzGQd6wk

### 3b. Blueprints Exchange: "Glyph: show a Saved look when something happens"

- **Venue:** Blueprints Exchange category
- **Date:** Fri 30 Oct 2026 (same day, after the project post)
- **Asset:** Screenshot of the blueprint's input form (take one in HA)
- **Flair/format to check:** the exchange convention is the import badge,
  a short description, the inputs, and the source link. Add the
  `automation` tag if offered.

**Title:** Glyph: show a Saved look when something happens (WLED matrix)

**Body:**

[![Open your Home Assistant instance and show the blueprint import dialog with a specific blueprint pre-filled.](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fspandan-kumar%2Fglyph%2Fblob%2Fmain%2Fhomeassistant%2Fblueprints%2Fautomation%2Fglyph%2Fshow_saved_look.yaml)

Plays one of your **Saved looks** (a preset on a WLED display) when
something happens, then optionally goes back to what the device was doing. I
wrote it for WLED matrices driven by the Glyph Android app, but it only needs
the WLED integration's light and Preset select. I've only built and tried it
around Glyph's Saved looks.

**Needs:** Home Assistant 2024.10+, the built-in WLED integration, and a saved
preset on the device.

**Inputs:**

- *When this happens:* any trigger.
- *Your Glyph device (light)* and *(Preset)*: the WLED entries, for example
  `light.matrix` and `select.matrix_preset`.
- *Saved look name:* exactly as the device shows it. Glyph's Device > Saved >
  Use with Home Assistant sheet has a copy button for each name.
- *Go back after:* how long to show it; 0 stays on it.
- *Until this happens (optional)* and *Longest wait:* stay until another
  trigger (the door opens), with a 12-hour default fallback.
- *Quiet hours*, *Cooldown*, *Brightness*, and an optional *Playlist* entry
  so it can go back to a Show that was playing.

Only goes back if the device still shows your look, so it won't undo someone
else's change. Mode is `restart`: a second trigger restarts the timer.

**Not tested live yet.** I haven't had a live run on a real Home Assistant, so
treat this as beta. If the name doesn't match, the automation trace shows a
"not a valid option" error.

Source: https://github.com/spandan-kumar/glyph/blob/main/homeassistant/blueprints/automation/glyph/show_saved_look.yaml
Guide: https://github.com/spandan-kumar/glyph/blob/main/docs/HOME_ASSISTANT.md

### 3c. Blueprints Exchange: "Glyph: play a Show when something happens"

- **Venue, date, asset, format:** as 3b. Post it as a separate topic.

**Title:** Glyph: play a Show when something happens (WLED playlist)

**Body:**

[![Open your Home Assistant instance and show the blueprint import dialog with a specific blueprint pre-filled.](https://my.home-assistant.io/badges/blueprint_import.svg)](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fspandan-kumar%2Fglyph%2Fblob%2Fmain%2Fhomeassistant%2Fblueprints%2Fautomation%2Fglyph%2Fplay_show.yaml)

Starts one of your **Shows** (a playlist of Saved looks on a WLED display)
when something happens, then optionally goes back to what was playing. It's
the sibling of the Saved look blueprint, for when you want a sequence, such as
a party mode when you arrive.

**Needs:** Home Assistant 2024.10+, the built-in WLED integration, and a
playlist on the device.

**Inputs:**

- *When this happens:* any trigger.
- *Your Glyph device (light)* and *(Playlist)*: for example `light.matrix` and
  `select.matrix_playlist`.
- *Show name:* exactly as the device shows it (copy buttons in Glyph's
  Device > Saved > Use with Home Assistant).
- *Preset (optional):* lets it return to a Saved look that was playing.
- *Go back after*, *Until this happens*, *Longest wait*, *Quiet hours*,
  *Cooldown*, *Brightness*: same as the Saved look blueprint.

A Show that ends by itself may leave the device where it is. Going back only
happens while the device still reports that Show as playing.

**Not tested live yet.** No live run on a real Home Assistant so far, so it's
beta. Feedback on the inputs is the most useful thing.

Source: https://github.com/spandan-kumar/glyph/blob/main/homeassistant/blueprints/automation/glyph/play_show.yaml
Guide: https://github.com/spandan-kumar/glyph/blob/main/docs/HOME_ASSISTANT.md

---

## 4. r/WLED (soft launch)

- **Venue:** r/WLED (~71k members)
- **Date:** Sat 31 Oct 2026 (Halloween), around 9:00 to 12:00 ET. Reply for 48 h.
- **Asset:** Clip A ending on a Halloween look (lead); clip B in the body
- **Gate:** clip A filmed and 1.4.10 shipped; otherwise post Sat 7 Nov
- **Flair/format to check:** unverified. Read the sidebar for the
  self-promotion rule and pick a flair like "Show Off" or "Project". Upload
  the video natively and put links in the body, not the title.
- **Angle:** the setup wizard. PixelForge is mentioned warmly, once.

**Title:** I made a free app that sets up your 2D matrix: it asks "which corner lit up?"

**Body:**

[clip A]

I got tired of fixing 2D settings by hand every time I built a matrix, so I
made Glyph, a free Android app with a setup wizard. It walks through: pick the
size, tap the corner that lit up, tap which way the run moves, and it writes
the layout into WLED's 2D config. It keeps a snapshot, so Undo puts the old
settings back. It also handles grids of equal panels, up to WLED's
18-panel limit.

After that it's a content app, so the panel has something to show:

- 13,000+ animations (effects, pixel art, public-domain classics like The
  Starry Night and Dracula, plus a collection shared with permission),
  with a Halloween pack for today
- a pixel editor that draws on the panel live, text and clocks, seven games,
  album art from your phone
- Send puts a baked GIF on the controller, so it plays with the phone off

This is not a PixelForge replacement. PixelForge is great for turning one
image into a GIF. Glyph is the setup around it plus a library, and it uses
WLED's normal API, so everything still works in the WLED app and web UI.

Free, MIT-licensed code (artwork terms vary, README has the detail), no
account, no Glyph server. Android 7+ and 64-bit ARM; sideload the APK or add
it to Obtainium. No iOS.

Honest limits: I built it on a 16x16 WS2812B with an ESP32 on WLED 16.0.1.
The wizard hasn't been run on a factory-fresh controller yet, and multi-panel
grids are tested in software only, not on a real grid. If you try a 32x8, a
64x32 or a grid of panels, I'd really like to hear what broke.

APK: https://github.com/spandan-kumar/glyph/releases/latest
Code: https://github.com/spandan-kumar/glyph
Discord: https://discord.gg/fMbzGQd6wk

**Pinned first comment (from you):** Author here. Happy to answer anything.
The most useful thing you could tell me is your panel size and whether the
wizard picked the right corner and direction.

---

## 5. Other subreddits (each a different angle)

### 5a. r/homeassistant

- **Date:** Tue 10 Nov 2026 (HA 2026.11 is a week old by then)
- **Asset:** Clip A, with a screenshot of the blueprint form
- **Flair/format to check:** "Show & Tell". Promotion rules unverified; read
  them. Open source and free is usually tolerated there. Don't post the same
  day as r/esp32 in the same style.
- **Angle:** local, no cloud, blueprints.

**Title:** A WLED pixel matrix that reacts to automations, with no cloud or account (blueprints)

**Body:**

[clip A]

I made a free Android app called Glyph for WLED matrices. For Home Assistant
users, the useful part is a Saved look and Show model: you send a look to the
device from your phone, then it plays on its own, and two blueprints let
automations trigger those looks by name (doorbell, washer done, someone
arriving). Everything stays on your network. Home Assistant talks to the
controller; Glyph has no server, no account and no analytics.

The blueprints can go back to what was showing, after a time or when another
trigger fires, and respect quiet hours and a cooldown. If someone changes the
display in the meantime, it leaves their choice alone. The guide has four
recipes in it.

Limits: the blueprints haven't had a live Home Assistant run yet, so they're
beta. Glyph can't draw a Home Assistant entity (a temperature) on the display
yet; HA picks what plays. It's Android only, free, MIT-licensed code.

Guide: https://github.com/spandan-kumar/glyph/blob/main/docs/HOME_ASSISTANT.md
Repo: https://github.com/spandan-kumar/glyph

### 5b. r/esp32

- **Date:** Tue 10 Nov 2026 (different hour from 5a)
- **Asset:** Clip A
- **Flair/format to check:** "I made a thing!" and say clearly in the body
  that it's an app, not a build. Avoid the "advertisement" flair confusion.
- **Angle:** a weekend build that ends somewhere fun.

**Title:** I made a thing! An app so your first ESP32 + LED matrix build ends with something to look at

**Body:**

[clip A]

The common wall with a first WLED matrix build isn't the soldering. It's the
afternoon after: the panel is wired, and it shows a rainbow and nothing else.

A typical weekend build: a 16x16 WS2812B panel (256 LEDs), an ESP32 running
WLED 16 (install at install.wled.me), a 5 V supply with a separate power feed
to the panel, and wiring. Roughly US$40 to 80 depending on supplier, before
tools and shipping. Then I made Glyph, a free Android app, for the
remaining part: a setup wizard for the 2D layout, 13,000+ animations, a
pixel editor, games with your phone as the controller, and album art.

The phone renders every frame, so even small controllers work. It streams
over DDP, or you tap Send and the ESP32 plays a baked GIF without the phone
(that needs an ESP32-family chip with free storage and WLED 16+). A 16x16 frame is
768 bytes, so 40 fps over UDP is about 30 KB/s.

Free, MIT-licensed code, no account. Android 7+, 64-bit ARM. Not a firmware
(it needs WLED already on the board), and it hasn't been tested on a
never-configured controller or a physical multi-panel grid yet.

Code: https://github.com/spandan-kumar/glyph
APK: https://github.com/spandan-kumar/glyph/releases/latest

### 5c. r/fossdroid

- **Date:** Wed 11 Nov 2026
- **Asset:** Clip C or A (a short clip; screenshots of Settings > privacy
  optional)
- **Flair/format to check:** unverified; rules page. The sub's purpose is
  FOSS on Android, so promotion is the point, but keep it factual.
- **Angle:** openness, no tracking, how to get it today, F-Droid pending.

**Title:** Glyph: MIT-licensed Android app for WLED LED matrices, no account or tracking (F-Droid merge request open)

**Body:**

I made Glyph, an Android app for WLED LED matrices. It's licensed MIT (the code;
artwork terms vary and are listed in the README), has no account, no ads and no
analytics, and talks to the devices on your Wi-Fi. The only other network
calls are optional: Open-Meteo for weather and air quality, and GitHub Pages
for catalog updates, and only when you check. The privacy details are in
`docs/PRIVACY.md`.

How to get it today: download the signed APK from the GitHub release (its
SHA-256 is next to it), or add the repo to Obtainium. It is **not on F-Droid
yet**: the merge request is open and I'm waiting for review. It's not on the
Play Store either. Android 7+, 64-bit ARM.

It's a Flutter app; the engine is plain Dart. Notification alerts (an option)
send only the app's logo to the display, never message content. I use AI
coding assistants and review and test everything myself on real hardware.

Repo: https://github.com/spandan-kumar/glyph
Latest APK: https://github.com/spandan-kumar/glyph/releases/latest
Obtainium: https://apps.obtainium.imranr.dev/redirect?r=obtainium://add/https://github.com/spandan-kumar/glyph

### 5d. r/androidapps

- **Date:** Wed 11 Nov 2026
- **Asset:** Clip C (album art on the panel)
- **Flair/format to check:** developer-post format or flair. Rules unverified;
  read them before drafting. Some subs want free-of-charge disclosure.
- **Angle:** one visual feature, plain eligibility.

**Title:** [Dev] Glyph: puts your phone's album art on an LED matrix (Android 7+, free, open source)

**Body:**

[clip C]

I made this. Glyph is a free, open-source app for WLED LED matrices. The part
I think this sub will like: Now Playing takes the cover of whatever your
phone is playing (Spotify, YouTube Music, any player) and draws it on the
matrix with a progress bar. Covers aren't stored on your phone or the device.

It also has 13,000+ animations, a pixel editor that draws on the matrix live,
seven games with your phone as the controller, and a setup wizard for the
matrix itself.

To be clear about who it's for: you need a WLED LED matrix on your Wi-Fi. If
you don't have one, "Try without a device" lets you browse and play on your
phone. No account, no ads, no tracking. MIT-licensed code, artwork terms vary.

Requirements: Android 7+ on a 64-bit ARM phone. It's sideloaded for now: get
the APK from GitHub or add it to Obtainium. Not on the Play Store yet. No iOS.

https://github.com/spandan-kumar/glyph/releases/latest

[check against the shipped build: the first-run no-device button was "Just
looking around" before 1.4.10; use whichever wording the release has]

### 5e. r/coolgithubprojects

- **Date:** Thu 12 Nov 2026
- **Asset:** Clip A as the post media, or a link post to the repo with the
  clip in a comment
- **Flair/format to check:** the repo-link post flair. Rules unverified.
  Keep short.
- **Angle:** the repo itself.

**Title:** Glyph: Flutter app that sets up and drives WLED matrices (pure-Dart engine, DDP streaming, GIF encoder)

**Body:**

I made Glyph, a free MIT-licensed Flutter app that sets up and drives WLED LED
matrices. The phone renders every frame in a pure-Dart engine, then streams it
over DDP or bakes a GIF and sends it to the controller.

In the repo: 62 procedural effects, 356 sprites, a custom GIF encoder, a
text-grid sprite format (so contributing art is a small PR), a setup wizard,
Home Assistant blueprints, and around 1,000 tests. It also has a `skills/`
folder so an AI agent can draw a sprite and open the pull request.

The repo is a small project, and contributions are welcome. There are good
first issues, and CONTRIBUTING.md covers the sprite format and art
licensing. Android only for now.

https://github.com/spandan-kumar/glyph

### 5f. r/FlutterDev

- **Date:** Thu 12 Nov 2026
- **Asset:** Optional: a short clip; the post is the write-up
- **Flair/format to check:** it has a weekly showcase thread (unverified):
  check whether the sub wants this as a standalone post or in that thread.
  The write-up must be public first: `blog-phone-renders-every-frame.md`
  (fix the stale counts before publishing it).
- **Angle:** the engineering.

**Title:** Streaming 40 fps to an LED matrix from Flutter: a pure-Dart renderer, DDP over UDP and a hand-written GIF encoder

**Body:**

I wrote up how Glyph, my Flutter app for WLED matrices, draws on a 16x16
panel: [blog link].

The short version of the design:

- `lib/engine` is pure Dart with no Flutter imports. A frame is a `Uint8List`
  of RGB bytes, and an effect implements `render(Frame, t, dt, Params,
  Palette)`. The same engine draws the previews and the real LEDs, and it runs
  in isolates and `dart run` tools.
- Streaming is a small DDP sender on `dart:io`: a 10-byte header, 1,440-byte
  chunks, push flag on the last packet, buffers reused between frames.
- Send bakes a seamless-loop GIF with my own encoder (shared palette, delta
  rectangles, transparency) and uploads it. One surprise: WLED's GIF loader
  doesn't reset the frame delay between files, so a long hold in one GIF
  blanks the next. The encoder caps every frame at one second.
- Android specifics (joining a Wi-Fi network without internet, notification
  listener, album art from media sessions) sit behind a platform channel, so
  the rest stays testable.

Tests use fakes for the device (`MockClient` and a fake WLED), and widget
tests never `pumpAndSettle` because the previews tick forever.

Honest context: I build this with AI coding assistants and review and test on
real hardware. Code is MIT: https://github.com/spandan-kumar/glyph. Android
only for now.

---

## 6. Lemmy, Mastodon, Bluesky

### 6a. Lemmy: !opensource@lemmy.ml

- **Date:** Wed 11 Nov 2026
- **Asset:** Clip A (upload as media) with alt text
- **Format to check:** community rules; there may be a self-promotion cap with a
  FOSS exemption. Read first.

**Title:** Glyph, an MIT-licensed Android app for WLED LED matrices (no account, no tracking)

**Body:** I made this. Glyph sets up a WLED matrix and fills it with 13,000+
animations, a pixel editor, games and album art. The phone renders every frame
and either streams it or sends it to the device. Code is MIT; artwork terms
vary. No account, no analytics, no server of mine. F-Droid merge request is
pending; for now sideload the APK or use Obtainium. Android 7+, 64-bit ARM.
https://github.com/spandan-kumar/glyph

### 6b. Lemmy: !android@lemmy.world

- **Date:** Wed 11 Nov 2026 (later in the day than 6a)
- **Asset:** Clip C with alt text
- **Format to check:** rules; app posts may need a specific tag.

**Title:** I made an app that shows your phone's album art on a WLED LED matrix

**Body:** Glyph's Now Playing mirrors whatever your phone plays onto a WLED
matrix, with a progress bar. It needs an LED matrix running WLED, but there's a
no-device mode to look around [use the shipped wording]. Free, open source, no account.
Android 7+, 64-bit ARM, sideload or Obtainium. Not on the Play Store.
https://github.com/spandan-kumar/glyph

### 6c. Lemmy: !homeassistant@lemmy.world

- **Date:** Wed 11 Nov 2026
- **Asset:** Screenshot of a blueprint form or clip A
- **Format to check:** rules; project posts may need a tag.

**Title:** Two blueprints to trigger looks on a WLED matrix from automations (local, beta)

**Body:** I made blueprints for a free Android app called Glyph. They show a
Saved look or play a Show on a WLED matrix when something happens, then go
back to what was playing. They use the built-in WLED integration and have
quiet hours and a cooldown. Beta: they have not had a live Home Assistant run
yet. https://github.com/spandan-kumar/glyph/blob/main/docs/HOME_ASSISTANT.md

### 6d. Mastodon (500 characters)

- **Date:** Wed 11 Nov 2026
- **Asset:** Clip A, with alt text below
- **Format to check:** Content warning not needed. Add the video, alt text and
  tags. Post from your own account.

> I made Glyph: a free Android app that sets up your WLED LED matrix in a few
> taps, then fills it with 13,000+ animations. Swipe to change what's showing,
> tap Send, and the panel keeps playing with the phone off.
>
> MIT-licensed code, no account, no tracking. Sideload or Obtainium; F-Droid
> pending. Android only for now.
>
> https://github.com/spandan-kumar/glyph
>
> #WLED #LEDMatrix #PixelArt #HomeAssistant #ESP32 #FOSS #Android #opensource

**Alt text for clip A:** A 16 by 16 LED panel beside a phone in a dim room. A
finger swipes on the phone's screen and the animation on the panel changes
three times. The person taps Send, then turns the phone's screen off, and the
panel keeps playing an animation. [adjust to the final footage]

### 6e. Bluesky (300 characters)

> I made Glyph, a free Android app that sets up your WLED LED matrix and fills
> it with 13,000+ animations. Tap Send and it plays on its own. MIT code, no
> account. Android only for now.
> https://github.com/spandan-kumar/glyph
> #WLED #pixelart #LEDmatrix #opensource

**Alt text for clip A:** same as Mastodon above.

---

## 7. Hackaday tip

- **Venue:** tips@hackaday.com (or hackaday.com/submit-a-tip/)
- **Date:** Thu 12 Nov 2026
- **Asset:** Clip A link, repo link, blog link. No press-release attachments.
- **Format to check:** descriptive subject, no press-release tone, one
  engineering hook. If skipped, resubmit once after about a week.
- **Before sending:** consider reporting the frame-delay quirk to the WLED
  repo. I could not confirm it has been reported.

**Subject:** Phone app renders every frame for WLED matrices; WLED's GIF player carries one file's frame delay into the next

**Body:**

Hi Hackaday,

I made Glyph, a free, MIT-licensed Android app that drives WLED LED matrices.
The unusual design choice is that the phone renders every frame, in a pure
Dart engine, so a small controller does not limit what runs. It streams RGB
over DDP, or bakes a looping GIF with a custom encoder and uploads it so the
panel plays without the phone.

Two things I found along the way that might interest your readers:

- In WLED 16.0.1, `image_loader.cpp` never resets `currentFrameDelay`, so a
  long frame wait in one GIF carries into the next file and the display looks
  blank until it runs out. The encoder caps every device frame at one second.
- Live DDP frames skip WLED's gamma when `if.live.no-gc` is true, so the app
  applies gamma and white balance itself to keep low-brightness colours stable.

Write-up: [blog link]. Clip: [clip A link]. Code: https://github.com/spandan-kumar/glyph

It's Android only and developed on a 16x16 panel; grids are tested in software.
Thanks for a look.

Spandan Kumar

---

## 8. Show HN

- **Venue:** news.ycombinator.com/submit
- **Date:** only if a real story emerges (a creator video, a striking build); then a Sunday, 12:00 UTC (5:30 pm in India)
- **Asset:** None to attach. The first comment links the clip and the blog.
  Only post with the blog published and clip A live.
- **Format to check:** title starts "Show HN:", submit the repo or site URL,
  post the story as the first comment within a minute. Be present all day. Don't
  ask anyone to upvote. WLED-matrix Show HNs with no story got 1 to 3 points.

**Title:** Show HN: Glyph, an open-source app that fills your WLED matrix (found a WLED GIF delay quirk)

**URL:** https://github.com/spandan-kumar/glyph

**First comment (story, not features):**

A GIF I uploaded made my LED panel go dark for minutes, and nothing in the file was wrong.

I'd been sending animations to a WLED controller as baked GIFs, and one of them
would blank the display for a long time after another had finished. The cause,
in the WLED 16.0.1 source: `image_loader.cpp` never resets `currentFrameDelay`
between files, so a long hold at the end of one GIF becomes the wait before the
first frame of the next. My fix is boring: the encoder caps every device frame
at one second. Finding it was not.

That's the project in miniature. Glyph is an Android app where the phone
renders every frame (a pure-Dart engine, nothing from Flutter in it) and either
streams RGB to the matrix over DDP or bakes a looping GIF and uploads it so
the panel plays without the phone. I wrote my own GIF encoder (shared palette,
delta rectangles) and handled the colour side too: live frames skip WLED's
gamma, so the app applies it, otherwise low-brightness colours drift.

[maintainer: add one or two sentences here on why you started: what the
original matrix was, and the moment you decided a phone app was the fix. I
have not invented a backstory.]

Around that sits a setup wizard (it asks which corner lit up and writes the
2D layout), 13,000+ animations, a live pixel editor, seven games with the
phone as the controller, and album art. No account, no analytics, no server of
mine. The code is MIT; the artwork terms vary and are in the README.

Limits: Android 7+ and 64-bit ARM only, no iOS. Developed on WLED 16.0.1 with an
ESP32 and a 16x16 panel. The wizard hasn't run on a factory-fresh controller,
multi-panel grids are tested in software only, and I haven't had a live run of the
Home Assistant blueprints. I use AI coding assistants and review and test
everything myself on real hardware.

You don't need a matrix to look around (a no-device mode is on the first
screen). Clip: [clip A link]. Write-up: [blog link].

---

## 9. Creator pitch emails

Rules from the research: 120 to 180 words in total, personal, the subject
names the video you watched, one clip link, no sponsorship or paid-review
ask, one follow-up after 2 to 3 days. Contact routes were not retrievable
from YouTube About pages (captcha). Check each channel's About tab, public
website or Discord by hand, and don't send until you've watched the video you
cite. **Date:** Phase 3, starting Mon 16 Nov 2026. Order: MyBritishComputerGuy
first, then Smart Home Junkie and DrZzs, then Core Electronics and Chris
Maher last, with the polished clip and any coverage so far.

**Subject line pattern:** `Free WLED matrix app, after your [video title]`

### 9.0 Template

> Hi [Name],
>
> [Tailored first paragraph, see below]
>
> I made Glyph, a free, open-source Android app for WLED matrices (MIT, no
> account). It sets up the 2D layout with a "which corner lit up?" test, then
> fills the panel with 13,000+ animations, and Send makes it play without the
> phone. Here's 15 seconds on a real panel: [clip B link].
>
> I'm not asking for a review or paying for one. It's free; try it on a panel
> you already have if it's useful. I've only tested a 16x16 so far, so I'd
> value knowing what breaks on yours. Android only, no iOS. Links:
> github.com/spandan-kumar/glyph
>
> Spandan Kumar

### 9.1 Chris Maher

- **Reference:** "Matrix Panels Just Got INSANE with WLED v16 Update" (73.6K,
  3 months ago); "MAJOR Brand Goes All IN on WLED!!" (103K, about 2 weeks
  before 18 Oct). Contact: his About tab (not retrievable).
- **Note:** He is the top WLED matrix teacher. Send with a polished clip A
  and no hardware claims beyond the 16x16.

**Tailored first paragraph:**

Hi Chris, I watched "Matrix Panels Just Got INSANE with WLED v16 Update". WLED
16 made GIFs and 2D matrices much easier, and two things still seem to
trip people up: getting the matrix layout right, and finding something
good to put on it. Glyph is my attempt at both.

### 9.2 Smart Home Junkie

- **Reference:** "Install Awtrix NG on the Ulanzi TC002 ... Home Assistant
  Voice Display" (12K views, a day old on 18 Oct); "This is the BEST MATRIX
  DISPLAY CLOCK for Home Assistant!" (177K).
- **Note:** Be honest that Glyph needs a WLED matrix, not a Ulanzi running
  Awtrix. The angle is the HA blueprints, flagged as beta.

**Tailored first paragraph:**

Hi, I watched your Awtrix NG on the Ulanzi TC002 video. The pixel display that
doubles as a Home Assistant screen is the thing I'm after too, just on WLED
matrices. If any of your viewers run WLED rather than Awtrix, here's something
for them. I added two Home Assistant blueprints (a Saved look, or a Show,
when something happens). They haven't had a live HA run yet, so I'm saying so
up front.

### 9.3 DrZzs

- **Reference:** "It died, we rebuilt it - DIY LED Sphere Reborn!" (113K, a
  month ago). His xLights and LedFx videos are linked from WLED's own
  compatible software page.
- **Note:** Runs a Discord community; mention the Discord only if it's
  welcome.

**Tailored first paragraph:**

Hi, I watched "It died, we rebuilt it". I'm writing because your WLED and
xLights videos are where many people start with WLED, and there's a gap
after the wiring: what to put on a matrix once it works. I made a free tool
for that. I also found a quirk in WLED's GIF player that your tinkerers
might want to know about.

### 9.4 Core Electronics

- **Reference:** "Custom Pixel Art with NO CODE on Any LED Grid - GlowBit
  Matrix With WLED" (128K, three years ago) and the GlowBit Orb kit (10 months
  ago). Editorial contact route is unverified: use their public contact page.
- **Note:** I haven't tried a GlowBit matrix; say so.

**Tailored first paragraph:**

Hi Core Electronics team, your "Custom Pixel Art with NO CODE on Any LED Grid"
video is still the clearest one on how to put your own art on a GlowBit
matrix with WLED, and it's why I'm writing. I built a free Android app for
the same audience. I haven't tried it on a GlowBit panel, and I'd love to know
whether it works on yours, since it was developed on a 16x16 WS2812B.

### 9.5 MyBritishComputerGuy

- **Reference:** "How To Create Pixel Art on any LED Matrix with WLED, No
  Coding Needed" (18.6K, two years ago) and "WLED Segments for Beginners"
  (12K, six months ago).
- **Note:** A small channel that probably replies. Be warm and specific.

**Tailored first paragraph:**

Hi, I watched "WLED Segments for Beginners" and your no-code pixel art video.
Both suit someone with a first matrix, which is who I made Glyph for.

**Follow-up (2 to 3 days later, one only):**

> Hi [Name], a short nudge in case my note got buried. There's a 15 second
> clip on a real panel here: [clip B link]. No pressure at all. If it isn't
> a fit, thanks for reading.

---

## 10. Adafruit blog tip

- **Venue:** adafruit.com/contact_us, category "Cool thing for the Adafruit
  Blog!"
- **Date:** Phase 3 (from 16 Nov)
- **Asset:** URL plus clip A link
- **Format to check:** title, URL and a short description, per Adafruit's
  guide. They don't feature crowdfunding or negative content. Adafruit
  covers WLED matrix guides; Glyph is a looser fit than CircuitPython, so
  keep it modest.

**Title:** Glyph, a free open-source Android app for WLED LED matrices

**URL:** https://github.com/spandan-kumar/glyph

**Description:** Glyph is an MIT-licensed Android app that sets up a WLED 2D
matrix with a "which corner lit up?" wiring test, then fills it with 13,000+
animations, a live pixel editor, games and album art. The phone renders every
frame and either streams it over DDP or bakes a GIF for WLED's Image effect.
Developed on an ESP32 with a 16x16 WS2812B panel. Video: [clip A link].

---

## 11. Reply bank

Short, honest answers for recurring questions. Reuse the wording; change it
if the question is different.

**How is this different from PixelForge or the WLED app?**
Use them too. Glyph is a phone app that sets up the 2D layout for you, brings
a 13,000-look library, draws and plays games live, and puts your music's album
art on the panel. It talks to WLED's normal API, so nothing else changes.

**Is there an iOS version?**
Not yet. It's Android only today (7+, 64-bit ARM). The code is Flutter, but I
haven't tested it on iPhone hardware, so I won't promise a date. I'll post here
if that changes.

**Is it AI-made?**
I built it with AI coding assistants. I review the code, and I test it
myself on a real WLED matrix, not only in unit tests. The repo has the tests
and the AGENTS.md that guides the assistants, if you want to look.

**Where do the animations come from?**
About 1,300 are effects and sprites made for the project (MIT), CC0 art with
credits, and public-domain originals such as The Starry Night and Dracula. The other ~12,000 are a collection of pixel art shared
with permission by its creator. The code is MIT; artwork terms vary, and that last collection isn't
covered by the MIT licence. The README lists the details.

**Why isn't it on the Play Store?**
Not yet, and I won't promise a date. For now it's a GitHub release you
sideload, with an Obtainium link for updates, and an F-Droid merge request is
open.

**Does it need internet or an account?**
No account, ever. The phone talks to your matrix over your Wi-Fi, and the
library is bundled, so it works offline. The only optional internet calls are
Open-Meteo for weather and air quality, and checking GitHub Pages for new
catalog items when you ask it to. No analytics, no Glyph server. Details:
docs/PRIVACY.md.

---

## 12. PR to wled/WLED-Docs: compatible software

- **Venue:** https://github.com/wled/WLED-Docs, file
  `docs/basics/compatible-software.md` (the page is
  https://kno.wled.ge/basics/compatible-software/)
- **Date:** Do now (Phase 0). It needs no video.
- **Format checked (18 Oct 2026):** The page is three tables (Controllers,
  Sources, Various) with `Name | Description` columns. Newer rows use leading
  and trailing pipes, older rows don't. Glyph fits **Controllers** ("use the
  WLED API to change the current light settings"). The page says "Still under
  construction, feel free to add to the list!"
- **Style rules (CONTRIBUTING and AGENTS):** friendly tone, contractions OK,
  short sentences, plain words, "only claim what the evidence supports", one
  topic per PR. No new page, so no `mkdocs.yml` change.
- **Where:** a new row near the top of the Controllers table, after Home
  Assistant. The list is roughly alphabetical but starts with Home Assistant;
  say in the PR that you're happy to move it.

**Exact Markdown line to add (Controllers table):**

```markdown
| [Glyph](https://github.com/spandan-kumar/glyph) | Free, open-source (MIT) Android app for 2D matrices. It has a setup wizard for the matrix layout, a library of 13,000+ animations, a live pixel editor and games. Streams frames over DDP, or sends a GIF to the device for the Image effect (WLED 16+ on ESP32). |
```

**Branch/commit:** `Add Glyph to compatible software`

**PR title:** Add Glyph to compatible software (Controllers)

**PR body:**

> Adds Glyph, a free open-source (MIT) Android app for WLED 2D matrices, to
> the Controllers table on the Compatible Software page. It's a one-line
> addition.
>
> How it uses WLED: the JSON API for state, presets and file upload, DDP for
> streaming frames, and `/upload` plus the Image effect for GIFs. Its setup
> wizard writes the 2D layout with `POST /settings/2D` and keeps a snapshot so
> Undo restores the old settings.
>
> Developed and tested with WLED 16.0.1 on an ESP32 with a 16x16 WS2812B
> panel. Link: https://github.com/spandan-kumar/glyph
>
> I'm the author. Glyph isn't affiliated with the WLED project. Happy to
> change the wording, shorten it or move the row.
