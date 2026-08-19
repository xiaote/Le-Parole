#!/usr/bin/env python3
"""Fill missing part-of-speech metadata without guessing inflections.

The catalogue's inflection strings already identify nouns and adjectives. Verb
translations use the "to …" convention. The remaining five unambiguous
function words are deliberately listed below, so every assignment is
deterministic and reviewable. Inflection strings are left untouched: generating
Italian noun/adjective paradigms or verb conjugations mechanically would add
incorrect forms to study-answer validation.

Preview changes:
    python3 tools/complete_vocabulary_metadata.py

Write the completed part-of-speech values:
    python3 tools/complete_vocabulary_metadata.py --write
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATA_DIRECTORY = REPOSITORY_ROOT / "Le Parole" / "Data"
WORD_FILES = sorted(DATA_DIRECTORY.glob("words_*.json"))
MANUAL_PARTS_OF_SPEECH = {
    "ancora": "adverb",
    "insieme": "adverb",
    "spesso": "adverb",
    "subito": "adverb",
    "infermiere": "noun",
}


def infer_part_of_speech(word: dict) -> tuple[str, str]:
    inflections = word.get("inflections") or ""
    english = word["english"].casefold()
    italian = word["italian"].casefold()
    if inflections.startswith("Noun:"):
        return "noun", "noun inflections"
    if inflections.startswith("Adj:"):
        return "adjective", "adjective inflections"
    if english.startswith("to "):
        return "verb", "English infinitive gloss"
    if italian in MANUAL_PARTS_OF_SPEECH:
        return MANUAL_PARTS_OF_SPEECH[italian], "curated function-word override"
    raise ValueError(f"Cannot infer part of speech for {word['id']} ({word['italian']})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write missing part-of-speech values")
    args = parser.parse_args()

    updates = Counter()
    unresolved: list[str] = []
    changed = 0
    for path in WORD_FILES:
        words = json.loads(path.read_text(encoding="utf-8"))
        for word in words:
            if word.get("partOfSpeech"):
                continue
            try:
                part_of_speech, reason = infer_part_of_speech(word)
            except ValueError as error:
                unresolved.append(str(error))
                continue
            updates[reason] += 1
            if args.write:
                word["partOfSpeech"] = part_of_speech
                changed += 1
        if args.write:
            path.write_text(json.dumps(words, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")

    if unresolved:
        raise SystemExit("Metadata completion failed:\n- " + "\n- ".join(unresolved))
    action = "Updated" if args.write else "Would update"
    print(f"{action} {changed if args.write else sum(updates.values())} part-of-speech values.")
    print("Assignments: " + ", ".join(f"{reason}={count}" for reason, count in sorted(updates.items())))


if __name__ == "__main__":
    main()
