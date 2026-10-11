#!/usr/bin/env python3
"""Writes Hearken/Resources/Content/chapter-words.json: every chapter's word count, which reading
plans use to balance days by reading length without loading scripture text.

    python3 scripts/chapter_word_counts.py

Run it again whenever the scripture files change.
"""
import json, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Hearken", "Resources", "Content")
counts = {}
for volume in ["ot", "nt", "bofm", "dc-testament", "pgp"]:
    with open(os.path.join(ROOT, f"scripture-{volume}.json"), encoding="utf-8") as f:
        data = json.load(f)
    for book in data["volume"]["books"]:
        for chapter in book["chapters"]:
            counts[chapter["id"]] = max(1, sum(len(v["text"].split()) for v in chapter["verses"]))
with open(os.path.join(ROOT, "chapter-words.json"), "w", encoding="utf-8") as f:
    json.dump({"contentVersion": 1, "words": counts}, f, separators=(",", ":"))
print(f"{len(counts)} chapters")
