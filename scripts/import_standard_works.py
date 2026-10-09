#!/usr/bin/env python3
"""Convert github.com/Atreyu4EVR/Standard-Works (public domain) into Hearken's bundled content.

Usage: python3 scripts/import_standard_works.py <path-to-Standard-Works-clone> Hearken/Resources/Content

Writes one file per volume (scripture-ot.json, scripture-nt.json, scripture-bofm.json,
scripture-dc-testament.json, scripture-pgp.json) in the app's Volume schema. IDs follow
the Church's URL slugs: "<volume>.<book>.<chapter>", e.g. "bofm.alma.32", and verse IDs
add ".<verse>". Never change an ID scheme once it ships: highlights and notes point at them.
"""
import json
import sys
from pathlib import Path

CONTENT_VERSION = 2

SOURCES = [
    # (file, volume id, volume title)
    ("old-testament.json", "ot", "Old Testament"),
    ("new-testament.json", "nt", "New Testament"),
    ("book-of-mormon.json", "bofm", "Book of Mormon"),
    ("doctrine-and-covenants.json", "dc-testament", "Doctrine and Covenants"),
    ("pearl-of-great-price.json", "pgp", "Pearl of Great Price"),
]

# Display names that differ from the source.
TITLE_OVERRIDES = {"ot.song": "Song of Solomon"}


def clean(text):
    return " ".join(text.split()) if text else None


def chapter(book_id, number, source_chapter, fallback_heading=None):
    chapter_id = f"{book_id}.{number}"
    heading = clean(source_chapter.get("heading") or source_chapter.get("note")) or fallback_heading
    out = {"id": chapter_id, "number": number}
    if heading:
        out["heading"] = heading
    out["verses"] = [
        {"id": f"{chapter_id}.{v['verse']}", "number": v["verse"], "text": clean(v["text"])}
        for v in source_chapter["verses"]
    ]
    return out


def convert(source, volume_id, volume_title):
    if "sections" in source:  # Doctrine and Covenants
        book_id = f"{volume_id}.dc"
        books = [{
            "id": book_id,
            "title": "Doctrine and Covenants",
            "chapters": [chapter(book_id, s["section"], s) for s in source["sections"]],
        }]
    else:
        books = []
        for b in source["books"]:
            book_id = f"{volume_id}.{b['lds_slug']}"
            book_heading = clean(b.get("heading"))
            chapters = []
            for c in b["chapters"]:
                # The Book of Mormon's book-level headings introduce chapter 1.
                fallback = book_heading if c["chapter"] == 1 else None
                chapters.append(chapter(book_id, c["chapter"], c, fallback))
            books.append({"id": book_id, "title": TITLE_OVERRIDES.get(book_id, b["book"]), "chapters": chapters})
    return {"contentVersion": CONTENT_VERSION, "volume": {"id": volume_id, "title": volume_title, "books": books}}


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    for file, volume_id, title in SOURCES:
        data = convert(json.loads((src / file).read_text()), volume_id, title)
        out = dst / f"scripture-{volume_id}.json"
        out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
        books = data["volume"]["books"]
        chapters = sum(len(b["chapters"]) for b in books)
        verses = sum(len(c["verses"]) for b in books for c in b["chapters"])
        print(f"{out.name}: {len(books)} books, {chapters} chapters, {verses} verses, {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
