# Glyph sprite format reference

Exact rules for pixel-art animations in `assets/catalog/sprites/*.json`, taken
from the code that reads them:

- parser: `lib/engine/generators/sprite.dart` (`Sprite.parsePackJson`)
- compiler: `tool/build_sprites.dart` → `lib/engine/generators/sprite_data.g.dart`
- catalog: `tool/build_catalog.dart` → `assets/catalog/catalog.json`
- tests: `test/engine/sprite_test.dart`, `test/library/full_catalog_test.dart`
- palettes: `lib/engine/palette.dart`; seasonal shelf: `lib/ui/tune/seasons.dart`

"Parser" below means the Dart parser; "validator" means
`scripts/validate_sprite.py`, which is stricter in a few places (noted).

## Pack file

```json
{
  "pack": "nature",
  "category": "Nature",
  "colors": { "K": "#0C0C10", "G": "p:0.55", "s": "t:#FFFFFF" },
  "parts": { "body": ["....", "..."] },
  "sprites": [ { ... }, { ... } ]
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `pack` | string | `"pack"` | Short id for the file. |
| `category` | string | `"Pixel Art"` | Shelf for every sprite in the pack. Must be in `categoryOrder` (below) or `build_catalog.dart` fails ("unknown category"). |
| `colors` | object | `{}` | Shared colour key: one character → colour value. |
| `parts` | object | `{}` | Named drawings (lists of row strings) that frames can use as `base`. Only `faces.json` uses them. |
| `sprites` | list | required | The sprites. |

Existing packs and their category: `animals.json` Animals ·
`classic_cartoons.json` Classic Cartoons · `faces.json` Emoji · `food.json`
Food & Drink · `gaming.json` Gaming · `holidays.json` Holidays ·
`legends.json` Monsters & Legends · `love.json` Love · `masterpieces.json`
Masterpieces · `mini.json` Symbols (8×8 minis, most override their category) ·
`nature.json` Nature · `storybook.json` Storybook · `symbols.json` Symbols ·
`weather.json` Weather. Categories without a pack (Space, Water, Party, Chill,
Fire & Energy…) are reached with a per-sprite `"category"` override, as
`gaming.json` does for its Space sprites.

## Sprite fields

| Field | Required | Type | Default | Rule |
|---|:---:|---|---|---|
| `id` | yes | string | — | Unique across **all** packs (`build_sprites.dart` throws on duplicates). Lowercase, digits, single dashes: `^[a-z0-9]+(-[a-z0-9]+)*$` (convention; the validator enforces it). |
| `title` | yes | string | the id | Shown in the app; must be non-empty (test). Keep it unique among catalog titles (see Catalog). |
| `tags` | yes | list of strings | `[]` | Must be non-empty (test). Lowercase; spaces allowed (`"new year"`). |
| `frames` | yes | list | — | 1–48 frames (test). See Frames. |
| `palette` | | string | `"rainbow"` | Must be a real palette id (test). Drives every `p:`/`c:` colour. |
| `motion` | | string | `"still"` | One of the motion names below. The parser silently treats unknown names as `still`; the validator errors. |
| `ms` | | number or list | `200` | Per-step duration in ms. The parser clamps each value to 20–10000; the validator errors outside that range. A list needs exactly one entry per `seq` step. |
| `seq` | | list of ints | `[0, 1, …, n-1]` | Play order by frame index; repeats allowed. Every index must be `0 ≤ i < frames.length`. |
| `colors` | | object | `{}` | Extra or overriding colours for this sprite (merged over the pack's). |
| `category` | | string | the pack's | Per-sprite shelf override; must be in `categoryOrder`. |
| `backdrop` | | number 0–1 | `0` | Default for the "Backdrop" control: fills transparent pixels with a soft palette glow. Rarely used (one sprite). |
| `source` | | object | — | Required for drawings based on public-domain works. See Source. |

Unknown fields are ignored by the parser; the validator warns.

## Frames

A frame is either a list of row strings (one character per LED) or a
shortcut object. All frames of a sprite must have the same width and height:
the size comes from the first row of the first frame, and any frame with a
different row count or row length is an error ("frames must all be WxH").

### Characters

- `.`, space and `_` are transparent everywhere.
- Every other character must be a key in `colors` (sprite's, then pack's),
  or the parser throws `no colour for "X"`.
- Keys are single characters; letters and digits are conventional
  (`K` outline, `W` white, upper/lower case for light/dark pairs).
- Keep rows ASCII (the validator rejects other characters).

### Shortcut frames

```json
{"base": 0, "patch": [{"at": [4, 6], "rows": ["KK", "_K"]}], "shift": [0, -1], "flip": "h"}
```

Applied in this order: `base` → each `patch` → `shift` → `flip`.

| Key | Meaning |
|---|---|
| `base` | An **earlier** frame index (`0 ≤ base < this frame's index`) or a name in the pack's `parts`. Required. Anything else: `unknown base`. |
| `patch` | List of `{"at": [x, y], "rows": [...]}`. Rows are pasted with their top-left at column x, row y. In a patch, `.` and space keep the pixel underneath, `_` clears it to transparent, any other character paints. Parts that fall outside the frame are clipped. |
| `shift` | `[x, y]`: move the whole drawing right by x and down by y (negative = left/up). Vacated pixels become transparent; pixels pushed off the edge are lost. |
| `flip` | `"h"` mirrors left↔right, `"v"` mirrors top↔bottom. |

Only these four keys are read; the validator errors on others.

## Colour values

| Value | Kind | Behaviour |
|---|---|---|
| `#RRGGBB` | fixed | Exactly that colour. |
| `p:v` | palette | `palette.at(v)`: position v along the sprite's palette gradient. Wraps, so `1.2` = `0.2` and negatives work. Recolourable in the app. |
| `p:v*k` | palette, dimmed | Same, every channel multiplied by k (e.g. `p:0.3*0.25`). |
| `p:v!` | palette, vivid | Lifted to full brightness and washed 15% towards white, so it stays readable on palettes with dark stretches. A colour whose brightest channel is under 24 becomes white. `!` goes last: `p:0.5*0.6!` (vivid first, then dimmed). |
| `c:v`, `c:v*k`, `c:v!` | cycling palette | Like `p:` but the position moves with time: `palette.at(v + t/4)`, a full trip through the palette every 4 s. |
| `t:#RRGGBB` | twinkle | That colour with brightness breathing between 45% and 100% (`sin(5t + 2.3·inkIndex)`), so each twinkle letter is out of phase with the others. |

Grammar the validator accepts (the parser accepts the same in practice):
`#[0-9A-Fa-f]{6}` · `t:#[0-9A-Fa-f]{6}` · `[pc]:NUM(\*NUM)?!?` where NUM is a
decimal such as `0.55`, `1`, `-0.1`.

A sprite is **recolourable** when it uses at least one `p:` or `c:` colour.
Recolourable sprites get alternate colourways in the catalog and respond to
the app's palette picker.

### Palette ids

`rainbow` `sunset` `ocean` `lava` `forest` `neon` `ice` `matrix` `aurora`
`synthwave` `christmas` `festive` `galaxy` `heart` `pastel` `halloween` `candy`
`ember` `gold` `mint` `cyberpunk` `toxic` `twilight` `sakura` `autumn`
`tropical` `deepsea` `desert` `royal` `arctic` `bubblegum` `fireice` (Fire &
Ice) `mono` (Moonlight: black → blue-grey → white) `blood` (Crimson) `spring`
`diwali` `emerald` `sapphire` `vaporwave` `peach` `cmy` (Print) `copper`

Stops (position, colour) for the most useful ones. Many palettes start and end
dark, so pick `p:` positions in the bright middle (roughly 0.4–0.9):

| id | stops |
|---|---|
| rainbow | 0 FF0000 · .17 FFAA00 · .33 55FF00 · .5 00FFAA · .67 0055FF · .83 AA00FF · 1 FF0000 |
| sunset | 0 1A0033 · .35 B0004F · .6 FF5A1F · .85 FFC94A · 1 1A0033 |
| ocean | 0 000A28 · .4 0047AB · .7 00C2C7 · .85 B8FFF5 · 1 000A28 |
| forest | 0 002200 · .4 1E7A1E · .7 9ACD32 · .85 3CB371 · 1 002200 |
| heart | 0 0A0002 · .35 5C0011 · .6 D00030 · .8 FF3366 · 1 FFC2D4 |
| gold | 0 140A00 · .4 7A4A00 · .7 E0A100 · .9 FFE27A · 1 FFFBE6 |
| autumn | 0 3B0D00 · .3 B23A00 · .55 F28C28 · .8 FFD166 · 1 3B0D00 |
| candy | 0 FF4FA3 · .3 FFB2E0 · .55 7FE7FF · .8 B18CFF · 1 FF4FA3 |
| halloween | 0 120018 · .35 6A0DAD · .6 FF6A00 · .85 7CFF00 · 1 120018 |
| christmas | hard bands: 0–.2 red E0101E · .25–.45 green 0FA33A · .5–.7 gold FFB627 · .75–.95 cream FFF4E0 |
| mono | 0 000000 · .6 7A8AA0 · 1 FFFFFF |
| toxic | 0 001400 · .4 3DFF00 · .7 D4FF00 · .85 00FFA2 · 1 001400 |

The full table is `lib/engine/palette.dart`; the validator reads it from
there (or uses an embedded copy outside a checkout) and renders `p:` colours
exactly as the app does.

## Timing and sequence

- Step i of `seq` shows frame `seq[i]` for `ms[i]` ms; the loop length is the
  sum. The last step flows back into the first, so design a clean cycle.
- The device caps every frame of a Sent GIF at **1 s** (AGENTS.md: GIF waits
  carry over between files on WLED). For a long hold, repeat the frame in
  `seq` (`"seq": [0, 0, 0, 1]`) instead of a big `ms`. The validator warns
  on steps over 1000 ms. (A few existing sprites stream with longer holds,
  e.g. the blinking `smile`; new art should not rely on it.)
- Typical values: 80–150 ms for fast action, 200–350 ms for gentle loops,
  500–1000 ms for slow blinks.

## Size

- **16×16** is the standard. Glyph scales by whole numbers to fit the panel
  (32×32 → 2×), and area-averages when shrinking (a 16×16 still reads at 8×8).
- **8×8** minis are welcome (`mini.json`).
- **Banners**: a sprite at least twice as wide as tall (`width ≥ 2·height`,
  e.g. 60×8) is fitted by height and should use `"motion": "scroll"`.
- Other sizes work but the validator warns.

## Motion names

Extra movement applied by the player on top of your frames, in device pixels
(`amp = max(1, round(0.07 · min(panelW, panelH)))`, i.e. 1 px on 16×16):

| Name | Movement |
|---|---|
| `still` | None (default). |
| `bounce` | Hops up: `abs(sin)` with a 0.7 s period, 1.5 × amp high. |
| `float` | Drifts up and down, sine, 2.6 s period. |
| `sway` | Drifts left and right, sine, 2.2 s period. |
| `scroll` | Slides in from the right and exits left at max(4, 0.45 × panel width) px/s. For banners. |
| `pulse` | Zooms ±9% about the centre, 1.1 s period. |
| `shake` | Random ±1 px jitter every 80 ms. |

Motions move the whole drawing, including any "ground" you draw, so a
full-width scene (water, grass) shows gaps at its edges with float/sway;
animate scenery in the frames and keep `still`.

## Categories (`categoryOrder`)

`Classic Cartoons` · `Storybook` · `Monsters & Legends` · `Masterpieces` ·
`Chill` · `Party` · `Emoji` · `Love` · `Holidays` · `Nature` · `Animals` ·
`Water` · `Weather` · `Space` · `Fire & Energy` · `Abstract` · `Hypnotic` ·
`Retro & Digital` · `Gaming` · `Science & Sims` · `Food & Drink` · `Symbols`

Classic Cartoons, Storybook, Monsters & Legends and Masterpieces hold
public-domain works with a `source` block.

## Tags

Tags feed search and the seasonal shelf. The catalog lowercases them and adds
`pixel art`, `sprite` and colour words for the palette (e.g. ocean → `blue`,
`teal`), so you don't need those.

**Occasion tags** (`occasionTags` in `build_catalog.dart`) add more tags
automatically when present, matched exactly:

| Tag on the sprite | Also added |
|---|---|
| `christmas` | `winter`, `holiday` |
| `halloween` | `autumn`, `october` |
| `valentine` | `love`, `february` |
| `diwali` | `festival`, `india` |
| `easter` | `spring` |
| `eid` | `ramadan`, `festival` |
| `hanukkah` | `winter`, `festival` |
| `new year` | `celebrate`, `winter` |
| `birthday` | `celebrate`, `party` |

**Seasonal shelf** (`seasonFor` in `lib/ui/tune/seasons.dart`): the app's
seasonal row shows items with any of these exact tags in each window:

| Dates | Shelf | Tags |
|---|---|---|
| Dec 26 – Jan 7 | New Year Countdown | `new year`, `nye`, `fireworks`, `celebrate` |
| Jan 8 – 31 | Winter Cozy | `winter`, `snow`, `cozy`, `cold` |
| Feb 1 – 15 | Valentine's Day | `valentine`, `love`, `heart`, `romantic` |
| Feb 16 – Mar 31 | Spring Festivals | `holi`, `eid`, `ramadan`, `spring`, `st patricks` |
| Apr | Easter & Spring | `easter`, `spring`, `bunny`, `flower` |
| May | In Bloom | `flower`, `garden`, `spring`, `butterfly` |
| Jun – Aug | Summer Vibes | `summer`, `beach`, `tropical`, `sun` |
| Sep | Hello Autumn | `autumn`, `fall`, `leaf`, `harvest` |
| Oct | Spooky Season | `halloween`, `spooky` |
| Nov 1 – 20 | Festival of Lights | `diwali`, `festival of lights`, `diya`, `lights` |
| Nov 21 – 30 | Harvest Time | `thanksgiving`, `harvest`, `autumn` |
| Dec 1 – 25 | Holiday Season | `christmas`, `hanukkah`, `winter`, `snow` |

Good tag set: what it is (`boat`, `paper`), synonyms (`origami`), setting
(`sea`, `ocean`), mood (`calm`), main colours, and any occasion/season.

## Catalog (what `build_catalog.dart` makes of a sprite)

- One item per sprite: id = slug of the title (lowercase, `&` → `and`,
  apostrophes dropped, other runs → `-`), category, palette, tags as above.
  If the title is already taken the item becomes `Pixel <Title>` /
  `pixel-<slug>`: pick a distinct title instead.
- Recolourable sprites in Love, Emoji, Animals, Food & Drink, Holidays,
  Gaming, Symbols, Nature, Weather, Space or Fire & Energy also get up to two
  colourway items such as `Neon <Title>` (skipped silently if taken).
- Every other non-banner sprite (fixed-colour, or recolourable in a category
  without colourways such as Water or Party) gets a `<Title> (Bounce)` item
  (or `(Float)` if the sprite already bounces) over a soft glow. **This title
  must be free**, or the catalog build fails with a duplicate title.
- Banners get a `<Title> (Rainbow)` (or `(Neon)`) item.
- Sprites with `source` get exactly one item, tagged `classic`,
  `public domain`, with the notice shown in the app; `(Classic)` is appended
  if the title is taken.

The validator checks these title clashes against the current `catalog.json`.

## Source (public-domain bases)

```json
"source": {
  "work": "Dracula",
  "year": 1897,
  "creator": "Bram Stoker",
  "basis": "What the drawing takes from the original: figure, pose, costume, colours. Say what it does NOT take from later copyrighted adaptations.",
  "jurisdiction": "worldwide",
  "notice": "Based on Bram Stoker's novel \"Dracula\" (1897) — public domain."
}
```

| Key | Type | Notes |
|---|---|---|
| `work` | string | Title of the original work or tradition. |
| `year` | int or null | First publication/release; `null` for folklore with no single date (`legends.json`). |
| `creator` | string | Author/artist; "Folklore" or similar for traditions. |
| `basis` | string | Which elements come from the public-domain original. |
| `jurisdiction` | string | `worldwide`, or `US` (e.g. 1928 films public domain in the US only). |
| `notice` | string | Shown to users. If a character is still a trademark today, add "Not affiliated with or endorsed by <owner>." and draw only the public-domain version. |

All six keys are present on every existing `source`; the validator requires
them. The app shows `notice`; the rest documents provenance for reviewers.

## Generated files

Never hand-edit these; regenerate with Flutter:

```bash
dart run tool/build_sprites.dart   # → lib/engine/generators/sprite_data.g.dart
dart run tool/build_catalog.dart   # → assets/catalog/catalog.json
```

Until they are rebuilt, `test/engine/sprite_test.dart` fails ("compiled
data matches the JSON sources") and `test/library/full_catalog_test.dart`
fails ("every generator and sprite is used"), so CI on a pull request
without them is red.
