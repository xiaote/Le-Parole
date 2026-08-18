#!/usr/bin/env python3
"""Remove mechanically derivable cardinal-number cards from the source catalogue.

The retained curriculum teaches base numbers, tens, and scale words. These
composite forms are mechanically generated from them and do not need individual
cards. The app's v23 migration preserves historical records for existing users
by changing their stage to skipped rather than deleting them.

Preview changes:
    python3 tools/retire_composite_number_cards.py

Write the revised catalogue:
    python3 tools/retire_composite_number_cards.py --write
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Le Parole" / "Data"

# Composite cardinal numerals are derived from already-retained base numbers
# and their composition rules. This deliberately excludes historical-century
# terms such as Quattrocento and non-numeric vocabulary such as ventenne.
RETIRED_NUMBER_IDS = {
    "comm_9227",   # ventuno
    "comm_7994",   # ventidue
    "comm_6213",   # ventiquattro
    "comm_5973",   # venticinque
    "comm_10902",  # ventisei
    "comm_10519",  # ventisette
    "comm_10132",  # ventotto
    "comm_14046",  # ventinove
    "comm_13890",  # trentuno
    "comm_11981",  # trentadue
    "comm_15264",  # trentaquattro
    "comm_10259",  # trentacinque
    "comm_12681",  # trentasei
    "comm_16383",  # trentotto
    "comm_16537",  # trentanove
    "comm_14446",  # quarantadue
    "comm_12343",  # quarantacinque
    "comm_13695",  # quarantotto
    "comm_15727",  # settantadue
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="remove the retired cards from the bundled JSON files")
    args = parser.parse_args()

    found: set[str] = set()
    files: list[tuple[Path, list[dict]]] = []
    for path in sorted(DATA.glob("words_*.json")):
        words = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(words, list):
            raise ValueError(f"{path} must contain a JSON array")
        found.update(word.get("id") for word in words if isinstance(word, dict))
        files.append((path, words))

    missing = RETIRED_NUMBER_IDS - found
    if missing and missing != RETIRED_NUMBER_IDS:
        raise ValueError(f"Some expected number cards are missing: {', '.join(sorted(missing))}")

    pending = RETIRED_NUMBER_IDS & found
    if args.write:
        for path, words in files:
            retained = [word for word in words if word["id"] not in RETIRED_NUMBER_IDS]
            path.write_text(json.dumps(retained, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
        print(f"Retired {len(pending)} composite number cards from the source catalogue.")
    elif pending:
        print(f"Preview only: {len(pending)} composite number cards would be retired; pass --write to apply them.")
    else:
        print("Composite number cards are already retired from the source catalogue.")


if __name__ == "__main__":
    main()
