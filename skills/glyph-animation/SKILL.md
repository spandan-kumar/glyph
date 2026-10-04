---
name: glyph-animation
description: Create a new pixel-art animation (sprite) for the Glyph LED-matrix app and open a pull request with it. Use when someone asks to draw, design, add or contribute an animation, sprite, icon, emoji or pixel art for Glyph (github.com/spandan-kumar/glyph) or for a WLED matrix through Glyph, or to fulfil a Glyph "animation request" issue. Covers forking and branching, the original-or-public-domain licensing rule, picking a pack and id, LED-friendly design, writing the sprite JSON, validating and previewing it with a bundled zero-dependency Python script, rebuilding generated files, and the pull request.
license: MIT
---

# Glyph animation

Glyph plays pixel-art loops on WLED LED matrices. Each animation is a JSON
entry in a pack file in `assets/catalog/sprites/`, drawn with one character
per LED. This skill takes an idea to a merged-ready pull request.

Files next to this one:

- `reference.md`: the exact format (every field, colour syntax, shortcuts,
  palettes, categories, tags, seasonal shelves, `source`). Read it before
  writing JSON.
- `scripts/validate_sprite.py`: validator and PNG previewer (Python 3, no
  packages). Mirrors the app's parser and tests.
- `examples/paper-boat.json` + `paper-boat.png`: a complete, validated sprite.

Paths below are relative to the Glyph checkout, where this skill also lives
at `skills/glyph-animation/`.

## 1. Get the repo and a branch

If you are already in a Glyph checkout (it has `assets/catalog/sprites/`),
use it: `git checkout main && git pull`. Otherwise:

```bash
gh repo fork spandan-kumar/glyph --clone && cd glyph   # needs `gh auth login`
```

Without `gh`, fork on github.com and `git clone` your fork. Then:

```bash
git checkout -b animation/<id>    # e.g. animation/paper-boat
```

## 2. Pin down the idea

If the request is vague, ask once, briefly: subject, size (16×16 default),
main colours, motion, occasion. If the user doesn't care, proceed with
sensible defaults and say what you chose. If it fulfils an issue, read it
(`gh issue view N`) and note the number for the PR.

## 3. Choose pack, category and id

- Prefer an existing pack: animals, faces (Emoji), food, gaming, holidays,
  legends, love, masterpieces, mini (8×8), nature, storybook, symbols,
  weather (`reference.md` → Pack file). A sprite can set `"category"` to
  reach shelves without a pack (Space, Water, Party, Chill, Fire & Energy…).
  The category must be one of `categoryOrder` in `tool/build_catalog.dart`.
- Pick a lowercase dashed `id` that is unique across **all** packs, and a
  title not already in the catalog:

```bash
grep -rn '"id": "paper-boat"' assets/catalog/sprites/      # must print nothing
grep -o '"title":"Paper Boat[^"]*"' assets/catalog/catalog.json   # should print nothing
```

The validator re-checks both.

## 4. Design for LEDs

- **Grid**: 16×16 unless asked otherwise; 8×8 minis and N×8 scrolling
  banners also work. Fill most of the grid with one big, simple silhouette.
- **Black is off.** Transparent (`.`) pixels are dark LEDs. Dark colours
  (under ~12% brightness) vanish on a dim panel; near-black reads as a gap,
  which is fine for eyes and outlines but not for fills.
- **Contrast** beats detail: 2–4 main colours, light/dark pairs for shading,
  and 1–2 highlight pixels (a white eye glint, a shine) for life.
- **Recolourable**: use `p:` palette colours for the main body (e.g.
  `"G": "p:0.55"`, darker `"g": "p:0.3"`) so users can recolour it; pick
  positions in the palette's bright range (check the stops in reference.md).
  Keep fixed `#RRGGBB` for things with a "true" colour (eyes, white sails).
- **Sparkle**: `t:#RRGGBB` twinkles (stars, glints, bubbles); `c:` cycles
  through the palette (party lights).
- **Loops**: the last frame flows into the first. Two to six frames is
  plenty: blink, wag, flicker, bob, wave. Change few pixels per frame.
- **Timing**: keep every step ≤ 1000 ms (the device caps GIF frames at 1 s);
  for a pause repeat a frame in `seq`, e.g. `"seq": [0, 0, 0, 0, 1]`.
- **Motion**: `still` (default), `bounce`, `float`, `sway`, `pulse`, `shake`,
  `scroll` (banners). Motion moves the whole drawing; for full-width scenes
  (water, ground) animate in the frames and keep `still`.

## 5. Write the JSON

Add an entry to the pack's `sprites` list (end of the list is fine). Reuse the
pack's `colors` letters where they fit, or add sprite-level `colors`. Keep
the file's existing indentation style. A complete example
(`examples/paper-boat.json`, here as it would sit in a pack):

```json
{
  "id": "paper-boat",
  "title": "Paper Boat",
  "tags": ["boat", "paper", "origami", "sea", "ocean", "waves", "sail", "summer", "calm", "blue"],
  "palette": "ocean",
  "category": "Water",
  "motion": "still",
  "ms": 260,
  "colors": {
    "W": "#FFFFFF", "u": "#AFC3DA", "Y": "#FFE9B0", "y": "#D9B26A",
    "c": "p:0.8", "O": "p:0.6", "o": "p:0.45", "t": "t:#FFFFFF"
  },
  "frames": [
    [
      "................",
      "..t.............",
      ".......Wu.......",
      "......WWuu....t.",
      ".....WWWuuu.....",
      "....WWWWuuuu....",
      "...WWWWWuuuuu...",
      ".YYYYYYYYYYYYYY.",
      "..YYYYYYYYYYYY..",
      "...yyyyyyyyyy...",
      "cc....cccc....cc",
      "OccOOOOcOccOOOOc",
      "OOOOOOOOOOOOOOOO",
      "OOooOOOOOOooOOOO",
      "OOOOOOooOOOOOOoo",
      "ooOOOOOOooOOOOOO"
    ],
    {"base": 0, "patch": [{"at": [0, 10], "rows": [
      "____cccc____cccc", "cOOOOcOccOOOOcOc", "OOOOOOOOOOOOOOOO",
      "ooOOOOOOooOOOOOO", "OOOOooOOOOOOooOO", "OOOOOOooOOOOOOoo"]}]},
    {"base": 0, "patch": [{"at": [0, 10], "rows": [
      "__cccc____cccc__", "OOOcOccOOOOcOccO", "OOOOOOOOOOOOOOOO",
      "OOOOOOooOOOOOOoo", "OOooOOOOOOooOOOO", "OOOOooOOOOOOooOO"]}]},
    {"base": 0, "patch": [{"at": [0, 10], "rows": [
      "cccc____cccc____", "OcOccOOOOcOccOOO", "OOOOOOOOOOOOOOOO",
      "OOOOooOOOOOOooOO", "ooOOOOOOooOOOOOO", "OOooOOOOOOooOOOO"]}]}
  ]
}
```

Frames 1–3 reuse frame 0 and repaint only the water (`_` clears a pixel in a
patch, `.` keeps it), so the waves roll under a steady boat while the
sparkles twinkle. Use full row lists when most pixels change.

## 6. Validate and look at it

```bash
python3 skills/glyph-animation/scripts/validate_sprite.py \
  --pack assets/catalog/sprites/<pack>.json --only <id> \
  --preview build/<id>.png
```

- Fix every `ERROR` (unknown colour letter, mismatched frame sizes, duplicate
  id, unknown palette/motion/category, bad seq or ms, blank sprite, catalog
  title clash). Read each `warning` and fix it unless it is deliberate.
- **Look at `build/<id>.png`** (each frame as LED dots, side by side). If you
  can view images, open it and ask: is the subject obvious at a glance? Is
  any part too dark or lost in the background? Does the motion read? If you
  cannot view images, re-read the rows as ASCII art, frame by frame.
- Iterate until it reads clearly at 16×16, then show the user the preview.
- Finally run `python3 skills/glyph-animation/scripts/validate_sprite.py --all`
  (whole library, must report 0 errors).

## 7. Rebuild generated files (if Flutter is available)

```bash
flutter --version     # Flutter 3.47+; on the maintainer's machine: export PATH="$HOME/development/flutter/bin:$PATH"
flutter pub get
dart run tool/sprite_preview.dart assets/catalog/sprites/<pack>.json --only '^<id>$'   # optional: app's own preview in build/sprite_preview/
dart run tool/build_sprites.dart
dart run tool/build_catalog.dart
flutter test test/engine/sprite_test.dart test/library
```

Commit the regenerated `lib/engine/generators/sprite_data.g.dart` and
`assets/catalog/catalog.json` with the pack. **Never edit those two files by
hand.** If Flutter isn't installed, skip this step, commit only the pack JSON,
and say so in the PR: the maintainer regenerates them, and CI's stale-data
test fails until then (expected).

## 8. Commit, push, open the pull request

```bash
git add assets/catalog/sprites/<pack>.json lib/engine/generators/sprite_data.g.dart assets/catalog/catalog.json
git commit -m "Add <Title> animation" -m "<one or two lines: what it is and why it fits the pack>"
git push -u origin animation/<id>
gh pr create --repo spandan-kumar/glyph --base main --title "Add <Title> animation" --body-file build/<id>-pr.md --label art
```

Don't commit the preview PNG. Only add the files you meant to change (check
`git status`). If `--label` fails (forks often can't set labels), rerun
without it; the maintainer adds `art`. Add `--label animation-request` too
when it fulfils an issue.

PR body template (write it to `build/<id>-pr.md`):

```markdown
## What and why

<Title>: <one sentence describing the animation>.
Closes #<N>            <!-- only if it fulfils an issue -->

- Pack / category: `<pack>.json` / <Category>
- Size, frames, timing: 16×16, <n> frames, <ms> ms per step (<loop> ms loop), motion `<motion>`
- Palette: `<palette>` (recolourable: yes/no)

## Preview

<!-- Drag build/<id>.png from the validator here. -->

Frame 0:
    <paste the 16 rows of frame 0 here>

## Licensing

<Original artwork, drawn for this PR and released under the project's MIT license.>
<or: Based on <work> (<year>) by <creator>, public domain because <reason>; see the `source` block.>

## Checks

- [x] `validate_sprite.py --all`: 0 errors
- [x] / [ ] Rebuilt `sprite_data.g.dart` and `catalog.json`; `flutter test test/engine/sprite_test.dart test/library` passes
      <!-- or: Flutter wasn't available, so the generated files are not included; please regenerate. -->
- [x] Original or public domain; no trademarked characters

Made with the glyph-animation agent skill. Credit: <contributor name/handle>.
```

After `gh pr create` prints the URL, tell the user: the PR link, the preview
path, and to drag the PNG into the PR description (the CLI can't upload
images). Animation PRs labelled `art` or `animation-request` appear under
**New animations** in the release notes.

## Use with any agent

- **Claude Code**: `/plugin marketplace add spandan-kumar/glyph`, then
  `/plugin install glyph-animation@glyph`. Or copy this folder to
  `~/.claude/skills/glyph-animation/` (or `.claude/skills/` in a project).
- **Codex, Cursor, Gemini CLI and others**: inside a Glyph checkout, point
  the agent at `skills/glyph-animation/SKILL.md` (AGENTS.md links it), or
  copy the folder into the tool's skills/rules directory.
- **Plain chat**: paste this file and `reference.md`, draw together, then run
  the validator yourself.
