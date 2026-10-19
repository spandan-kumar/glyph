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
  when the catalog grows. The headline is "13,000+ animations".
- **No trademarked characters** in screenshots or the Stage demo, even
  public-domain versions of them.
- **Privacy copy** must stay true to `docs/PRIVACY.md`.

**Deploying.** The site lives at the Pages root,
<https://spandan-kumar.github.io/glyph/>, beside the signed animation catalog.
Pages serves one artifact per repository, so the `catalog` workflow ships both:
after building the catalog it copies `index.html` (over the generated stub) and
`media/` into the same artifact. Catalog paths (`manifest-v1.json`, `payload/`,
`collections/`) are untouched. A push to `main` that changes `website/` runs
that workflow, which waits for the maintainer's approval of the `catalog`
environment; unchanged catalog content keeps its existing signed manifest.
Never add a `website/` file named like a catalog path.
