# Glyph website

A single static page (`index.html`) plus the images in `media/`. No build step.

Preview it locally:

```bash
python3 -m http.server 8765 --directory website
```

then open <http://localhost:8765>.

- **Screenshots** are phone captures (450×1000) saved as JPEG in `media/`.
  Replace a file with the same name to update it; keep the 450:1000 shape.
- **Hero video**: the opening shows `media/intro.gif` (the boot animation) as
  a stand-in. When the room video exists, swap the `<img>` in the hero figure
  for the `<video>` tag noted in the comment above it.
- **Numbers** (looks, sprites, effects) are written into the copy; update them
  when the catalog grows.
- **Privacy copy** must stay true to `docs/PRIVACY.md`.

Not deployed yet. GitHub Pages already serves the animation catalog, so plan
the site's URL before publishing it there.
