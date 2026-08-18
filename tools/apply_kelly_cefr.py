#!/usr/bin/env python3
"""Apply source-backed CEFR labels from the official KELLY Italian list.

The KELLY project is a corpus-informed, language-learning vocabulary project
that assigns Italian vocabulary to CEFR bands. This tool updates only an exact
Italian headword match when its part of speech is compatible with the bundled
entry. Ambiguous senses and part-of-speech mismatches are reported, not guessed.

Download the public source workbook first:
    curl -L --fail --silent --show-error \
      https://ssharoff.github.io/kelly/it_m3.xls -o /path/to/it_m3.xls

Install the pinned parser dependency:
    python3 -m pip install -r tools/requirements-vocabulary.txt

Preview the update:
    python3 tools/apply_kelly_cefr.py --source /path/to/it_m3.xls

Write source-backed labels and the audit report:
    python3 tools/apply_kelly_cefr.py --source /path/to/it_m3.xls --write
"""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import xlrd
except ImportError as error:  # pragma: no cover - exercised by users without the tool dependency.
    raise SystemExit(
        "xlrd is required. Run: python3 -m pip install -r tools/requirements-vocabulary.txt"
    ) from error


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATA_DIRECTORY = REPOSITORY_ROOT / "Le Parole" / "Data"
REPORT_PATH = REPOSITORY_ROOT / "tools" / "audits" / "cefr_audit.json"
WORD_FILES = sorted(DATA_DIRECTORY.glob("words_*.json"))
CEFR_LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}
KELLY_SOURCE_URL = "https://ssharoff.github.io/kelly/it_m3.xls"


@dataclass
class VocabularyEntry:
    path: Path
    index: int
    data: dict[str, Any]


@dataclass(frozen=True)
class KellyEntry:
    part_of_speech: str
    level: str
    lemma: str


def normalize_italian(value: str) -> str:
    return (
        unicodedata.normalize("NFC", value)
        .strip()
        .casefold()
        .replace("’", "'")
        .replace("‘", "'")
        .replace("`", "'")
    )


def app_part_of_speech_codes(value: object) -> set[str]:
    """Map the app's descriptive labels to the compact KELLY POS codes."""
    part_of_speech = str(value or "").casefold()
    codes: set[str] = set()
    if "noun" in part_of_speech:
        codes.add("n")
    if "verb" in part_of_speech:
        codes.add("v")
    if "adjective" in part_of_speech:
        codes.add("adj")
    if "adverb" in part_of_speech:
        codes.add("adv")
    if "preposition" in part_of_speech:
        codes.add("prep")
    if "conjunction" in part_of_speech:
        codes.add("conj")
    if "pronoun" in part_of_speech:
        codes.add("pron")
    if "interjection" in part_of_speech or "exclamation" in part_of_speech:
        codes.add("int")
    if any(token in part_of_speech for token in ("number", "numeral", "ordinal")):
        codes.add("num")
    return codes


def load_entries() -> list[VocabularyEntry]:
    entries: list[VocabularyEntry] = []
    for path in WORD_FILES:
        words = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(words, list):
            raise ValueError(f"{path} must contain a JSON array")
        entries.extend(VocabularyEntry(path, index, word) for index, word in enumerate(words))
    return entries


def load_kelly_entries(path: Path) -> tuple[dict[str, list[KellyEntry]], int, int]:
    if not path.is_file():
        raise ValueError(f"KELLY source workbook does not exist: {path}")

    workbook = xlrd.open_workbook(path)
    sheet = workbook.sheet_by_index(0)
    if sheet.row_values(0)[:3] != ["Lemma", "Pos", "Points"]:
        raise ValueError("Unexpected KELLY workbook header; expected Lemma, Pos, Points")

    entries: dict[str, list[KellyEntry]] = defaultdict(list)
    labelled_rows = 0
    for row_index in range(1, sheet.nrows):
        lemma, part_of_speech, level = (str(value).strip() for value in sheet.row_values(row_index)[:3])
        if level not in CEFR_LEVELS:
            continue
        if not lemma:
            continue
        entries[normalize_italian(lemma)].append(KellyEntry(part_of_speech, level, lemma))
        labelled_rows += 1
    return entries, sheet.nrows - 1, labelled_rows


def resolve_level(entry: VocabularyEntry, candidates: list[KellyEntry]) -> tuple[str | None, str]:
    """Return a safe source label and the reason it is safe, if any."""
    if not candidates:
        return None, "no labelled KELLY entry"

    app_codes = app_part_of_speech_codes(entry.data.get("partOfSpeech"))
    if not app_codes:
        levels = {candidate.level for candidate in candidates}
        if len(levels) == 1:
            return next(iter(levels)), "unambiguous lemma; no app part of speech"
        return None, "ambiguous KELLY senses; no app part of speech"

    compatible = [candidate for candidate in candidates if candidate.part_of_speech in app_codes]
    if not compatible:
        return None, "part-of-speech mismatch"
    levels = {candidate.level for candidate in compatible}
    if len(levels) == 1:
        return next(iter(levels)), "unambiguous compatible part of speech"
    return None, "ambiguous compatible KELLY senses"


def audit(
    entries: list[VocabularyEntry],
    kelly_entries: dict[str, list[KellyEntry]],
    source_path: Path,
    source_rows: int,
    labelled_rows: int,
) -> tuple[dict[str, Any], dict[tuple[Path, int], str]]:
    resolutions = Counter()
    changes: list[dict[str, Any]] = []
    unresolved: list[dict[str, Any]] = []
    updates: dict[tuple[Path, int], str] = {}

    for entry in entries:
        candidates = kelly_entries.get(normalize_italian(entry.data["italian"]), [])
        new_level, reason = resolve_level(entry, candidates)
        resolutions[reason] += 1
        if new_level is None:
            if candidates:
                unresolved.append(
                    {
                        "id": entry.data["id"],
                        "italian": entry.data["italian"],
                        "appPartOfSpeech": entry.data.get("partOfSpeech"),
                        "currentLevel": entry.data["level"],
                        "reason": reason,
                        "kellyCandidates": [
                            {"lemma": candidate.lemma, "partOfSpeech": candidate.part_of_speech, "level": candidate.level}
                            for candidate in candidates
                        ],
                    }
                )
            continue

        updates[(entry.path, entry.index)] = new_level
        if new_level != entry.data["level"]:
            changes.append(
                {
                    "id": entry.data["id"],
                    "italian": entry.data["italian"],
                    "partOfSpeech": entry.data.get("partOfSpeech"),
                    "from": entry.data["level"],
                    "to": new_level,
                    "reason": reason,
                }
            )

    change_directions = Counter(f"{change['from']}→{change['to']}" for change in changes)
    resulting_level_counts = Counter(
        updates.get((entry.path, entry.index), entry.data["level"]) for entry in entries
    )
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    report = {
        "schemaVersion": 1,
        "cefrSource": {
            "name": "KELLY Italian word list",
            "project": "KELLY (Keywords for Language Learning)",
            "sourceUrl": KELLY_SOURCE_URL,
            "file": source_path.name,
            "sha256": source_hash,
            "worksheet": "Italian_for_Translators",
        },
        "catalogueWordCount": len(entries),
        "sourceRowCount": source_rows,
        "sourceLabelledRowCount": labelled_rows,
        "exactHeadwordMatches": sum(1 for entry in entries if normalize_italian(entry.data["italian"]) in kelly_entries),
        "sourceBackedAssignments": len(updates),
        "changedLevelCount": len(changes),
        "unchangedSourceBackedCount": len(updates) - len(changes),
        "resolutionCounts": dict(sorted(resolutions.items())),
        "changeDirections": dict(sorted(change_directions.items())),
        "resultingLevelCounts": {level: resulting_level_counts[level] for level in sorted(CEFR_LEVELS)},
        "unresolvedAmbiguitiesOrMismatches": unresolved,
    }
    return report, updates


def write_levels(updates: dict[tuple[Path, int], str]) -> int:
    updated = 0
    updates_by_path: dict[Path, dict[int, str]] = defaultdict(dict)
    for (path, index), level in updates.items():
        updates_by_path[path][index] = level

    for path, path_updates in updates_by_path.items():
        words = json.loads(path.read_text(encoding="utf-8"))
        for index, level in path_updates.items():
            if words[index]["level"] != level:
                words[index]["level"] = level
                updated += 1
        path.write_text(json.dumps(words, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="path to the downloaded it_m3.xls workbook")
    parser.add_argument("--write", action="store_true", help="write source-backed labels into the bundled JSON files")
    parser.add_argument("--report", type=Path, default=REPORT_PATH, help="path for the audit report")
    args = parser.parse_args()

    entries = load_entries()
    kelly_entries, source_rows, labelled_rows = load_kelly_entries(args.source)
    report, updates = audit(entries, kelly_entries, args.source, source_rows, labelled_rows)

    if args.write:
        updated = write_levels(updates)
        print(f"Updated {updated} CEFR labels across {len(WORD_FILES)} files.")
    else:
        print(f"Preview only: {report['changedLevelCount']} CEFR labels would be updated; pass --write to apply them.")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Source-backed labels: {report['sourceBackedAssignments']}/{report['catalogueWordCount']}; "
        f"unresolved source matches: {len(report['unresolvedAmbiguitiesOrMismatches'])}; report: {args.report}"
    )


if __name__ == "__main__":
    main()
