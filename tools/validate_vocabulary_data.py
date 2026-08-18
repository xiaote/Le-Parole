#!/usr/bin/env python3
"""Validate the bundled vocabulary files without rewriting them."""

from __future__ import annotations

import json
import sqlite3
import sys
import unicodedata
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Le Parole" / "Data"
LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}
# These IDs are retired by app migrations after their userWords history is
# merged into the canonical ID. Keeping the redirect here lets a pre-migration
# backup be validated against the new catalogue as well.
RETIRED_WORD_REDIRECTS = {
    "comm_1670": "comm_6",
    "1276": "comm_3313",
    "comm_406": "2037",
    "comm_10049": "comm_11857",
    "comm_10851": "comm_1040",
    "comm_384": "comm_1208",
    "comm_323": "comm_6",
    "comm_13094": "comm_3866",
    "comm_16341": "comm_1999",
    "comm_16342": "comm_1816",
    "comm_5660": "393",
    "comm_13543": "comm_11827",
    "comm_4578": "465",
    "comm_13785": "comm_4596",
    "comm_9145": "comm_1333",
    "comm_6403": "comm_2161",
}
RETIRED_WORD_IDS = {
    "comm_9227", "comm_7994", "comm_6213", "comm_5973", "comm_10902",
    "comm_10519", "comm_10132", "comm_14046", "comm_13890", "comm_11981",
    "comm_15264", "comm_10259", "comm_12681", "comm_16383", "comm_16537",
    "comm_14446", "comm_12343", "comm_13695", "comm_15727",
}


def normalized(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip().casefold()


def main() -> None:
    database_path = Path(sys.argv[1]) if len(sys.argv) == 2 else None
    if len(sys.argv) > 2:
        raise SystemExit("Usage: python3 tools/validate_vocabulary_data.py [database.sqlite]")

    errors: list[str] = []
    entries: list[dict] = []
    seen_ids: set[str] = set()
    seen_italian: set[str] = set()

    for path in sorted(DATA.glob("words_*.json")):
        try:
            words = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            errors.append(f"{path.name}: invalid JSON ({error})")
            continue
        if not isinstance(words, list):
            errors.append(f"{path.name}: top-level value must be an array")
            continue

        for index, word in enumerate(words):
            prefix = f"{path.name}[{index}]"
            if not isinstance(word, dict):
                errors.append(f"{prefix}: entry must be an object")
                continue
            for required in ("id", "italian", "english", "level", "frequencyRank"):
                if required not in word or (isinstance(word[required], str) and not word[required].strip()):
                    errors.append(f"{prefix}: missing {required}")
            if word.get("level") not in LEVELS:
                errors.append(f"{prefix}: unsupported CEFR level {word.get('level')!r}")
            if not isinstance(word.get("frequencyRank"), int) or word.get("frequencyRank", 0) < 1:
                errors.append(f"{prefix}: frequencyRank must be a positive integer")
            if not isinstance(word.get("alternatives", []), list) or not all(
                isinstance(value, str) and value.strip() for value in word.get("alternatives", [])
            ):
                errors.append(f"{prefix}: alternatives must be an array of non-empty strings")

            word_id = word.get("id")
            italian = word.get("italian")
            if isinstance(word_id, str):
                if word_id in seen_ids:
                    errors.append(f"{prefix}: duplicate id {word_id!r}")
                seen_ids.add(word_id)
            if isinstance(italian, str):
                headword = normalized(italian)
                if headword in seen_italian:
                    errors.append(f"{prefix}: duplicate Italian headword {italian!r}")
                seen_italian.add(headword)
            entries.append(word)

    ranks = [word["frequencyRank"] for word in entries if isinstance(word.get("frequencyRank"), int)]
    expected_ranks = set(range(1, len(entries) + 1))
    if set(ranks) != expected_ranks or len(ranks) != len(set(ranks)):
        errors.append("frequencyRank must be a collision-free sequence from 1 through the word count")

    if errors:
        print("Vocabulary validation failed:", file=sys.stderr)
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        raise SystemExit(1)

    level_counts = Counter(word["level"] for word in entries)
    print(f"Validated {len(entries)} words with unique frequency ranks.")
    print("Levels: " + ", ".join(f"{level}={level_counts[level]}" for level in sorted(level_counts)))

    if database_path:
        if not database_path.is_file():
            raise SystemExit(f"Database does not exist: {database_path}")
        source_ids = {word["id"] for word in entries}
        with sqlite3.connect(database_path) as connection:
            bundled_ids = {
                row[0]
                for row in connection.execute("SELECT wordId FROM words WHERE isUserCreated = 0")
            }
            history_ids = {
                row[0]
                for row in connection.execute(
                    """
                    SELECT DISTINCT uw.wordId
                    FROM userWords uw
                    JOIN words w ON w.wordId = uw.wordId
                    WHERE w.isUserCreated = 0
                    """
                )
            }
            history_count = connection.execute("SELECT COUNT(*) FROM userWords").fetchone()[0]

        retired_ids = set(RETIRED_WORD_REDIRECTS) | RETIRED_WORD_IDS
        missing_catalogue_ids = (bundled_ids - source_ids) - retired_ids
        missing_history_ids = (history_ids - source_ids) - retired_ids
        if missing_catalogue_ids or missing_history_ids:
            problems = []
            if missing_catalogue_ids:
                problems.append(f"{len(missing_catalogue_ids)} bundled database IDs are absent from the source catalogue")
            if missing_history_ids:
                problems.append(f"{len(missing_history_ids)} learning-history IDs are absent from the source catalogue")
            raise SystemExit("Database compatibility validation failed: " + "; ".join(problems))

        print(
            f"Database compatibility: {len(bundled_ids)} bundled IDs and "
            f"{history_count} learning records are preserved by this catalogue."
        )
        redirects_present = history_ids & set(RETIRED_WORD_REDIRECTS)
        if redirects_present:
            print(
                "Pending catalogue redirects: "
                + ", ".join(f"{word_id} → {RETIRED_WORD_REDIRECTS[word_id]}" for word_id in sorted(redirects_present))
            )
        retired_number_ids_present = history_ids & RETIRED_WORD_IDS
        if retired_number_ids_present:
            print(f"Pending number-card retirement: {len(retired_number_ids_present)} history records will be kept as skipped")


if __name__ == "__main__":
    main()
