#!/usr/bin/env python3
"""Validate and preview Glyph sprite packs. Zero dependencies (Python 3.8+).

Mirrors the rules of the Dart parser (lib/engine/generators/sprite.dart),
tool/build_sprites.dart, tool/build_catalog.dart and the sprite/catalog tests,
so a sprite that passes here should pass `flutter test` once the generated
files are rebuilt.

  validate_sprite.py --all                                  # every pack in the repo
  validate_sprite.py --pack assets/catalog/sprites/nature.json --only paper-boat
  validate_sprite.py --pack nature.json --only paper-boat --preview boat.png

Exit code: 0 when there are no errors (warnings are allowed), 1 otherwise.
"""
import argparse
import glob
import json
import math
import os
import re
import struct
import sys
import zlib

# ---------------------------------------------------------------------------
# Tables. Read from the repo when it is available (the source of truth);
# these copies (taken from lib/engine/palette.dart and tool/build_catalog.dart)
# are the fallback when the script runs outside a checkout.

PALETTES = [
    ('rainbow', 'Rainbow', [(0.0, 0xFF0000), (0.17, 0xFFAA00), (0.33, 0x55FF00), (0.5, 0x00FFAA), (0.67, 0x0055FF), (0.83, 0xAA00FF), (1.0, 0xFF0000)]),
    ('sunset', 'Sunset', [(0.0, 0x1A0033), (0.35, 0xB0004F), (0.6, 0xFF5A1F), (0.85, 0xFFC94A), (1.0, 0x1A0033)]),
    ('ocean', 'Ocean', [(0.0, 0x000A28), (0.4, 0x0047AB), (0.7, 0x00C2C7), (0.85, 0xB8FFF5), (1.0, 0x000A28)]),
    ('lava', 'Lava', [(0.0, 0x000000), (0.3, 0x800000), (0.6, 0xFF3300), (0.85, 0xFFCC00), (1.0, 0xFFFFCC)]),
    ('forest', 'Forest', [(0.0, 0x002200), (0.4, 0x1E7A1E), (0.7, 0x9ACD32), (0.85, 0x3CB371), (1.0, 0x002200)]),
    ('neon', 'Neon', [(0.0, 0xFF00CC), (0.33, 0x3300FF), (0.66, 0x00FFEE), (1.0, 0xFF00CC)]),
    ('ice', 'Ice', [(0.0, 0x000014), (0.5, 0x3399FF), (0.8, 0xCCF2FF), (1.0, 0xFFFFFF)]),
    ('matrix', 'Matrix', [(0.0, 0x000000), (0.6, 0x00A01E), (0.9, 0x55FF55), (1.0, 0xDDFFDD)]),
    ('aurora', 'Aurora', [(0.0, 0x020814), (0.25, 0x0B6E4F), (0.45, 0x2BFF88), (0.62, 0x19D3DA), (0.8, 0x7A3CFF), (1.0, 0xFF5FD2)]),
    ('synthwave', 'Synthwave', [(0.0, 0x2B0B5A), (0.3, 0xFF2A9D), (0.55, 0xFF9E3D), (0.75, 0x00E5FF), (1.0, 0x2B0B5A)]),
    ('christmas', 'Christmas', [(0.0, 0xE0101E), (0.2, 0xE0101E), (0.25, 0x0FA33A), (0.45, 0x0FA33A), (0.5, 0xFFB627), (0.7, 0xFFB627), (0.75, 0xFFF4E0), (0.95, 0xFFF4E0), (1.0, 0xE0101E)]),
    ('festive', 'Festive', [(0.0, 0xFF6A00), (0.3, 0xFFD000), (0.55, 0xFF1F7A), (0.8, 0x8B1EFF), (1.0, 0xFF6A00)]),
    ('galaxy', 'Galaxy', [(0.0, 0x05001A), (0.3, 0x3A0CA3), (0.5, 0x4361EE), (0.7, 0xF72585), (0.88, 0xFFD6A5), (1.0, 0xFFFFFF)]),
    ('heart', 'Heart', [(0.0, 0x0A0002), (0.35, 0x5C0011), (0.6, 0xD00030), (0.8, 0xFF3366), (1.0, 0xFFC2D4)]),
    ('pastel', 'Pastel', [(0.0, 0xFFB3BA), (0.25, 0xFFDFBA), (0.5, 0xBAFFC9), (0.75, 0xBAE1FF), (1.0, 0xFFB3BA)]),
    ('halloween', 'Halloween', [(0.0, 0x120018), (0.35, 0x6A0DAD), (0.6, 0xFF6A00), (0.85, 0x7CFF00), (1.0, 0x120018)]),
    ('candy', 'Candy', [(0.0, 0xFF4FA3), (0.3, 0xFFB2E0), (0.55, 0x7FE7FF), (0.8, 0xB18CFF), (1.0, 0xFF4FA3)]),
    ('ember', 'Ember', [(0.0, 0x000000), (0.4, 0x5A0A00), (0.7, 0xD9480F), (0.9, 0xFF9F1C), (1.0, 0xFFE8A3)]),
    ('gold', 'Gold', [(0.0, 0x140A00), (0.4, 0x7A4A00), (0.7, 0xE0A100), (0.9, 0xFFE27A), (1.0, 0xFFFBE6)]),
    ('mint', 'Mint', [(0.0, 0x00261C), (0.4, 0x00A878), (0.7, 0x7CF5C8), (0.9, 0xE6FFF6), (1.0, 0x00261C)]),
    ('cyberpunk', 'Cyberpunk', [(0.0, 0x0D0221), (0.3, 0xFF124F), (0.5, 0xFF00A0), (0.75, 0x00F0FF), (1.0, 0x0D0221)]),
    ('toxic', 'Toxic', [(0.0, 0x001400), (0.4, 0x3DFF00), (0.7, 0xD4FF00), (0.85, 0x00FFA2), (1.0, 0x001400)]),
    ('twilight', 'Twilight', [(0.0, 0x07051A), (0.35, 0x2E1F6B), (0.6, 0x8A4FFF), (0.82, 0xFF8BD1), (1.0, 0x07051A)]),
    ('sakura', 'Sakura', [(0.0, 0x2A0A1F), (0.4, 0xE85A9B), (0.7, 0xFFB7D5), (0.9, 0xFFF0F6), (1.0, 0x2A0A1F)]),
    ('autumn', 'Autumn', [(0.0, 0x3B0D00), (0.3, 0xB23A00), (0.55, 0xF28C28), (0.8, 0xFFD166), (1.0, 0x3B0D00)]),
    ('tropical', 'Tropical', [(0.0, 0x00B4D8), (0.3, 0x06D6A0), (0.55, 0xFFD166), (0.8, 0xFF6B6B), (1.0, 0x00B4D8)]),
    ('deepsea', 'Deep Sea', [(0.0, 0x000208), (0.45, 0x001F4D), (0.75, 0x006D77), (0.92, 0x83F0E8), (1.0, 0x000208)]),
    ('desert', 'Desert', [(0.0, 0x2B1300), (0.35, 0xA0522D), (0.65, 0xE9A15B), (0.88, 0xFFE0B2), (1.0, 0x2B1300)]),
    ('royal', 'Royal', [(0.0, 0x0A0033), (0.4, 0x3F1DCB), (0.7, 0xB58BFF), (0.88, 0xFFD54A), (1.0, 0x0A0033)]),
    ('arctic', 'Arctic', [(0.0, 0x001018), (0.4, 0x00A6C8), (0.75, 0xA8F2FF), (1.0, 0xFFFFFF)]),
    ('bubblegum', 'Bubblegum', [(0.0, 0xFF5CA8), (0.5, 0x5CE1FF), (1.0, 0xFF5CA8)]),
    ('fireice', 'Fire & Ice', [(0.0, 0x00103A), (0.25, 0x00A2FF), (0.5, 0xFFFFFF), (0.75, 0xFF6A00), (1.0, 0x3A0000)]),
    ('mono', 'Moonlight', [(0.0, 0x000000), (0.6, 0x7A8AA0), (1.0, 0xFFFFFF)]),
    ('blood', 'Crimson', [(0.0, 0x000000), (0.5, 0x8A0010), (0.85, 0xFF1A2E), (1.0, 0xFFC2C2)]),
    ('spring', 'Spring', [(0.0, 0x7BD389), (0.3, 0xFFF07C), (0.55, 0xFF9FBE), (0.8, 0xA0C4FF), (1.0, 0x7BD389)]),
    ('diwali', 'Diwali', [(0.0, 0xFF6F00), (0.3, 0xFFC400), (0.55, 0xD5006D), (0.8, 0x7B1FA2), (1.0, 0xFF6F00)]),
    ('emerald', 'Emerald', [(0.0, 0x001A0E), (0.45, 0x00875A), (0.75, 0x3EE89F), (0.92, 0xFFE9A8), (1.0, 0x001A0E)]),
    ('sapphire', 'Sapphire', [(0.0, 0x000822), (0.4, 0x0B3D91), (0.7, 0x4C8DFF), (0.9, 0xD6E6FF), (1.0, 0x000822)]),
    ('vaporwave', 'Vaporwave', [(0.0, 0xFF71CE), (0.33, 0x01CDFE), (0.66, 0x05FFA1), (0.85, 0xB967FF), (1.0, 0xFF71CE)]),
    ('peach', 'Peach', [(0.0, 0x3D1408), (0.4, 0xFF7F50), (0.7, 0xFFB38A), (0.9, 0xFFE5D1), (1.0, 0x3D1408)]),
    ('cmy', 'Print', [(0.0, 0x00C8FF), (0.33, 0xFF00B4), (0.66, 0xFFE600), (1.0, 0x00C8FF)]),
    ('copper', 'Copper', [(0.0, 0x120500), (0.4, 0x7C3A12), (0.7, 0xD9824A), (0.9, 0xFFD3A8), (1.0, 0x120500)]),
]

CATEGORY_ORDER = [
    'Classic Cartoons', 'Storybook', 'Monsters & Legends', 'Masterpieces',
    'Chill', 'Party', 'Emoji', 'Love', 'Holidays', 'Nature', 'Animals', 'Water',
    'Weather', 'Space', 'Fire & Energy', 'Abstract', 'Hypnotic', 'Retro & Digital',
    'Gaming', 'Science & Sims', 'Food & Drink', 'Symbols',
]

# spriteColourways in tool/build_catalog.dart: categories whose recolourable
# sprites get colourway items instead of a "(Bounce)"/"(Float)" look.
COLOURWAYS = {
    'Love': ['neon', 'gold', 'candy', 'galaxy', 'sapphire'],
    'Emoji': ['neon', 'candy', 'gold'],
    'Animals': ['tropical', 'candy', 'neon', 'sapphire'],
    'Food & Drink': ['candy', 'mint', 'neon'],
    'Holidays': ['gold', 'neon', 'candy', 'rainbow'],
    'Gaming': ['neon', 'gold', 'cyberpunk', 'toxic'],
    'Symbols': ['neon', 'gold', 'mint', 'candy', 'rainbow', 'blood'],
    'Nature': ['candy', 'sakura', 'gold'],
    'Weather': ['candy', 'neon', 'gold'],
    'Space': ['neon', 'gold', 'candy'],
    'Fire & Energy': ['arctic', 'toxic'],
}

MOTIONS = ['still', 'bounce', 'float', 'sway', 'scroll', 'pulse', 'shake']  # spriteMotionNames
TRANSPARENT = {'.', ' ', '_'}  # '_' also clears a pixel inside a patch
ID_RE = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
NUM = r'-?(?:\d+\.?\d*|\.\d+)'
PAL_RE = re.compile(r'^([pc]):(' + NUM + r')(?:\*(' + NUM + r'))?(!?)$')
HEX_RE = re.compile(r'^#([0-9A-Fa-f]{6})$')
TWINKLE_RE = re.compile(r'^t:#([0-9A-Fa-f]{6})$')
MAX_FRAMES = 48       # test/engine/sprite_test.dart
MS_MIN, MS_MAX = 20, 10000
DEVICE_FRAME_CAP_MS = 1000  # WLED GIFs cap each frame at 1 s
PACK_KEYS = {'pack', 'category', 'colors', 'parts', 'sprites'}
SPRITE_KEYS = {'id', 'title', 'tags', 'palette', 'motion', 'ms', 'seq', 'frames',
               'colors', 'category', 'backdrop', 'source'}
SOURCE_KEYS = ['work', 'year', 'creator', 'basis', 'jurisdiction', 'notice']


def find_repo(explicit):
    if explicit:
        return explicit
    for start in (os.getcwd(), os.path.dirname(os.path.abspath(__file__))):
        d = start
        while True:
            if os.path.isdir(os.path.join(d, 'assets', 'catalog', 'sprites')):
                return d
            parent = os.path.dirname(d)
            if parent == d:
                break
            d = parent
    return None


def load_tables(repo):
    """Palettes and categories from the checkout, else the embedded copies."""
    palettes, cats = PALETTES, CATEGORY_ORDER
    if repo:
        try:
            src = open(os.path.join(repo, 'lib', 'engine', 'palette.dart'), encoding='utf-8').read()
            found = []
            for m in re.finditer(r"Palette\('(\w+)',\s*'([^']*)',\s*\[(.*?)\]\)", src, re.S):
                stops = [(float(a), int(b, 16)) for a, b in
                         re.findall(r'\(([\d.]+),\s*0x([0-9A-Fa-f]{6})\)', m.group(3))]
                found.append((m.group(1), m.group(2), stops))
            if found:
                palettes = found
        except OSError:
            pass
        try:
            src = open(os.path.join(repo, 'tool', 'build_catalog.dart'), encoding='utf-8').read()
            m = re.search(r'const categoryOrder = \[(.*?)\];', src, re.S)
            if m:
                cats = re.findall(r"'([^']+)'", m.group(1))
        except OSError:
            pass
    return palettes, cats


# ---------------------------------------------------------------------------
# Colour maths, ported from palette.dart / frame.dart / sprite.dart.

def dround(x):  # Dart's round(): half away from zero
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def bake(stops):
    lut = []
    for i in range(256):
        p = i / 255
        a, b = stops[0], stops[-1]
        for s in range(len(stops) - 1):
            if stops[s][0] <= p <= stops[s + 1][0]:
                a, b = stops[s], stops[s + 1]
                break
        span = b[0] - a[0]
        t = 0.0 if span == 0 else (p - a[0]) / span

        def ch(sh):
            x, y = (a[1] >> sh) & 255, (b[1] >> sh) & 255
            return dround(x + (y - x) * t)
        lut.append((ch(16) << 16) | (ch(8) << 8) | ch(0))
    return lut


def pal_at(lut, v):
    f = v - math.floor(v)
    return lut[int(f * 255)]


def scale_color(c, f):
    def ch(v):
        return max(0, min(255, int(v * f)))
    return (ch((c >> 16) & 255) << 16) | (ch((c >> 8) & 255) << 8) | ch(c & 255)


def vivid(c):
    m = max((c >> 16) & 255, (c >> 8) & 255, c & 255)
    if m < 24:
        return 0xFFFFFF
    k = 255 / m

    def ch(v):
        return min(255, dround(v * k * 0.85 + 255 * 0.15))
    return (ch((c >> 16) & 255) << 16) | (ch((c >> 8) & 255) << 8) | ch(c & 255)


def luminance(c):
    r, g, b = (c >> 16) & 255, (c >> 8) & 255, c & 255
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255


def parse_ink(s):
    """(kind, rgb, v, k, vivid) like _Ink.parse, or None if the syntax is bad."""
    if not isinstance(s, str):
        return None
    m = HEX_RE.match(s)
    if m:
        return ('fixed', int(m.group(1), 16), 0.0, 1.0, False)
    m = TWINKLE_RE.match(s)
    if m:
        return ('twinkle', int(m.group(1), 16), 0.0, 1.0, False)
    m = PAL_RE.match(s)
    if m:
        kind = 'palette' if m.group(1) == 'p' else 'cycle'
        return (kind, 0, float(m.group(2)), float(m.group(3)) if m.group(3) else 1.0, m.group(4) == '!')
    return None


def resolve_ink(ink, lut):
    """Display colour at t=0; twinkles show their base colour."""
    kind, rgb, v, k, viv = ink
    c = rgb if kind in ('fixed', 'twinkle') else pal_at(lut, v)
    if viv:
        c = vivid(c)
    if k != 1:
        c = scale_color(c, k)
    return c


# ---------------------------------------------------------------------------
# Frame building, ported from Sprite._buildFrame.

class SpriteError(Exception):
    pass


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


def build_frame(spec, built, parts, sid, fi):
    where = f'frame {fi}'
    if isinstance(spec, list):
        if not spec:
            raise SpriteError(f'{where}: no rows')
        if not all(isinstance(r, str) for r in spec):
            raise SpriteError(f'{where}: every row must be a string')
        return list(spec)
    if not isinstance(spec, dict):
        raise SpriteError(f'{where}: a frame is a list of rows or a {{"base": ...}} object')
    for key in spec:
        if key not in ('base', 'patch', 'shift', 'flip'):
            raise SpriteError(f'{where}: unknown key "{key}" (base, patch, shift, flip)')
    base = spec.get('base')
    if is_int(base) and 0 <= base < len(built):
        rows = list(built[base])
    elif isinstance(base, str) and base in parts:
        rows = list(parts[base])
    else:
        hint = f' (only frames 0..{len(built) - 1} exist so far)' if is_int(base) else ''
        raise SpriteError(f'{where}: unknown base {base!r}{hint}')
    patches = spec.get('patch', [])
    if not isinstance(patches, list):
        raise SpriteError(f'{where}: patch must be a list')
    for p in patches:
        if not isinstance(p, dict) or not isinstance(p.get('at'), list) or len(p['at']) < 2 \
                or not all(is_int(v) for v in p['at'][:2]) or not isinstance(p.get('rows'), list) \
                or not all(isinstance(r, str) for r in p['rows']):
            raise SpriteError(f'{where}: each patch is {{"at": [x, y], "rows": ["..."]}}')
        px, py = p['at'][0], p['at'][1]
        for dy, prow in enumerate(p['rows']):
            y = py + dy
            if y < 0 or y >= len(rows):
                continue
            chars = list(rows[y])
            for dx, ch in enumerate(prow):
                x = px + dx
                if ch in (' ', '.') or x < 0 or x >= len(chars):
                    continue
                chars[x] = '.' if ch == '_' else ch
            rows[y] = ''.join(chars)
    shift = spec.get('shift')
    if shift is not None:
        if not isinstance(shift, list) or len(shift) < 2 or not all(is_int(v) for v in shift[:2]):
            raise SpriteError(f'{where}: shift must be [x, y] integers')
        sx, sy = shift[0], shift[1]
        w, h = len(rows[0]), len(rows)
        rows = [''.join(rows[y - sy][x - sx] if 0 <= x - sx < w and 0 <= y - sy < h
                        and x - sx < len(rows[y - sy]) else '.' for x in range(w))
                for y in range(h)]
    flip = spec.get('flip')
    if flip == 'h':
        rows = [r[::-1] for r in rows]
    elif flip == 'v':
        rows = rows[::-1]
    elif flip is not None:
        raise SpriteError(f'{where}: flip must be "h" or "v"')
    return rows


# ---------------------------------------------------------------------------

class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def err(self, where, msg):
        self.errors.append(f'{where}: {msg}')

    def warn(self, where, msg):
        self.warnings.append(f'{where}: {msg}')


def check_colors(colors, where, rep):
    if colors is None:
        return {}
    if not isinstance(colors, dict):
        rep.err(where, 'colors must be an object of "letter": "value"')
        return {}
    out = {}
    for ch, val in colors.items():
        if len(ch) != 1:
            rep.err(where, f'colour key "{ch}" must be a single character')
            continue
        if ch in TRANSPARENT:
            rep.warn(where, f'colour key "{ch}" is always transparent and never used')
        if parse_ink(val) is None:
            rep.err(where, f'colour "{ch}": bad value {val!r} (use #RRGGBB, p:0.5, p:0.5*0.6, p:0.5!, c:0.2, t:#RRGGBB)')
            continue
        out[ch] = val
    return out


def validate_sprite(j, pack_ctx, tables, rep, catalog_titles):
    """Returns a resolved sprite dict for previews, or None on fatal errors."""
    palettes, luts, cats = tables
    pack_name, pack_cat, pack_colors, parts = pack_ctx
    sid = j.get('id') if isinstance(j, dict) else None
    where = f'{pack_name}/{sid if isinstance(sid, str) else "?"}'
    if not isinstance(j, dict):
        rep.err(where, 'each sprite must be an object')
        return None
    for key in j:
        if key not in SPRITE_KEYS:
            rep.warn(where, f'unknown field "{key}" is ignored')
    if not isinstance(sid, str):
        rep.err(where, 'missing "id"')
        return None
    if not ID_RE.match(sid):
        rep.err(where, 'id must be lowercase letters/digits with single dashes, e.g. "sleepy-cat"')
    title = j.get('title')
    if not isinstance(title, str) or not title.strip():
        rep.err(where, 'missing "title"')
        title = sid
    tags = j.get('tags')
    if not isinstance(tags, list) or not tags or not all(isinstance(t, str) and t.strip() for t in tags):
        rep.err(where, '"tags" must be a non-empty list of strings')
        tags = []
    elif any(t != t.lower() for t in tags):
        rep.warn(where, 'tags are lowercased in the catalog; write them lowercase')
    palette = j.get('palette', 'rainbow')
    if 'palette' not in j:
        rep.warn(where, 'no "palette": defaults to rainbow')
    if palette not in luts:
        rep.err(where, f'unknown palette {palette!r} (see reference.md for the list)')
        palette = 'rainbow'
    motion = j.get('motion', 'still')
    if motion not in MOTIONS:
        rep.err(where, f'unknown motion {motion!r} (one of {", ".join(MOTIONS)}); the app would silently use still')
    category = j.get('category', pack_cat)
    if category not in cats:
        rep.err(where, f'category {category!r} is not in categoryOrder: {", ".join(cats)}')
    if 'backdrop' in j and (not isinstance(j['backdrop'], (int, float)) or isinstance(j['backdrop'], bool)
                            or not 0 <= j['backdrop'] <= 1):
        rep.err(where, 'backdrop must be a number from 0 to 1')
    src = j.get('source')
    if src is not None:
        if not isinstance(src, dict):
            rep.err(where, 'source must be an object')
        else:
            for k in SOURCE_KEYS:
                if k not in src:
                    rep.err(where, f'source is missing "{k}"')
            for k in ('work', 'creator', 'basis', 'jurisdiction', 'notice'):
                if k in src and not (isinstance(src[k], str) and src[k].strip()):
                    rep.err(where, f'source "{k}" must be a non-empty string')
            if 'year' in src and src['year'] is not None and not is_int(src['year']):
                rep.err(where, 'source "year" must be an integer (or null for folklore)')
    sprite_colors = check_colors(j.get('colors'), where, rep)
    colors = dict(pack_colors)
    colors.update(sprite_colors)

    frames_spec = j.get('frames')
    if not isinstance(frames_spec, list) or not frames_spec:
        rep.err(where, '"frames" must be a non-empty list')
        return None
    if len(frames_spec) > MAX_FRAMES:
        rep.err(where, f'{len(frames_spec)} frames; the limit is {MAX_FRAMES}')
    built = []
    try:
        for fi, spec in enumerate(frames_spec):
            built.append(build_frame(spec, built, parts, sid, fi))
    except SpriteError as e:
        rep.err(where, str(e))
        return None

    h, w = len(built[0]), len(built[0][0])
    if w == 0:
        rep.err(where, 'frame 0 has an empty row')
        return None
    ok = True
    for fi, rows in enumerate(built):
        if len(rows) != h or any(len(r) != w for r in rows):
            sizes = sorted({len(r) for r in rows})
            rep.err(where, f'frame {fi} is {"/".join(map(str, sizes))}x{len(rows)}; frames must all be {w}x{h}')
            ok = False
    if not ok:
        return None

    inks, used, grids = {}, set(), []
    for fi, rows in enumerate(built):
        grid = []
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in TRANSPARENT:
                    grid.append(None)
                    continue
                if ord(ch) > 126 or ord(ch) < 32:
                    rep.err(where, f'frame {fi} row {y}: non-ASCII character {ch!r}')
                    return None
                if ch not in colors:
                    rep.err(where, f'frame {fi} row {y} col {x}: no colour for "{ch}"')
                    return None
                used.add(ch)
                grid.append(ch)
        grids.append(grid)
    for ch in used:
        inks[ch] = parse_ink(colors[ch])

    seq = j.get('seq', list(range(len(built))))
    if not isinstance(seq, list) or not seq or not all(is_int(s) for s in seq):
        rep.err(where, 'seq must be a non-empty list of frame indices')
        return None
    if any(s < 0 or s >= len(built) for s in seq):
        rep.err(where, f'seq refers to a frame outside 0..{len(built) - 1}')
        return None
    ms_raw = j.get('ms', 200)
    if isinstance(ms_raw, list):
        if not all(isinstance(m, (int, float)) and not isinstance(m, bool) for m in ms_raw):
            rep.err(where, 'ms must be a number or a list of numbers')
            return None
        if len(ms_raw) != len(seq):
            rep.err(where, f'ms has {len(ms_raw)} entries but the sequence has {len(seq)} steps; ms must match seq')
            return None
        ms = [int(m) for m in ms_raw]
    elif isinstance(ms_raw, (int, float)) and not isinstance(ms_raw, bool):
        ms = [int(ms_raw)] * len(seq)
    else:
        rep.err(where, 'ms must be a number or a list of numbers')
        return None
    if any(m < MS_MIN or m > MS_MAX for m in ms):
        rep.err(where, f'ms values must be {MS_MIN}-{MS_MAX}')
    long_steps = [i for i, m in enumerate(ms) if m > DEVICE_FRAME_CAP_MS]
    if long_steps:
        rep.warn(where, f'step(s) {long_steps} last over {DEVICE_FRAME_CAP_MS} ms; Sent GIFs cap each frame at 1 s, '
                        'so repeat the frame in seq for a long hold')
    unused = sorted(set(range(len(built))) - set(seq))
    if unused:
        rep.warn(where, f'frame(s) {unused} are never shown by seq (fine if they are only bases)')

    # Rendering checks with the default palette.
    lut = luts[palette]
    rgb = {ch: resolve_ink(ink, lut) for ch, ink in inks.items()}
    blank = [fi for fi in sorted(set(seq)) if all(c is None for c in grids[fi])]
    if len(blank) == len(set(seq)):
        rep.err(where, 'every frame is empty; the sprite renders blank')
    elif blank:
        rep.warn(where, f'frame(s) {blank} are completely empty')
    lit = any(max((rgb[c] >> 16) & 255, (rgb[c] >> 8) & 255, rgb[c] & 255) > 8
              for fi in set(seq) for c in grids[fi] if c is not None)
    if not lit and len(blank) != len(set(seq)):
        rep.err(where, 'every pixel is (near) black with this palette; the sprite renders blank')
    for ch in sorted(used):
        c, kind = rgb[ch], inks[ch][0]
        lum = luminance(c)
        if lum < 0.12:
            label = 'near-black: reads as an LED that is off (fine for outlines/eyes, not for fill)' \
                if max((c >> 16) & 255, (c >> 8) & 255, c & 255) <= 40 else \
                'very dark: may vanish at low brightness'
            via = f' ({colors[ch]} on {palette})' if kind in ('palette', 'cycle') else ''
            rep.warn(where, f'colour "{ch}" = #{c:06X}{via} is {label}')
    if src is None and not any(i[0] in ('palette', 'cycle') for i in inks.values()):
        rep.warn(where, 'no p:/c: colours, so the app cannot recolour it (fine for fixed-colour art)')
    if (w, h) not in ((16, 16), (8, 8)) and not (h == 8 and w > 8):
        rep.warn(where, f'size {w}x{h}: the standard is 16x16 (8x8 minis and Nx8 banners are fine too)')

    # Catalog: titles must stay unique (tool/build_catalog.dart).
    if catalog_titles is not None and title:
        owner = catalog_titles.get(title.lower())
        if owner and owner != f'sprite:{sid}':
            rep.warn(where, f'title "{title}" is already used by {owner}; the catalog will call it "Pixel {title}". '
                            'Pick a distinct title')
        banner = w >= h * 2
        recolourable = any(i[0] in ('palette', 'cycle') for i in inks.values())
        ways = [p for p in COLOURWAYS.get(category, []) if p != palette]
        if src is None and not (recolourable and ways) and not banner:
            alt = 'Float' if motion == 'bounce' else 'Bounce'
            t2 = f'{title} ({alt})'.lower()
            owner = catalog_titles.get(t2)
            if owner and owner != f'sprite:{sid}':
                rep.err(where, f'the catalog adds a "{title} ({alt})" look, which clashes with {owner}; rename it')

    return {'id': sid, 'title': title, 'w': w, 'h': h, 'grids': grids, 'seq': seq, 'rgb': rgb, 'ms': ms}


def load_catalog_titles(repo):
    if not repo:
        return None
    try:
        data = json.load(open(os.path.join(repo, 'assets', 'catalog', 'catalog.json'), encoding='utf-8'))
    except (OSError, ValueError):
        return None
    return {i['title'].lower(): i.get('generator', '?') for i in data.get('items', [])}


def validate_pack(path, tables, rep, catalog_titles, only=None):
    try:
        pack = json.load(open(path, encoding='utf-8'))
    except ValueError as e:
        rep.err(os.path.basename(path), f'invalid JSON: {e}')
        return [], []
    except OSError as e:
        rep.err(os.path.basename(path), str(e))
        return [], []
    name = os.path.basename(path)
    if not isinstance(pack, dict) or not isinstance(pack.get('sprites'), list):
        rep.err(name, 'a pack is an object with a "sprites" list')
        return [], []
    for key in pack:
        if key not in PACK_KEYS:
            rep.warn(name, f'unknown pack field "{key}" is ignored')
    if not isinstance(pack.get('pack'), str):
        rep.warn(name, 'no "pack" id')
    cat = pack.get('category', 'Pixel Art')
    colors = check_colors(pack.get('colors'), name, rep)
    parts = {}
    raw_parts = pack.get('parts', {})
    if not isinstance(raw_parts, dict):
        rep.err(name, 'parts must be an object of name: [rows]')
    else:
        for k, v in raw_parts.items():
            if not isinstance(v, list) or not v or not all(isinstance(r, str) for r in v):
                rep.err(name, f'part "{k}" must be a list of row strings')
            else:
                parts[k] = v
    ids, resolved = [], []
    for s in pack['sprites']:
        sid = s.get('id') if isinstance(s, dict) else None
        if isinstance(sid, str):
            ids.append(sid)
        if only and sid not in only:
            continue
        r = validate_sprite(s, (name, cat, colors, parts), tables, rep, catalog_titles)
        if r:
            resolved.append(r)
    return ids, resolved


# ---------------------------------------------------------------------------
# PNG contact sheet.

def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * width * 3:(y + 1) * width * 3])

    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) \
        + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


def render_sheet(sprites, path, cell=16, all_steps=False):
    """One row per sprite: each frame (in first-shown order, or every seq step)
    as round LED dots on a dark panel, frames side by side."""
    gap, pad = cell, cell // 2
    rows = []
    for s in sprites:
        order = list(s['seq']) if all_steps else list(dict.fromkeys(s['seq']))
        rows.append((s, order))
    width = max(pad * 2 + len(o) * (s['w'] * cell) + (len(o) - 1) * gap for s, o in rows)
    height = pad * 2 + sum(s['h'] * cell for s, _ in rows) + gap * (len(rows) - 1)
    bg, off = (20, 20, 26), (34, 34, 42)
    px = bytearray(bytes(bg) * (width * height))
    r_out = cell * 0.44
    mask = []
    for dy in range(cell):
        for dx in range(cell):
            d = math.hypot(dx + 0.5 - cell / 2, dy + 0.5 - cell / 2)
            mask.append(max(0.0, min(1.0, r_out - d + 0.5)))
    oy = pad
    for s, order in rows:
        for col, fi in enumerate(order):
            ox = pad + col * (s['w'] * cell + gap)
            grid = s['grids'][fi]
            for y in range(s['h']):
                for x in range(s['w']):
                    ch = grid[y * s['w'] + x]
                    if ch is None:
                        c = off
                    else:
                        v = s['rgb'][ch]
                        c = ((v >> 16) & 255, (v >> 8) & 255, v & 255)
                    for dy in range(cell):
                        base = ((oy + y * cell + dy) * width + ox + x * cell) * 3
                        for dx in range(cell):
                            a = mask[dy * cell + dx]
                            if a <= 0:
                                continue
                            i = base + dx * 3
                            px[i] = int(bg[0] + (c[0] - bg[0]) * a)
                            px[i + 1] = int(bg[1] + (c[1] - bg[1]) * a)
                            px[i + 2] = int(bg[2] + (c[2] - bg[2]) * a)
        oy += s['h'] * cell + gap
    write_png(path, width, height, px)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description='Validate and preview Glyph sprite packs.')
    ap.add_argument('--pack', action='append', default=[], help='pack JSON file (repeatable)')
    ap.add_argument('--all', action='store_true', help='validate every pack in assets/catalog/sprites')
    ap.add_argument('--only', action='append', default=[], help='only these sprite ids (repeatable or comma separated)')
    ap.add_argument('--preview', metavar='PNG', help='write a PNG contact sheet of the selected sprites')
    ap.add_argument('--steps', action='store_true', help='preview every seq step, not just distinct frames')
    ap.add_argument('--cell', type=int, default=16, help='preview pixels per LED (default 16)')
    ap.add_argument('--repo', help='Glyph checkout (default: found from the current directory)')
    ap.add_argument('-v', '--verbose', action='store_true', help='list every warning with --all')
    args = ap.parse_args()
    if not args.pack and not args.all:
        ap.error('give --pack <file> or --all')

    repo = find_repo(args.repo)
    palettes, cats = load_tables(repo)
    luts = {pid: bake(stops) for pid, _, stops in palettes}
    tables = (palettes, luts, cats)
    catalog_titles = load_catalog_titles(repo)
    only = {i for o in args.only for i in o.split(',') if i} or None

    repo_packs = sorted(glob.glob(os.path.join(repo, 'assets', 'catalog', 'sprites', '*.json'))) if repo else []
    targets = [os.path.abspath(p) for p in args.pack]
    if args.all:
        if not repo_packs:
            ap.error('no Glyph checkout found; run from the repo or pass --repo')
        targets = sorted(set(targets) | {os.path.abspath(p) for p in repo_packs})

    rep = Report()
    seen_ids = {}  # id -> pack file, for global uniqueness
    resolved = []
    for p in targets:
        ids, res = validate_pack(p, tables, rep, catalog_titles, only)
        resolved += res
        for i in ids:
            if i in seen_ids:
                rep.err(os.path.basename(p), f'duplicate sprite id "{i}" (also in {os.path.basename(seen_ids[i])})')
            seen_ids[i] = p
    # Ids must be unique across every pack, not just the ones checked.
    for p in repo_packs:
        if os.path.abspath(p) in targets:
            continue
        try:
            data = json.load(open(p, encoding='utf-8'))
        except (OSError, ValueError):
            continue
        for s in data.get('sprites', []):
            i = s.get('id') if isinstance(s, dict) else None
            if i in seen_ids and (only is None or i in only):
                rep.err(os.path.basename(seen_ids[i]), f'duplicate sprite id "{i}" (already in {os.path.basename(p)})')
    if only:
        missing = only - {s['id'] for s in resolved} - {e.split(': ')[0].split('/')[-1] for e in rep.errors}
        for m in sorted(missing):
            rep.err('--only', f'no sprite "{m}" in the given pack(s)')

    quiet = args.all and not args.verbose and not only
    for e in rep.errors:
        print(f'ERROR   {e}')
    if not quiet:
        for w in rep.warnings:
            print(f'warning {w}')
    for s in resolved if not quiet else []:
        steps = len(s['seq'])
        print(f'sprite  {s["id"]}: "{s["title"]}" {s["w"]}x{s["h"]}, {len(s["grids"])} frame(s), '
              f'{steps} step(s), loop {sum(s["ms"])} ms')
    print(f'{len(targets)} pack(s), {len(resolved)} sprite(s) checked: '
          f'{len(rep.errors)} error(s), {len(rep.warnings)} warning(s)'
          + (' (use -v to list warnings)' if quiet and rep.warnings else ''))

    if args.preview:
        if not resolved:
            print('nothing to preview', file=sys.stderr)
        elif len(resolved) > 60:
            print('too many sprites for one preview; narrow it with --only', file=sys.stderr)
            return 1
        else:
            render_sheet(resolved, args.preview, max(4, args.cell), args.steps)
            print(f'preview: {args.preview} (rows: {", ".join(s["id"] for s in resolved)})')
    return 1 if rep.errors else 0


if __name__ == '__main__':
    sys.exit(main())
