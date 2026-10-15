# Glyph privacy policy

*Updated 15 October 2026 for the fully offline Pipplee collection.*

Glyph is a free, open-source (MIT) app that draws on your WLED LED display.
It has **no account, no ads, no analytics, no tracking and no Glyph server**.
The author does not collect your data and could not read it if they wanted to.
Everything below is checked against the source code, which you can read at
<https://github.com/spandan-kumar/glyph>.

## What leaves your phone

| What | Goes to | When | Optional? |
| --- | --- | --- | --- |
| Pictures, commands and settings for your display | **Your own WLED device**, on your Wi-Fi | Whenever you use the display | Core feature |
| Wi-Fi name and password (setup wizard only) | **Your own WLED device** | Only when you set up a new device | Yes |
| Phone clock and time zone | **Your own WLED device** | Automatically after setup and when you add a device, or when you tap Set the time | Automatic (only to your device) |
| Place name you type, or the places you saved (coordinates) | **Open-Meteo** (weather and air quality) | When you use Weather or Air quality | Yes |
| A request for the animation list (your IP address, like any web request) | **GitHub Pages** (`spandan-kumar.github.io`) | When you check for new animations; automatic daily checks are **off** until you turn them on | Yes |
| A request for an animation file not included in your app version (your IP address and the requested file) | **GitHub Pages** (`spandan-kumar.github.io`) | When you browse or play an unbundled animation that is not cached; the full bundled Pipplee collection needs no requests | Yes |
| A bug report, idea or request you choose to file | **GitHub** (a web page opened in your browser) | Only when you tap a feedback item and press Submit there | Yes |
| Chat invite | **Discord** (opens in your browser) | Only when you tap the link | Yes |
| Glyph app updates | **GitHub Releases** or your update app (for example Obtainium) | Only if you update that way. The app does not check for updates by itself | Yes |

Nothing else leaves your phone. In particular, **your microphone audio,
notification contents, music titles, creations, saved devices and device
addresses are never sent to the author or to any third party.**

## The details

### Your display (your local network)
Glyph talks directly to the WLED controllers you add, over your home Wi-Fi.
This uses WLED's normal web API (HTTP), a fast stream of picture frames
(UDP), and, to find devices, mDNS (Bonjour) plus an optional scan of the
devices on your Wi-Fi network for WLED controllers. None of this goes to the
internet. WLED's web API has no passwords, so anyone on the same Wi-Fi can
reach the device without Glyph; Glyph does not change that.

Glyph can send a GIF to your device, which stays on the device until you
delete it there or from Glyph.

### Setting up a new device (Wi-Fi password)
If you give the wizard your Wi-Fi name and password, they are sent only to
your WLED device so it can join your network. The wizard clears the password
from memory after sending, **does not save it and does not log it**. Because
WLED's own API is plain HTTP, that short hop between your phone and the
device is not encrypted; do it on your own network. The wizard also saves a
small note of the device's previous layout settings (for Undo). It holds no
Wi-Fi details.

### Device time
So routines run on time, Glyph sets your device's clock from your phone and
switches on WLED's internet-time (NTP) option with your time zone, after
setup and when you add a device (or when you tap Set the time). If your
device already had internet time on, Glyph keeps your settings. With it on,
the **device itself** asks an internet time server from time to time; you
can turn that off in WLED's Time settings. That traffic comes from your
device, not from Glyph.

### Weather and air quality (optional)
You search for a place by name, or pick one. Glyph then asks Open-Meteo
(<https://open-meteo.com>) for matching places, and for weather or air
quality at the coordinates of the places you saved. **The app never uses
your phone's GPS.** The requests include your IP address (as every web
request does), the text you searched, and a User-Agent that says "Glyph"
plus the version. Open-Meteo has its own privacy policy. Your saved places
are stored on your phone only.

### Animation catalog (optional)
Glyph includes over 13,000 catalogue entries offline. Optionally it can fetch new
ones from a static file host (GitHub Pages). The check downloads a signed
list and only a new file if it changed, and Glyph verifies the signature
before using it. No account or identifier is sent; GitHub can see your IP
address and the request, as with any website. A check runs when you tap it, or
daily if you turn on automatic checks (off by default). Downloaded
animations are cached on your phone.

From version 1.4.7, the complete Pipplee collection is included in the app.
Browsing, playing and using these animations in Rotations works offline,
including on a fresh install. Files are checked against the hashes in the app.
Older versions downloaded these files from GitHub Pages on first use.
The loader retains that verified, cached download fallback for files not
included in an app version. No account or identifier is sent.
**Glyph does not contact Pipplee's API or image host.**

### Feedback
**Device → Send feedback** does not send anything by itself. It opens your
browser to a pre-filled GitHub issue form. Nothing is submitted until you
read it and press Submit, and a GitHub account is needed to do so. The
pre-filled part has: the Glyph version, your phone model and Android (or
iOS) version, WLED version and display size, the number of saved devices,
whether you were streaming, free space on the device, and the last error
message Glyph showed in this session. Network addresses, device names, Wi-Fi
details and web links are removed from that error before it is shown. You
can edit or delete any of it before submitting. Issues on GitHub are public.
Other ideas and request links open similar forms with less in them.

### Microphone (Music)
When you use the music visualiser, Glyph listens through the microphone,
analyses the sound on your phone and sends only the resulting pictures to
your display. Audio is **not recorded, saved or sent anywhere**. Microphone
access is only asked for when you start this feature.

### Now Playing and notification alerts (optional, Android)
These use Android's "notification access" setting, which you turn on
yourself and can turn off at any time.

- **Now Playing** reads what your music app is playing (title, artist, album,
  cover art) so it can be drawn on your display. This stays on your phone,
  and the picture goes to your display.
- **Notification alerts** read **only which app posted a notification** (its
  package name), a timestamp, and that app's icon, so a logo can flash on
  your display. Glyph **does not read the text, title or any content** of
  your notifications, and stores only the list of apps you chose. Existing
  notifications are not read when you grant access.

### Home Assistant
Glyph has a help page for using your display with Home Assistant. It only
shows text you can copy. Glyph itself makes no network connection to Home
Assistant.

### Sharing and files
When you export or share an animation, Android's or iOS's share sheet opens
and **you** choose where it goes. Glyph does not upload it. Importing
reads only files you choose.

### Device settings page
"Device settings" shows your WLED device's own web page inside the app. That
page comes from your device on your local network.

## What is stored on your phone

Saved devices (name and address), your creations, favourites, recents, saved
places, high scores, which apps you chose for alerts, preferences (such as
the automatic-check switch), the downloaded catalog and animation-file caches, and a few
settings for the home-screen widget (device name, address and on/off state).
It stays in Glyph's private storage on your phone. The last error message is
kept in memory only and is gone when the app closes. Android may include app
data in your phone's normal backup (Google backup) depending on your phone's
settings; that is your operating system's feature, not Glyph's.

## Permissions

| Permission | Why |
| --- | --- |
| Internet, network and Wi-Fi state | Reach your display, weather and the catalog |
| Wi-Fi multicast, change Wi-Fi/network state, nearby Wi-Fi devices, location (Android 12 and older only) | Find devices with mDNS, and let the setup wizard join a WLED setup network. **Glyph does not read your location.** Android asks for it for Wi-Fi scanning on older versions |
| Microphone (and its foreground service) | Music visualiser, only when started |
| Foreground service, wake lock | Keep streaming to your display with the screen off, shown as a notification |
| Notifications | Show that streaming is running |
| Notification access (a Settings switch) | Now Playing and alerts, as described above |
| Local network and Bonjour (iOS) | Find and control your WLED device |
| Microphone (iOS) | Music visualiser |

Android also lets Glyph list which apps can be opened, so you can choose apps
for alerts, and see browsers and music players for its links and Now
Playing labels. This list is not sent anywhere. Glyph allows plain HTTP only
because WLED devices don't use HTTPS.

## Children

Glyph is not directed at children, collects no personal data from anyone and
has no accounts or chat. There is nothing to collect from a child.

## Deleting your data

The author holds none of your data, so there is nothing to ask them to
delete. To remove what's on your phone, clear Glyph's storage or uninstall
it. Files and presets on your WLED device belong to you; delete them in
Glyph or in WLED. Issues you posted on GitHub are public; ask GitHub to
remove them or edit them yourself. Open-Meteo and GitHub keep only their own
server logs under their own policies.

## Changes to this policy

If a future version changes what leaves your phone, this file will be updated
before that release and the date at the top will change. History is in git.

## Contact

Questions about privacy: open an issue at
<https://github.com/spandan-kumar/glyph/issues> or join the
[Discord](https://discord.gg/9EeCFZAFvk). For a security problem, see
[SECURITY.md](../SECURITY.md).
