"""Build LED-sized clip assets from the complete, permission-granted archive.

Run with Python + Pillow: import_collection.py --archive PATH [--workers 4].
The index and compressed clips are bundled; Pages also hosts verified copies.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import gzip
import hashlib
import json
from pathlib import Path
import struct

from PIL import Image, ImageSequence

from build_collection_names import DESCRIPTIONS, name_rows
from collection_categories import CATEGORIES

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "catalog_assets/imported"


def convert(task):
    entry, original, archive = task
    path = Path(archive) / original["path"]
    source = path.read_bytes()
    if hashlib.sha256(source).hexdigest() != original["sha256"]:
        raise ValueError(f"Source hash mismatch: {entry['id']}")
    width, height = entry["min_width"], entry["min_height"]
    frames, delays = [], []
    with Image.open(path) as image:
        for frame in ImageSequence.Iterator(image):
            rgba = frame.convert("RGBA")
            black = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
            black.alpha_composite(rgba)
            # Centre samples recover LED colours from enlarged cell previews,
            # avoiding the thin grid lines around cells. Never average colours.
            rgb = black.convert("RGB").resize((width, height), Image.Resampling.NEAREST)
            frames.append(rgb.tobytes())
            ms = int(frame.info.get("duration", 100))
            delays.append(ms if ms > 10 else 100)
    if not frames or len(frames) > 12000 or width * height * len(frames) > 8 * 1024 * 1024:
        raise ValueError(f"Clip exceeds phone limits: {entry['id']}")
    body = bytearray(struct.pack("<4sHHI", b"GLC1", width, height, len(frames)))
    for frame, ms in zip(frames, delays):
        body.extend(struct.pack("<I", ms))
        body.extend(frame)
    compressed = gzip.compress(body, compresslevel=9, mtime=0)
    sha = hashlib.sha256(compressed).hexdigest()
    output = OUT / f"{sha}.clip.gz"
    # Different source IDs may share identical pixels and timing. Keep all
    # IDs in the index while storing a single content-addressed payload.
    if not output.exists():
        output.write_bytes(compressed)
    colours = Counter()
    for r, g, b in zip(frames[0][0::3], frames[0][1::3], frames[0][2::3]):
        if max(r, g, b) < 35:
            continue
        if max(r, g, b) - min(r, g, b) < 35:
            colours["white"] += 1
        elif r > g * 1.3 and r > b * 1.3:
            colours["red"] += 1
        elif g > r * 1.3 and g > b * 1.3:
            colours["green"] += 1
        elif b > r * 1.3 and b > g * 1.3:
            colours["blue"] += 1
        elif r > b * 1.4 and g > b * 1.4:
            colours["yellow"] += 1
        elif r > g * 1.3 and b > g * 1.3:
            colours["purple"] += 1
        elif g > r * 1.3 and b > r * 1.3:
            colours["cyan"] += 1
        else:
            colours["orange"] += 1
    tags = [name for name, _ in colours.most_common(3)]
    return [entry["id"], sha, len(compressed), width, height, len(frames), tags], {
        "id": entry["id"],
        "source_sha256": original["sha256"], "clip_sha256": sha,
        "width": width, "height": height,
        "frames": len(frames), "duration_ms": sum(delays),
    }


def main():
    args = argparse.ArgumentParser()
    args.add_argument("--archive", type=Path, required=True)
    args.add_argument("--workers", type=int, default=4)
    options = args.parse_args()
    archive = options.archive.resolve()
    catalogue = json.loads((archive / "catalogue.json").read_text())
    downloaded = json.loads((archive / "download-manifest.json").read_text())
    originals = {item["id"]: item for item in downloaded["files"]}
    if not downloaded["complete"] or downloaded["failed"]:
        raise ValueError("The source archive must be complete")
    if len(originals) != len(catalogue["animations"]):
        raise ValueError("Source catalogue/archive counts differ")
    OUT.mkdir(parents=True, exist_ok=True)
    tasks = [(item, originals[item["id"]], str(archive)) for item in catalogue["animations"]]
    rows, provenance = [], []
    with ProcessPoolExecutor(max_workers=options.workers) as pool:
        for row, record in pool.map(convert, tasks, chunksize=16):
            rows.append(row)
            provenance.append(record)
            if len(rows) % 250 == 0:
                print(f"Converted {len(rows)}/{len(tasks)} animations", flush=True)
    version = 1
    if DESCRIPTIONS.exists():
        descriptions = json.loads(DESCRIPTIONS.read_text())["clips"]
        existing = json.loads((ROOT / "assets/catalog/catalog.json").read_text())["items"]
        rows = name_rows(rows, descriptions, (i["title"] for i in existing))
        version = 3
    index = {"version": version, "count": len(rows), "permission": "maintainer-confirmed-collection-consent-2026-10-13", "rows": rows}
    if version == 3:
        present = {row[11] for row in rows}
        index["categories"] = [category for category in CATEGORIES if category in present]
    (ROOT / "assets/catalog/imported.json").write_text(json.dumps(index, separators=(",", ":")) + "\n")
    (OUT / "provenance.json").write_text(json.dumps({
        "catalogue_sha256": hashlib.sha256((archive / "catalogue.json").read_bytes()).hexdigest(),
        "permission": index["permission"], "entries": provenance,
    }, separators=(",", ":")) + "\n")
    unique = {row[1]: row[2] for row in rows}
    print(f"All {len(rows)} IDs retained; {len(unique)} unique clips; {sum(unique.values())} compressed bytes", flush=True)


if __name__ == "__main__":
    main()
