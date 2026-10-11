#!/usr/bin/env python3
"""Rebuild the curated CC0 packs from pinned artist files (requires Pillow).

Run from the repository root. Downloads are cached under build/catalog-import;
the SHA-256 checks prevent a changed upstream file silently changing our art.
"""

import hashlib
import io
import json
from pathlib import Path
import string
import urllib.request
import zipfile

from PIL import Image


CACHE = Path('build/catalog-import')
OUT = Path('assets/catalog/sprites')
LICENSE_URL = 'https://creativecommons.org/publicdomain/zero/1.0/'
SOURCES = {
    'emoji': (
        'emojipacki.zip',
        'c0108bed7b140d981aa10b1a006b3b03b764d1e618f81250a26e5a1e3170d1a2',
        'Tiny RPG - Emoji Pack I', 'Gabriel "tiopalada" Lima', 2025,
        'https://opengameart.org/content/tiny-rpg-emoji-pack-i',
    ),
    'fire': (
        'Fires.zip',
        'c716e8f46c85b2df8a102fd7c8db4003ee11b97a66bfe679af56809c91de9f71',
        'Animated Fires', 'Stealthix', 2019,
        'https://opengameart.org/content/animated-fires',
    ),
    'slime': (
        'Slimes.zip',
        '76b1cbf91cb75be82aea5286f6cbd9e2c950fd80ff5afcc7ffa91016b682599c',
        '16x16 Animated Slimes', 'Stealthix', 2019,
        'https://opengameart.org/content/16x16-animated-slimes',
    ),
    'birds': (
        'birds.32x32.png',
        '39221f19addd7f316a9821fd9b7729b7f0bb3840ebdb0c16f829411c79f0847b',
        'Animated Birds (32x32)', 'MoikMellah', 2012,
        'https://opengameart.org/content/animated-birds-32x32',
    ),
}


def load_sources():
    CACHE.mkdir(parents=True, exist_ok=True)
    result = {}
    for key, (name, digest, *_) in SOURCES.items():
        path = CACHE / name
        if not path.exists():
            url = 'https://opengameart.org/sites/default/files/' + name
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read(1024 * 1024 + 1)
            if len(data) > 1024 * 1024:
                raise ValueError(f'{name}: download exceeds 1 MiB')
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError(f'{name}: upstream file changed; review before importing')
            path.write_bytes(data)
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError(f'{name}: SHA-256 mismatch')
        result[key] = data
    return result


def image(data, member=None):
    if member:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            data = archive.read(member)
    return Image.open(io.BytesIO(data)).convert('RGBA')


def tiles(sheet, width, height, indices):
    cols = sheet.width // width
    if sheet.width % width or sheet.height % height:
        raise ValueError('sheet dimensions must be whole cells')
    if max(indices) >= cols * (sheet.height // height):
        raise ValueError('frame index outside sheet')
    return [sheet.crop((i % cols * width, i // cols * height,
                        (i % cols + 1) * width, (i // cols + 1) * height))
            for i in indices]


def sprite(key, member, sid, title, frames, size, ms, tags, palette,
           basis, category=None):
    # Centre every frame on the same canvas; per-frame bounds would jitter.
    images = []
    for frame in frames:
        if frame.width > size or frame.height > size:
            raise ValueError(f'{sid}: frame does not fit {size}x{size}')
        canvas = Image.new('RGBA', (size, size))
        canvas.paste(frame, ((size - frame.width) // 2,
                             (size - frame.height) // 2))
        images.append(canvas)
    pixels_by_frame = [
        [frame.getpixel((x, y)) for y in range(size) for x in range(size)]
        for frame in images
    ]
    rgb = sorted({c[:3] for pixels in pixels_by_frame for c in pixels if c[3]})
    letters = string.ascii_uppercase + string.ascii_lowercase + string.digits
    if len(rgb) > len(letters):
        raise ValueError(f'{sid}: too many colours')
    lookup = {c: letters[i] for i, c in enumerate(rgb)}
    colors = {lookup[c]: '#%02X%02X%02X' % c for c in rgb}
    unique, sequence = [], []
    for pixels in pixels_by_frame:
        if any(c[3] not in (0, 255) for c in pixels):
            raise ValueError(f'{sid}: partial alpha needs an explicit adaptation')
        pixels = ['.' if c[3] == 0 else lookup[c[:3]] for c in pixels]
        rows = [''.join(pixels[y * size:(y + 1) * size]) for y in range(size)]
        if rows not in unique:
            unique.append(rows)
        sequence.append(unique.index(rows))
    if len(unique) > 48:
        raise ValueError(f'{sid}: too many unique frames')
    name, digest, work, creator, year, url = SOURCES[key]
    source = {
        'work': work, 'year': year, 'creator': creator,
        'basis': basis, 'jurisdiction': 'worldwide',
        'notice': f'Artwork by {creator} — CC0 1.0. Adapted for Glyph.',
        'license': 'CC0-1.0', 'url': url, 'licenseUrl': LICENSE_URL,
        'downloadUrl': 'https://opengameart.org/sites/default/files/' + name,
        'sha256': digest, 'file': member or name,
    }
    result = {
        'id': sid, 'title': title, 'tags': tags, 'palette': palette,
        'motion': 'still', 'ms': ms, 'colors': colors,
        'frames': unique, 'seq': sequence, 'source': source,
    }
    if category:
        result['category'] = category
    return result


def write_pack(name, category, sprites):
    pack = {'pack': name, 'category': category, 'sprites': sprites}
    (OUT / f'{name}.json').write_text(json.dumps(pack, indent=2) + '\n')
    print(f'{name}: {len(sprites)} animations')


def main():
    sources = load_sources()
    expressions = [
        ('Laughing', 'Bubble Giggle', ['laugh', 'happy', 'funny']),
        ('Cute', 'Bubble Blush', ['cute', 'shy', 'adorable']),
        ('Love', 'Bubble Love', ['heart', 'love', 'valentine']),
        ('Kissing', 'Bubble Kiss', ['kiss', 'love', 'valentine']),
        ('Sleepy', 'Bubble Snooze', ['sleep', 'night', 'cozy']),
        ('Angry', 'Bubble Rage', ['angry', 'mad', 'rage']),
        ('Dizzy', 'Bubble Spin', ['dizzy', 'confused', 'spin']),
        ('Crying', 'Bubble Tears', ['sad', 'cry', 'tears']),
        ('Thinking', 'Bubble Ponder', ['think', 'hmm', 'thought']),
        ('OMG', 'Bubble Gasp', ['shocked', 'surprise', 'wow']),
        ('Sweat', 'Bubble Whew', ['sweat', 'nervous', 'relief']),
        ('Tongue', 'Bubble Mischief', ['tongue', 'silly', 'playful']),
        ('Eager', 'Bubble Delight', ['eager', 'excited', 'happy']),
        ('Frustrated', 'Bubble Grumble', ['frustrated', 'annoyed', 'grumpy']),
        ('Speechless', 'Bubble Speechless', ['speechless', 'quiet', 'silent']),
        ('Idea', 'Bright Idea Bubble', ['idea', 'lightbulb', 'inspiration']),
        ('Lit', 'Flame Bubble', ['fire', 'lit', 'hot']),
        ('Question', 'Curious Bubble', ['question', 'curious', 'confused']),
        ('Exclamation', 'Surprise Bubble', ['surprise', 'alert', 'exclamation']),
        ('Headblown', 'Mind Blown Bubble', ['mind blown', 'shock', 'amazed']),
    ]
    bubbles = []
    for emotion, title, tags in expressions:
        member = f'20250405emoticons-Sheet{emotion}.png'
        sheet = image(sources['emoji'], member)
        frames = tiles(sheet, 32, 32, range(16))
        if any(frame.getbbox() is None for frame in frames):
            raise ValueError(f'{emotion}: unexpected empty frame')
        bubbles.append(sprite(
            'emoji', member, 'bubble-' + emotion.lower(), title, frames, 32,
            100, ['emotion', 'speech bubble', *tags], 'mono',
            'Original 32x32 pixels and frame order. The four empty padding '
            'cells are omitted; repeated drawings share frames. Curated 100 ms timing.',
        ))
    write_pack('emotion_bubbles', 'Emoji', bubbles)

    fires = []
    for member, sid, title, w, h, palette, tags in [
        ('Small_Fireball_10x26.png', 'living-flame', 'Living Flame', 10, 26,
         'ember', ['fire', 'flame', 'warm', 'cozy']),
        ('Small_Iceball_9x24.png', 'frost-flame', 'Frost Flame', 9, 24,
         'arctic', ['fire', 'ice', 'blue', 'cold']),
        ('Small_Poisonball_9x25.png', 'witchlight-flame', 'Witchlight Flame', 9, 25,
         'toxic', ['fire', 'poison', 'green', 'halloween', 'spooky']),
    ]:
        frames = tiles(image(sources['fire'], member), w, h, range(0, 60, 2))
        fires.append(sprite(
            'fire', member, sid, title, frames, 32, 100, tags, palette,
            'Original colours, centred on a 32x32 canvas with a fixed origin. '
            'Every second frame of the 60-frame animation is played at 100 ms '
            'for a 3-second loop within Glyph frame limits.',
        ))
    write_pack('artist_fire', 'Fire & Energy', fires)

    animals = []
    for member, sid, title in [
        ('Slime_Medium_Green.png', 'jelly-squish', 'Jelly Squish'),
        ('Slime_Small_Blue.png', 'jelly-pebble', 'Jelly Pebble'),
    ]:
        small = 'Small' in member
        frames = tiles(image(sources['slime'], member), 32, 32,
                       range(2 if small else 4))
        if any(f.getbbox() is None or f.getbbox()[0] < 8 or
               f.getbbox()[1] < 8 or f.getbbox()[2] > 24 or
               f.getbbox()[3] > 24 for f in frames):
            raise ValueError(f'{sid}: fixed crop would cut the drawing')
        frames = [f.crop((8, 8, 24, 24)) for f in frames]
        animals.append(sprite(
            'slime', member, sid, title, frames, 16, 150,
            ['slime', 'jelly', 'squish', 'cute', 'creature', 'gaming'],
            'forest' if not small else 'ocean',
            f'Front-facing {len(frames)}-frame idle animation with original colours. '
            'A fixed 16x16 crop removes unused margins without cutting the drawing.',
            category='Gaming',
        ))
    bird_sheet = image(sources['birds'])
    for y in range(bird_sheet.height):
        for x in range(bird_sheet.width):
            if bird_sheet.getpixel((x, y))[:3] == (255, 0, 255):
                bird_sheet.putpixel((x, y), (0, 0, 0, 0))
    for row, sid, title, tags, palette in [
        (0, 'soaring-condor', 'Soaring Condor', ['condor', 'bird', 'fly', 'wings'], 'mono'),
        (1, 'copper-parrot', 'Copper Parrot', ['parrot', 'bird', 'fly', 'tropical'], 'autumn'),
    ]:
        frames = tiles(bird_sheet, 32, 32, range(row * 6, row * 6 + 5))
        animals.append(sprite(
            'birds', None, sid, title, frames, 32, 100, tags, palette,
            'Original five-frame wing cycle, canvas and colours; the source '
            'magenta background key is made transparent and the empty sixth '
            'column omitted. Curated 100 ms timing.',
        ))
    write_pack('artist_animals', 'Animals', animals)


if __name__ == '__main__':
    main()
