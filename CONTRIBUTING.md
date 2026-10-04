# Contributing to Glyph

Thanks for being here. Glyph gets better every time someone adds a drawing,
reports a bug or fixes one. You don't need to know Flutter to contribute art:
sprites are plain text files.

- [Add an animation in 5 minutes](#add-an-animation-in-5-minutes)
- [Licensing: original or public domain only](#licensing-original-or-public-domain-only)
- [Code contributions](#code-contributions)
- [Reporting bugs and ideas](#reporting-bugs-and-ideas)
- [Good first issues](#good-first-issues)
- [Code of conduct](#code-of-conduct)

## Add an animation in 5 minutes

Every pixel-art animation in Glyph is a few lines of JSON in
[`assets/catalog/sprites/`](assets/catalog/sprites). Each file is a *pack*
(`animals.json`, `food.json`, `holidays.json`…). You draw with letters, one
string per row, one letter per LED.

### 1. Pick a pack

Add your sprite to the pack that fits best, or start a new file with the same
shape. A pack looks like this:

```json
{
  "pack": "animals",
  "category": "Animals",
  "colors": {
    "K": "#0C0C10",
    "W": "#FFFFFF",
    "O": "p:0.55",
    "o": "p:0.3",
    "b": "t:#9FE3FF"
  },
  "sprites": [ ... ]
}
```

- `pack` — a short id for the file.
- `category` — the shelf it appears on in the app. Use one of the existing
  categories (Animals, Nature, Food & Drink, Holidays, Love, Emoji, Weather,
  Gaming, Symbols, Space, Storybook…); the full list is `categoryOrder` in
  [`tool/build_catalog.dart`](tool/build_catalog.dart). A sprite can override
  it with its own `"category"`.
- `colors` — the shared colour key for every sprite in the pack (see below).

### 2. Draw it

Add an entry to `sprites`:

```json
{
  "id": "fish",
  "title": "Little Fish",
  "tags": ["fish", "sea", "ocean", "swim", "orange"],
  "palette": "autumn",
  "motion": "float",
  "ms": 260,
  "frames": [
    [
      "................",
      "................",
      "................",
      "......dd........",
      "b....dOOd.......",
      "...ooOOOOoo...oo",
      "..oOOOOOOOOo.oOo",
      ".oOWKOOOOOOOooOo",
      ".oOKKOOOOOOOOOo.",
      ".oOOOOOOOOOOooOo",
      "..oOOOOOOOOo.oOo",
      "...ooOOOOoo...oo",
      "......dd........",
      "................",
      "................",
      "................"
    ],
    [ "...second frame, same size..." ]
  ]
}
```

| Field | Required | What it does |
|---|:---:|---|
| `id` | yes | Unique across **all** packs, lowercase with dashes (`sleepy-cat`). The build fails on duplicates. |
| `title` | yes | The name people see in the app. |
| `tags` | yes | Search words: what it is, colours, moods, occasions (`diwali`, `halloween`, `christmas`… also put it on seasonal shelves). |
| `frames` | yes | A list of frames; each frame is a list of row strings. Every frame must be the same size. |
| `palette` | | The default colour theme for `p:` colours, e.g. `sunset`, `ocean`, `autumn`, `heart`, `halloween`, `mono`. The full list is in [`lib/engine/palette.dart`](lib/engine/palette.dart). Defaults to `rainbow`. |
| `motion` | | Extra movement on top of your frames: `still`, `bounce`, `float`, `sway`, `scroll`, `pulse` or `shake`. Defaults to `still`. |
| `ms` | | How long each frame shows, in milliseconds: one number for all, or one per step (20–10000). Defaults to 200. |
| `seq` | | The order frames play in, by index, e.g. `[0, 1, 2, 1]`. Lets you reuse frames; if you give a list of `ms`, it needs one per step. |
| `colors` | | Extra or overriding colours for this sprite only. |

**Size.** 16×16 is the standard and looks right on most panels; Glyph scales
it to whatever the device is. 8×8 minis are welcome too, and wide 8-row
strips (e.g. 60×8) become scrolling banners.

**Loops.** The last frame flows back into the first, so make the motion
cycle cleanly. The device caps every frame at 1 second, so for a long pause
repeat a frame in `seq` rather than giving it a huge `ms`.

### 3. Colours

Each letter (or digit) in a row maps to an entry in `colors`. These
characters are see-through, so the background shows:

- `.` and space — transparent.

A colour can be:

| Value | Meaning |
|---|---|
| `#RRGGBB` | A fixed colour, e.g. `"K": "#0C0C10"` for outlines. |
| `p:0.55` | A position (0–1) along the sprite's palette. People can recolour these in the app, so use them for the main body colour. `p:0.55*0.6` dims it to 60%. |
| `p:0.65!` | Same, boosted to full brightness so it stays readable on dark palettes. |
| `c:0.2` | A palette colour that slowly cycles through the palette over time. |
| `t:#FFFFFF` | A twinkling colour, great for stars, sparkles and bubbles. |

Tips for LEDs: pure black is "off", so dark outlines read as gaps; very dark
colours disappear at low brightness. Big, high-contrast shapes and a couple of
highlight pixels look best.

### 4. Shortcuts for bigger animations (optional)

Instead of a full list of rows, a frame can build on an earlier one:

```json
{"base": 0, "patch": [{"at": [4, 6], "rows": ["KK", "KK"]}], "shift": [0, -1], "flip": "h"}
```

- `base` — an earlier frame index, or the name of a shared drawing in the
  pack's `parts` object (see `faces.json`).
- `patch` — rows pasted at `[x, y]`; `.` and space keep what's underneath,
  `_` clears a pixel.
- `shift` — move the whole frame by `[x, y]`; `flip` — `"h"` or `"v"`.

### 5. Preview and rebuild

You need [Flutter](https://docs.flutter.dev/get-started/install) (3.47+) for
this step; ask in your pull request if you get stuck and we'll run it for you.

```bash
flutter pub get
dart run tool/sprite_preview.dart assets/catalog/sprites/animals.json --only fish   # PNG sheet to check your frames
dart run tool/build_sprites.dart    # compiles the packs into lib/engine/generators/sprite_data.g.dart
dart run tool/build_catalog.dart    # adds your sprite to assets/catalog/catalog.json
flutter test test/engine/sprite_test.dart test/library
```

Never edit `sprite_data.g.dart` or `catalog.json` by hand. The tests fail if
either is stale ("compiled data matches the JSON sources") or if your sprite
has a problem (unknown colour letter, frames of different sizes, duplicate
id, a frame that renders blank).

Then open a pull request with the JSON change, the two regenerated files and
a screenshot or clip. Credit yourself in the PR description; animation PRs
are listed under **New animations** in the release notes.

## Licensing: original or public domain only

Glyph is MIT-licensed (see [LICENSE](LICENSE)) and everything in it must be
safe to share:

- **Original work** — you drew it yourself and are happy to release it under
  the project's MIT license.
- **Public domain** — based on a work whose copyright has expired.
- **No trademarked or copyrighted characters**: no game, film, TV or brand
  mascots, logos or fan art of them, however small the sprite.
- No pixels traced or copied from other people's sprite sheets.

Drawings based on public-domain works carry a `source` block so the app can
show where they come from (see `masterpieces.json` and
`classic_cartoons.json`):

```json
"source": {
  "work": "Mona Lisa",
  "year": 1503,
  "creator": "Leonardo da Vinci",
  "basis": "What the drawing takes from the original: composition, pose, colours.",
  "jurisdiction": "worldwide",
  "notice": "Based on Leonardo da Vinci's \"Mona Lisa\" (c. 1503-1519) — public domain."
}
```

`jurisdiction` is where the work is public domain (`worldwide`, or `US` for
works such as 1928 films). When a character is still a trademark today,
the `notice` also says Glyph isn't affiliated with or endorsed by the owner,
and the drawing must follow the public-domain version, not the modern
design. In your PR, explain why the work is public domain.

## Code contributions

[AGENTS.md](AGENTS.md) is the guide for the codebase: layout, conventions,
commands, testing rules and WLED quirks. The short version:

- `flutter analyze` must report no issues and `flutter test` must pass; CI
  runs both on every pull request.
- The engine (`lib/engine`) stays pure Dart; the UI uses the design kit in
  `lib/ui/design`.
- In the app's words it's a **device**, you **Send** an animation, and the
  device has **Saved**, **Shows** and **Routines**.
- Keep pull requests focused, and include a screenshot or clip for anything
  visual.
- For bigger changes, open an issue or a discussion first so we can agree on
  the approach.

## Reporting bugs and ideas

The best way to report a bug is **Send feedback** in the app (Device tab): it
opens a prefilled issue with your app version, phone, WLED version, panel and
the last error, and you see everything before sending.

Otherwise, use the [issue forms](https://github.com/spandan-kumar/glyph/issues/new/choose):
bug report, animation request, support for my display, or idea and feedback.
Questions are best asked in
[Discussions](https://github.com/spandan-kumar/glyph/discussions).

## Good first issues

Issues labelled
[`good first issue`](https://github.com/spandan-kumar/glyph/labels/good%20first%20issue)
are small, well-described and a good way in: new sprites, festival packs,
fonts and translations. Comment on one to claim it.

## Code of conduct

Everyone taking part in Glyph is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md). Be kind; we're all here to make
lights do fun things.
