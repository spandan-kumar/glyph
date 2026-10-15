"""Build the named collection index from visually reviewed, hash-keyed metadata.

No pixels, source IDs, timings or content hashes change. Regenerate this index
after edits to catalog_assets/imported/descriptions.json; never edit rows by hand.
"""
import argparse
from collections import Counter
import json
from pathlib import Path

from collection_categories import CATEGORIES, category_for

ROOT = Path(__file__).resolve().parents[1]
DESCRIPTIONS = ROOT / "catalog_assets/imported/descriptions.json"


def _words(description, field, maximum):
    words = description.get(field)
    if not isinstance(words, list) or len(words) > maximum or any(
        not isinstance(word, str) or not word.strip() or len(word) > 64
        or any(ord(c) < 32 for c in word) for word in words
    ):
        raise ValueError(f"Invalid {field}")
    if field != "aliases" and not words:
        raise ValueError(f"Empty {field}")
    return list(dict.fromkeys(word.strip() for word in words))


def name_rows(rows, descriptions, existing_titles=()):
    expected = {row[1] for row in rows}
    if set(descriptions) != expected:
        raise ValueError("Descriptions must cover every unique clip, without unknown hashes")
    validated = {}
    for sha, description in descriptions.items():
        title = description.get("title")
        if not isinstance(title, str) or not title.strip() or len(title) > 64 or (
            title.lower().startswith("imported ") or any(ord(c) < 32 for c in title)
        ):
            raise ValueError(f"Invalid title: {sha}")
        validated[sha] = (title.strip(), _words(description, "subjects", 12),
                          _words(description, "aliases", 8), _words(description, "tags", 24))
    reserved = {entry[0].casefold() for entry in validated.values()}
    used = {title.casefold() for title in existing_titles}
    seen = Counter()
    named = []
    for row in rows:
        title, subjects, aliases, tags = validated[row[1]]
        base = title.casefold()
        seen[base] += 1
        candidate = title if seen[base] == 1 else f"{title} {seen[base]}"
        while candidate.casefold() in used or (candidate != title and candidate.casefold() in reserved):
            seen[base] += 1
            candidate = f"{title} {seen[base]}"
        used.add(candidate.casefold())
        # Keep the natural name searchable when the display title distinguishes
        # variants or duplicate source records with an ordinal.
        full_aliases = list(aliases)
        if candidate != title and title not in full_aliases:
            full_aliases.append(title)
        if len(full_aliases) > 8:
            raise ValueError(f"Too many aliases after variant naming: {row[0]}")
        named.append([*row[:7], candidate, subjects, full_aliases, tags,
                      category_for(descriptions[row[1]])])
    return named


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--descriptions", type=Path, default=DESCRIPTIONS)
    args = parser.parse_args()
    path = ROOT / "assets/catalog/imported.json"
    index = json.loads(path.read_text())
    descriptions = json.loads(args.descriptions.read_text())["clips"]
    existing = json.loads((ROOT / "assets/catalog/catalog.json").read_text())["items"]
    index["rows"] = name_rows(index["rows"], descriptions, (i["title"] for i in existing))
    index["version"] = 3
    present = {row[11] for row in index["rows"]}
    index["categories"] = [category for category in CATEGORIES if category in present]
    path.write_text(json.dumps(index, separators=(",", ":")) + "\n")
    print(f"Named all {len(index['rows'])} records ({len(descriptions)} unique clips); identities unchanged")


if __name__ == "__main__":
    main()
