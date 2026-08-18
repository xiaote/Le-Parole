#!/usr/bin/env python3
"""Consolidate verified orthographic duplicate entries in the bundled catalogue.

This only removes variants that represent the same learning card. The matching
app migration merges their userWords records before the old IDs are retired.
English glosses and answer alternatives are folded into the canonical entry.

Preview changes:
    python3 tools/consolidate_catalogue_duplicates.py

Write the cleaned catalogue:
    python3 tools/consolidate_catalogue_duplicates.py --write
"""

from __future__ import annotations

import argparse
import json
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Le Parole" / "Data"

# The left-hand word is a verified duplicate of the right-hand canonical word.
# The app's v22 migration preserves every review result before retiring it.
REDIRECTS = {
    "comm_406": "2037",           # cosi → così
    "comm_10049": "comm_11857",   # equipe → équipe
    "comm_10851": "comm_1040",    # modalita → modalità
    "comm_384": "comm_1208",      # papa (incorrectly glossed as dad) → papà
    "comm_323": "comm_6",         # piu → più
    "comm_13094": "comm_3866",    # pressochè → pressoché
    "comm_16341": "comm_1999",    # priorita → priorità
    "comm_16342": "comm_1816",    # probabilita → probabilità
    "comm_5660": "393",           # qualita → qualità
    "comm_13543": "comm_11827",   # rossoblu → rossoblù
    "comm_4578": "465",           # venerdi → venerdì
    "comm_13785": "comm_4596",    # dopodichè → dopodiché
    "comm_9145": "comm_1333",     # fin'ora → finora
    "comm_6403": "comm_2161",     # tutt'ora → tuttora
}


def normalized(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip().casefold()


def is_new_value(value: str, target: dict[str, Any]) -> bool:
    existing = [target["english"], *target.get("alternatives", [])]
    return normalized(value) not in {normalized(existing_value) for existing_value in existing}


def load_catalogue() -> tuple[dict[str, list[dict[str, Any]]], dict[str, tuple[Path, dict[str, Any]]]]:
    files: dict[str, list[dict[str, Any]]] = {}
    entries: dict[str, tuple[Path, dict[str, Any]]] = {}
    for path in sorted(DATA.glob("words_*.json")):
        words = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(words, list):
            raise ValueError(f"{path} must contain a JSON array")
        files[str(path)] = words
        for word in words:
            word_id = word.get("id")
            if not isinstance(word_id, str) or not word_id:
                raise ValueError(f"{path} contains an entry without an id")
            if word_id in entries:
                raise ValueError(f"Duplicate id {word_id}")
            entries[word_id] = (path, word)
    return files, entries


def consolidate(entries: dict[str, tuple[Path, dict[str, Any]]]) -> int:
    consolidated = 0
    for retired_id, canonical_id in REDIRECTS.items():
        if retired_id not in entries:
            # A second run should be a harmless no-op once the canonical entry
            # has been written successfully.
            if canonical_id in entries:
                continue
            raise ValueError(f"Neither retired word {retired_id} nor canonical word {canonical_id} is present")
        if canonical_id not in entries:
            raise ValueError(f"Canonical word {canonical_id} is not present in the source catalogue")

        _, retired = entries[retired_id]
        _, canonical = entries[canonical_id]
        alternatives = list(canonical.get("alternatives", []))
        for value in [retired["english"], *retired.get("alternatives", [])]:
            if is_new_value(value, {**canonical, "alternatives": alternatives}):
                alternatives.append(value)
        canonical["alternatives"] = alternatives

        # Retain useful grammatical detail where an older base-list record had
        # omitted it, without changing the canonical meaning or headword.
        for field in ("partOfSpeech", "inflections"):
            if not canonical.get(field) and retired.get(field):
                canonical[field] = retired[field]
        consolidated += 1

    return consolidated


def write_catalogue(files: dict[str, list[dict[str, Any]]]) -> None:
    retired_ids = set(REDIRECTS)
    for path_string, words in files.items():
        path = Path(path_string)
        retained = [word for word in words if word["id"] not in retired_ids]
        path.write_text(json.dumps(retained, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write the consolidated word lists")
    args = parser.parse_args()

    files, entries = load_catalogue()
    count = consolidate(entries)
    if args.write:
        write_catalogue(files)
        print(f"Consolidated {count} verified duplicate entries.")
    else:
        print(f"Preview only: {count} verified duplicate entries would be consolidated; pass --write to apply them.")


if __name__ == "__main__":
    main()
