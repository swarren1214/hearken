#!/usr/bin/env python3
"""Builds Hearken/Resources/Kokoro/pronunciations.json from scripts/pronunciations.txt.

Each respelling becomes two pronunciations:
  - "kokoro": Kokoro's phoneme notation (misaki), for the natural voices
  - "ipa":    standard IPA, for the system voices (AVSpeechSynthesizer)

Run after editing pronunciations.txt:  python3 scripts/build_pronunciations.py
"""

import json
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "pronunciations.txt"
OUTPUT = ROOT / "Hearken" / "Resources" / "Kokoro" / "pronunciations.json"

STRESS_MARKS = "ʹ'ˈ′"

# Vowels: (stressed misaki, unstressed misaki, stressed IPA, unstressed IPA)
VOWELS = {
    "ou": ("W", "W", "aʊ", "aʊ"),
    "er": ("ɜɹ", "əɹ", "ɝ", "ɚ"),
    "ā": ("A", "A", "eɪ", "eɪ"),
    "ă": ("æ", "æ", "æ", "æ"),
    "ä": ("ɑ", "ɑ", "ɑ", "ɑ"),
    "â": ("ɛ", "ɛ", "ɛ", "ɛ"),
    "ô": ("ɔ", "ɔ", "ɔ", "ɔ"),
    "ē": ("i", "i", "i", "i"),
    "ĕ": ("ɛ", "ɛ", "ɛ", "ɛ"),
    "ī": ("I", "I", "aɪ", "aɪ"),
    "ĭ": ("ɪ", "ɪ", "ɪ", "ɪ"),
    "ō": ("O", "O", "oʊ", "oʊ"),
    "ŏ": ("ɑ", "ɑ", "ɑ", "ɑ"),
    "ū": ("u", "u", "u", "u"),
    "ŭ": ("ʌ", "ə", "ʌ", "ə"),
    "a": ("ʌ", "ə", "ʌ", "ə"),
    "e": ("ɛ", "ɛ", "ɛ", "ɛ"),
    "i": ("ɪ", "ɪ", "ɪ", "ɪ"),
    "o": ("ɑ", "ɑ", "ɑ", "ɑ"),
    "u": ("ʌ", "ə", "ʌ", "ə"),
}
# Consonants: (misaki, IPA)
CONSONANTS = {
    "ch": ("ʧ", "tʃ"), "sh": ("ʃ", "ʃ"), "th": ("θ", "θ"), "zh": ("ʒ", "ʒ"), "ng": ("ŋ", "ŋ"),
    "j": ("ʤ", "dʒ"), "g": ("ɡ", "ɡ"), "r": ("ɹ", "ɹ"), "y": ("j", "j"), "c": ("k", "k"),
    "q": ("k", "k"), "x": ("ks", "ks"),
}
for letter in "bdfhklmnpstvwz":
    CONSONANTS[letter] = (letter, letter)

UNITS = sorted(list(VOWELS) + list(CONSONANTS), key=len, reverse=True)


def tokens(syllable: str):
    text = unicodedata.normalize("NFC", syllable.lower())
    i = 0
    while i < len(text):
        for unit in UNITS:
            if text.startswith(unit, i):
                yield unit
                i += len(unit)
                break
        else:
            raise ValueError(f"can't read {text[i]!r} in {syllable!r}")


def syllables(respelling: str):
    """[(syllable, stress)] where stress is 0 none, 1 secondary, 2 primary (the last mark)."""
    result = []
    for piece in respelling.replace(" ", "-").split("-"):
        if not piece:
            continue
        current = ""
        for ch in piece:
            if ch in STRESS_MARKS:
                result.append([current, 1])
                current = ""
            else:
                current += ch
        if current:
            result.append([current, 0])
    marked = [i for i, (_, s) in enumerate(result) if s]
    if marked:
        result[marked[-1]][1] = 2
    elif len(result) == 1:
        result[0][1] = 2
    return result


def convert(respelling: str):
    kokoro, ipa = "", ""
    for syllable, stress in syllables(respelling):
        mark = {0: "", 1: "ˌ", 2: "ˈ"}[stress]
        k_part, placed = "", False
        i_part = ""
        for unit in tokens(syllable):
            if unit in VOWELS:
                stressed = stress > 0
                k, ku, iv, iu = VOWELS[unit]
                if not placed:
                    k_part += mark
                    placed = True
                k_part += k if stressed else ku
                i_part += iv if stressed else iu
            else:
                m, p = CONSONANTS[unit]
                k_part += m
                i_part += p
        kokoro += k_part
        ipa += mark + i_part
    return kokoro, ipa


def main():
    names = {}
    for number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if "|" not in line:
            sys.exit(f"line {number}: expected 'Name | respelling'")
        name, respelling = (part.strip() for part in line.split("|", 1))
        try:
            if respelling.startswith("/"):
                kokoro = respelling.strip("/")
                ipa = kokoro.translate(str.maketrans({"A": "eɪ", "I": "aɪ", "O": "oʊ", "W": "aʊ", "Y": "ɔɪ", "ʤ": "dʒ", "ʧ": "tʃ"}))
            else:
                kokoro, ipa = convert(respelling)
        except ValueError as error:
            sys.exit(f"line {number} ({name}): {error}")
        names[name] = {"kokoro": kokoro, "ipa": ipa}
        # Nephite → Nephites; Moroni → (no plural). Possessives ("Nephi's") work without entries.
        if name.endswith("ite"):
            names[name + "s"] = {"kokoro": kokoro + "s", "ipa": ipa + "s"}

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"version": 1, "names": dict(sorted(names.items()))}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"Wrote {len(names)} names to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
