#!/usr/bin/env python3
"""Rebuild the bundled vocabulary's deterministic Italian frequency ordering.

The former frequencyRank values were combined from several independently ordered
lists. They therefore contained collisions and could not be compared across the
full catalogue. This tool replaces them with one rank per bundled headword.
It uses wordfreq's Italian usage estimates for individual words, PAISÀ's
Italian lemma counts to avoid understating verb infinitives, and PAISÀ as a
fallback for individual words missing from wordfreq. Multi-word cards are
bounded by the least-frequent component instead of using wordfreq's synthetic
phrase estimate, which is not a reliable measure of phrase frequency.

The script intentionally does not change CEFR labels. Frequency and CEFR measure
different things, so CEFR labels remain in the curated catalogue rather than
being inferred from a rank.

Install the pinned dependency into a temporary virtual environment or target
directory before running:
    python3 -m pip install -r tools/requirements-vocabulary.txt

Preview changes:
    python3 tools/rebuild_frequency_ranks.py --paisa-source /path/to/lemma-frequencies-paisa.txt.gz

Write ranks and a review report:
    python3 tools/rebuild_frequency_ranks.py --paisa-source /path/to/lemma-frequencies-paisa.txt.gz --write

Download the public PAISÀ lemma list:
    curl -L --fail --silent --show-error \
      'https://clarin.eurac.edu/repository/xmlui/bitstream/handle/20.500.12124/3/lemma-frequencies-paisa.txt.gz?sequence=7&isAllowed=y' \
      -o /path/to/lemma-frequencies-paisa.txt.gz
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import unicodedata
from collections import Counter
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
PAISA_SOURCE_URL = (
    "https://clarin.eurac.edu/repository/xmlui/bitstream/handle/20.500.12124/3/"
    "lemma-frequencies-paisa.txt.gz?sequence=7&isAllowed=y"
)
# A phrase must realize a particular combination of words, so its frequency is
# safely below that of its rarest component. One Zipf point is a tenfold
# reduction; this deliberately conservative adjustment prevents a component
# bound from being mistaken for an observed phrase frequency.
PHRASE_COMPONENT_PENALTY = 1.0


@dataclass
class VocabularyEntry:
    path: Path
    index: int
    data: dict[str, Any]
    normalized_italian: str
    wordfreq_zipf: float
    paisa_count: int = 0
    score: float = 0
    source: str = "unranked"
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
                    wordfreq_zipf=zipf_frequency(normalized, "it"),
                )
            )

    return entries


def load_paisa_frequencies(path: Path) -> tuple[Counter[str], int]:
    """Load and case-normalize PAISÀ's lemma counts, preserving case variants."""
    if not path.is_file():
        raise ValueError(f"PAISÀ lemma-frequency file does not exist: {path}")

    frequencies: Counter[str] = Counter()
    total_tokens = 0
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as source:
        for line in source:
            if "," not in line:
                continue
            lemma, count = line.rstrip("\n").rsplit(",", 1)
            if not count.isdigit():
                continue
            frequency = int(count)
            frequencies[normalize_italian(lemma)] += frequency
            total_tokens += frequency

    if not frequencies or total_tokens == 0:
        raise ValueError(f"PAISÀ source contains no lemma frequencies: {path}")
    return frequencies, total_tokens


def paisa_zipf(count: int, total_tokens: int) -> float:
    """Convert a PAISÀ lemma count to wordfreq's Zipf-score unit."""
    return math.log10(count * 1_000_000_000 / total_tokens) if count else 0


def is_verb(entry: VocabularyEntry) -> bool:
    return (entry.data.get("partOfSpeech") or "").casefold().split("/")[0].strip() == "verb"


def component_score(token: str, paisa_frequencies: Counter[str], paisa_tokens: int) -> float:
    """Use the strongest directly attested score available for one word."""
    normalized = normalize_italian(token)
    return max(zipf_frequency(normalized, "it"), paisa_zipf(paisa_frequencies.get(normalized, 0), paisa_tokens))


def score_entries(entries: list[VocabularyEntry], paisa_frequencies: Counter[str], paisa_tokens: int) -> None:
    """Score lexical cards by corpus evidence without inflating phrases."""
    for entry in entries:
        entry.paisa_count = paisa_frequencies.get(entry.normalized_italian, 0)
        paisa_score = paisa_zipf(entry.paisa_count, paisa_tokens)
        tokens = entry.normalized_italian.split()

        if len(tokens) > 1:
            component_scores = [component_score(token, paisa_frequencies, paisa_tokens) for token in tokens]
            if all(component_scores):
                # A phrase cannot occur more often than its least-frequent
                # component. Discount that bound by one Zipf point because a
                # particular combination is necessarily less common than one
                # component. This avoids wordfreq's synthetic multi-token
                # estimate while preserving useful expressions near their
                # component vocabulary.
                entry.score = min(component_scores) - PHRASE_COMPONENT_PENALTY
                entry.source = "phrase-component-bound"
            else:
                entry.score = 0
                entry.source = "unranked"
            continue

        if is_verb(entry) and paisa_score > entry.wordfreq_zipf:
            # Headwords are infinitives, while Italian verbs usually occur in
            # conjugated forms. PAISÀ is lemma-based, so it restores the
            # aggregate corpus frequency for those cards.
            entry.score = paisa_score
            entry.source = "paisa-lemma-verb"
        elif entry.wordfreq_zipf > 0:
            entry.score = entry.wordfreq_zipf
            entry.source = "wordfreq"
        elif paisa_score:
            # Zipf is log10 occurrences per billion words, so PAISÀ fallback
            # values share the same unit as wordfreq and can be sorted together.
            entry.score = paisa_score
            entry.source = "paisa-fallback"
        else:
            entry.score = 0
            entry.source = "unranked"


def rank_entries(entries: list[VocabularyEntry]) -> None:
    # Higher scores are more common. Final keys make ties deterministic.
    for rank, entry in enumerate(
        sorted(entries, key=lambda item: (-item.score, item.normalized_italian, item.data["id"])),
        start=1,
    ):
        entry.rank = rank


def audit(entries: list[VocabularyEntry], paisa_path: Path, paisa_tokens: int) -> dict[str, Any]:
    source_counts = Counter(entry.source for entry in entries)
    unmatched_words = [
        {
            "id": entry.data["id"],
            "italian": entry.data["italian"],
            "english": entry.data["english"],
            "level": entry.data["level"],
            "partOfSpeech": entry.data.get("partOfSpeech"),
        }
        for entry in entries
        if entry.source == "unranked"
    ]

    digest = hashlib.sha256(
        "\n".join(
            f"{entry.data['id']}:{entry.rank}:{entry.score:.4f}:{entry.source}"
            for entry in sorted(entries, key=lambda item: item.data["id"])
        ).encode("utf-8")
    ).hexdigest()

    return {
        "schemaVersion": 4,
        "frequencySources": {
            "primary": {
                "name": "wordfreq",
                "version": "3.1.1",
                "language": "it",
                "metric": "Zipf frequency from wordfreq's best available Italian data",
            },
            "lemmaSource": {
                "name": "PAISÀ Corpus lemma frequencies",
                "sourceUrl": PAISA_SOURCE_URL,
                "file": paisa_path.name,
                "sha256": hashlib.sha256(paisa_path.read_bytes()).hexdigest(),
                "tokenCount": paisa_tokens,
                "metric": "case-normalized lemma count converted to Zipf frequency",
            },
        },
        "coverage": {
            "wordfreq": source_counts["wordfreq"],
            "paisaLemmaVerb": source_counts["paisa-lemma-verb"],
            "paisaFallback": source_counts["paisa-fallback"],
            "phraseComponentBound": source_counts["phrase-component-bound"],
            "unranked": source_counts["unranked"],
        },
        "wordCount": len(entries),
        "matchedFrequencyCount": len(entries) - source_counts["unranked"],
        "unmatchedFrequencyCount": source_counts["unranked"],
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
    parser.add_argument(
        "--paisa-source",
        type=Path,
        required=True,
        help="path to PAISÀ's lemma-frequencies-paisa.txt or .gz file",
    )
    parser.add_argument("--write", action="store_true", help="write recalculated ranks into the bundled JSON files")
    parser.add_argument("--report", type=Path, default=REPORT_PATH, help="path for the audit report")
    args = parser.parse_args()

    entries = load_entries()
    paisa_frequencies, paisa_tokens = load_paisa_frequencies(args.paisa_source)
    score_entries(entries, paisa_frequencies, paisa_tokens)
    rank_entries(entries)
    report = audit(entries, args.paisa_source, paisa_tokens)

    if args.write:
        changed = write_entries(entries)
        print(f"Updated {changed} frequency ranks across {len(WORD_FILES)} files.")
    else:
        changed = 0
        print(f"Preview only: {len(entries)} ranks calculated; pass --write to update the bundled files.")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Frequency coverage: {report['matchedFrequencyCount']}/{report['wordCount']} "
        f"(wordfreq={report['coverage']['wordfreq']}, PAISÀ verb lemma={report['coverage']['paisaLemmaVerb']}, "
        f"PAISÀ fallback={report['coverage']['paisaFallback']}, phrase bounds={report['coverage']['phraseComponentBound']}); "
        f"report: {args.report}"
    )
    if args.write and changed == 0:
        print("Ranks were already current.")


if __name__ == "__main__":
    main()
