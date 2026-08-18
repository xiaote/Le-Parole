#!/usr/bin/env python3
"""Rebuild the bundled vocabulary's deterministic Italian frequency ordering.

The former frequencyRank values were combined from several independently ordered
lists. They therefore contained collisions and could not be compared across the
full catalogue. This tool replaces them with one rank per bundled headword,
derived from wordfreq's Italian frequency data.

The script intentionally does not change CEFR labels. Frequency and CEFR measure
different things, so CEFR labels are maintained by apply_kelly_cefr.py rather
than inferred from a rank.

Install the pinned dependency into a temporary virtual environment or target
directory before running:
    python3 -m pip install -r tools/requirements-vocabulary.txt

Preview changes:
    python3 tools/rebuild_frequency_ranks.py

Write ranks and a review report:
    python3 tools/rebuild_frequency_ranks.py --write
"""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from wordfreq import zipf_frequency
except ImportError as error:  # pragma: no cover - exercised by users without the tool dependency.
    raise SystemExit(
        "wordfreq is required. Run: python3 -m pip install -r tools/requirements-vocabulary.txt"
    ) from error


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATA_DIRECTORY = REPOSITORY_ROOT / "Le Parole" / "Data"
REPORT_PATH = REPOSITORY_ROOT / "tools" / "audits" / "frequency_audit.json"
WORD_FILES = sorted(DATA_DIRECTORY.glob("words_*.json"))
CEFR_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}


@dataclass
class VocabularyEntry:
    path: Path
    index: int
    data: dict[str, Any]
    normalized_italian: str
    zipf: float
    rank: int = 0


def normalize_italian(value: str) -> str:
    """Normalize only for frequency lookup and deterministic sorting."""
    return (
        unicodedata.normalize("NFC", value)
        .strip()
        .casefold()
        .replace("’", "'")
        .replace("‘", "'")
        .replace("`", "'")
    )


def load_entries() -> list[VocabularyEntry]:
    entries: list[VocabularyEntry] = []
    ids: set[str] = set()
    italian_headwords: set[str] = set()

    for path in WORD_FILES:
        words = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(words, list):
            raise ValueError(f"{path} must contain a JSON array")

        for index, word in enumerate(words):
            word_id = word.get("id")
            italian = word.get("italian")
            english = word.get("english")
            level = word.get("level")
            if not all(isinstance(value, str) and value.strip() for value in (word_id, italian, english)):
                raise ValueError(f"{path.name}[{index}] is missing an id, Italian headword, or English gloss")
            if level not in CEFR_LEVELS:
                raise ValueError(f"{path.name}[{index}] has unsupported CEFR label {level!r}")

            normalized = normalize_italian(italian)
            if word_id in ids:
                raise ValueError(f"Duplicate id: {word_id}")
            if normalized in italian_headwords:
                raise ValueError(f"Duplicate Italian headword: {italian}")
            ids.add(word_id)
            italian_headwords.add(normalized)

            entries.append(
                VocabularyEntry(
                    path=path,
                    index=index,
                    data=word,
                    normalized_italian=normalized,
                    zipf=zipf_frequency(normalized, "it"),
                )
            )

    return entries


def rank_entries(entries: list[VocabularyEntry]) -> None:
    # Higher Zipf frequency is more common. The final two keys make the result
    # stable even when wordfreq rounds two terms to the same score.
    for rank, entry in enumerate(
        sorted(entries, key=lambda item: (-item.zipf, item.normalized_italian, item.data["id"])),
        start=1,
    ):
        entry.rank = rank


def audit(entries: list[VocabularyEntry]) -> dict[str, Any]:
    matched = sum(entry.zipf > 0 for entry in entries)
    unmatched_words = [
        {
            "id": entry.data["id"],
            "italian": entry.data["italian"],
            "english": entry.data["english"],
            "level": entry.data["level"],
            "partOfSpeech": entry.data.get("partOfSpeech"),
        }
        for entry in entries
        if entry.zipf == 0
    ]

    digest = hashlib.sha256(
        "\n".join(
            f"{entry.data['id']}:{entry.rank}:{entry.zipf:.2f}" for entry in sorted(entries, key=lambda item: item.data["id"])
        ).encode("utf-8")
    ).hexdigest()

    return {
        "schemaVersion": 2,
        "frequencySource": {
            "name": "wordfreq",
            "version": "3.1.1",
            "language": "it",
            "metric": "Zipf frequency from wordfreq's best available Italian data",
        },
        "wordCount": len(entries),
        "matchedFrequencyCount": matched,
        "unmatchedFrequencyCount": len(entries) - matched,
        "unmatchedFrequencyWords": unmatched_words,
        "rankDigest": digest,
    }


def write_entries(entries: list[VocabularyEntry]) -> int:
    changed = 0
    entries_by_path: dict[Path, list[VocabularyEntry]] = {}
    for entry in entries:
        entries_by_path.setdefault(entry.path, []).append(entry)

    for path, file_entries in entries_by_path.items():
        words = json.loads(path.read_text(encoding="utf-8"))
        for entry in file_entries:
            if words[entry.index].get("frequencyRank") != entry.rank:
                words[entry.index]["frequencyRank"] = entry.rank
                changed += 1
        # Keep the established four-space JSON formatting so a rank refresh
        # produces a reviewable data diff instead of a whole-file reformat.
        path.write_text(json.dumps(words, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")

    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write recalculated ranks into the bundled JSON files")
    parser.add_argument("--report", type=Path, default=REPORT_PATH, help="path for the audit report")
    args = parser.parse_args()

    entries = load_entries()
    rank_entries(entries)
    report = audit(entries)

    if args.write:
        changed = write_entries(entries)
        print(f"Updated {changed} frequency ranks across {len(WORD_FILES)} files.")
    else:
        changed = 0
        print(f"Preview only: {len(entries)} ranks calculated; pass --write to update the bundled files.")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Frequency coverage: {report['matchedFrequencyCount']}/{report['wordCount']}; report: {args.report}"
    )
    if args.write and changed == 0:
        print("Ranks were already current.")


if __name__ == "__main__":
    main()
