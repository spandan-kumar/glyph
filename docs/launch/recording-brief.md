# Recording brief: three short Glyph clips

For anyone filming Glyph on their own WLED matrix. Any panel size works, and
a size other than 16×16 is a bonus: it's the first real report from another
panel. The full storyboard, with shot-by-shot timings, is in
[video-storyboard.md](video-storyboard.md); this page is the short version.

## Before you film

- **Install the latest release** (v1.4.12 or newer) from
  [GitHub Releases](https://github.com/spandan-kumar/glyph/releases/latest).
  Note your phone, WLED version, controller and panel size; we'll credit
  the build in the post.
- **Phone:** turn on Do Not Disturb, hide notifications, and keep Wi-Fi
  names, passwords and IP addresses off screen. Use a neutral device name.
- **Panel:** brightness around 10–25% so colours don't clip. A diffuser
  helps. Dim room, soft light on your hand and phone.
- **Camera:** tripod, lock focus, exposure and white balance. Try 30 fps at
  1/60 s; if the LEDs band or flicker, try 1/30 s. Check a few seconds frame
  by frame before filming everything.
- **Content:** use Glyph's own effects and original sprites (plasma, fire,
  aurora, Halloween looks, Pixel Pals). Avoid anything that looks like a
  famous character. Use music and cover art you have the rights to (or skip
  clip C).
- Film **both vertical (9:16) and landscape (16:9)** takes if you can, with
  the phone and panel in the same shot. Keep 2 seconds of extra footage at the
  start and end of every action.

## The three clips

**Clip A (about 20 s, the most important one): "swipe, send, it keeps playing"**
1. Display tab: swipe the Stage two or three times; the panel changes each
   time (show the real delay, don't speed it up).
2. Turn a palette or motion knob; the panel follows.
3. Tap **Send** and wait for "Sent to your device".
4. Close the app or switch the phone off. Keep filming the panel for 10
   seconds: it keeps playing on its own.

**Clip B (about 15 s): "which corner lit up?"**
Device → Set up display. Film the wiring questions: the lit corner, the
direction of the run, the next run's start, then the upright arrow check.
If your matrix is already set up, the wizard's **Undo** puts your old layout
back afterwards; take a note of your 2D settings first anyway.

**Clip C (about 12 s, optional): album art**
Make → Now Playing with a song whose cover you're allowed to show; film the
cover and the moving progress bar on the panel. If that's awkward, film a
Glance weather card instead (don't show your location).

## Sending the footage

- Raw files from the camera plus the phone's screen recording if you have
  it (`adb shell screenrecord`, see the storyboard). No edits needed.
- Name them `A1.mp4`, `A2.mp4`, `B1.mp4`… and add a short text note: panel
  size, controller, WLED version, phone, and anything that looked wrong.
- Share a Drive/WeTransfer link with Spandan. Say how you'd like to be
  credited in the post (name, handle, or none).

## Also useful

While you're at it, anything that doesn't work on your panel size is gold:
wrong orientation, scaling, a Send that fails, the wizard picking the wrong
corner. Note it, or open an issue with the in-app **Send feedback**.
