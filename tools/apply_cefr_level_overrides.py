#!/usr/bin/env python3
"""Apply the reviewed CEFR override ledger to the bundled catalogue.

The baseline records the catalogue labels before editorial corrections.  An
active card may differ from that baseline only when it has a matching,
documented entry in ``cefr_level_overrides.json``.  This intentionally keeps
frequency out of the decision: frequency can identify review candidates but
cannot assign a CEFR level by itself.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Le Parole" / "Data"
LEDGER_PATH = ROOT / "tools" / "cefr_level_overrides.json"
BASELINE_PATH = ROOT / "tools" / "cefr_level_baseline.json"
LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def catalogue() -> tuple[dict[str, dict], dict[str, Path]]:
    entries: dict[str, dict] = {}
    paths: dict[str, Path] = {}
    for path in sorted(DATA.glob("words_*.json")):
        for entry in load_json(path):
            word_id = entry["id"]
            if word_id in entries:
                raise ValueError(f"Duplicate word ID {word_id!r}")
            entries[word_id] = entry
            paths[word_id] = path
    return entries, paths


def load_ledger() -> dict:
    ledger = load_json(LEDGER_PATH)
    if not isinstance(ledger, dict) or ledger.get("schemaVersion") != 1:
        raise ValueError("CEFR override ledger must use schemaVersion 1")
    for key in ("levelOverrides", "retirements"):
        if not isinstance(ledger.get(key), list):
            raise ValueError(f"CEFR override ledger is missing {key}")
    return ledger


def load_baseline() -> dict[str, str]:
    baseline = load_json(BASELINE_PATH)
    if not isinstance(baseline, dict) or baseline.get("schemaVersion") != 1:
        raise ValueError("CEFR baseline must use schemaVersion 1")
    levels = baseline.get("levels")
    if not isinstance(levels, dict) or not all(level in LEVELS for level in levels.values()):
        raise ValueError("CEFR baseline has invalid levels")
    return levels


def validate(entries: dict[str, dict], ledger: dict, baseline: dict[str, str]) -> list[str]:
    errors: list[str] = []
    overrides: dict[str, dict] = {}
    retirements: dict[str, dict] = {}

    for override in ledger["levelOverrides"]:
        required = ("id", "italian", "oldLevel", "newLevel", "rationale", "references")
        if not isinstance(override, dict) or any(not override.get(key) for key in required):
            errors.append(f"Invalid level override: {override!r}")
            continue
        word_id = override["id"]
        if word_id in overrides:
            errors.append(f"Duplicate level override for {word_id}")
        overrides[word_id] = override
        if override["oldLevel"] not in LEVELS or override["newLevel"] not in LEVELS:
            errors.append(f"{word_id}: invalid level override")
        if override["oldLevel"] == override["newLevel"]:
            errors.append(f"{word_id}: override must change the level")

    for retirement in ledger["retirements"]:
        required = ("id", "italian", "replacementId", "rationale", "references")
        if not isinstance(retirement, dict) or any(not retirement.get(key) for key in required):
            errors.append(f"Invalid retirement: {retirement!r}")
            continue
        word_id = retirement["id"]
        if word_id in retirements:
            errors.append(f"Duplicate retirement for {word_id}")
        retirements[word_id] = retirement
        if retirement["replacementId"] not in entries:
            errors.append(f"{word_id}: replacement {retirement['replacementId']} is not active")

    for word_id, entry in entries.items():
        baseline_level = baseline.get(word_id)
        if baseline_level is None:
            errors.append(f"{word_id}: missing from CEFR baseline")
            continue
        override = overrides.get(word_id)
        if entry["level"] == baseline_level:
            if override:
                errors.append(f"{word_id}: documented override was not applied")
        elif not override:
            errors.append(f"{word_id}: level changed from baseline without a reviewed override")
        elif (
            override["italian"] != entry["italian"]
            or override["oldLevel"] != baseline_level
            or override["newLevel"] != entry["level"]
        ):
            errors.append(f"{word_id}: active entry does not match its reviewed override")

    for word_id, override in overrides.items():
        if word_id not in entries:
            errors.append(f"{word_id}: override does not refer to an active entry")
        if word_id not in baseline:
            errors.append(f"{word_id}: override does not refer to a baseline entry")

    for word_id, retirement in retirements.items():
        if word_id in entries:
            errors.append(f"{word_id}: retired entry is still active")
        if word_id not in baseline:
            errors.append(f"{word_id}: retirement does not refer to a baseline entry")
        elif retirement["italian"] == entries.get(word_id, {}).get("italian"):
            errors.append(f"{word_id}: retirement headword was not removed")

    documented_retirements = set(retirements)
    missing_baseline_ids = set(baseline) - set(entries) - documented_retirements
    if missing_baseline_ids:
        errors.append(
            "Baseline entries removed without a documented retirement: "
            + ", ".join(sorted(missing_baseline_ids))
        )
    return errors


def write_catalogue(entries: dict[str, dict], paths: dict[str, Path], ledger: dict) -> None:
    overrides = {item["id"]: item for item in ledger["levelOverrides"]}
    retired_ids = {item["id"] for item in ledger["retirements"]}
    changed_ids: set[str] = set()

    for word_id, override in overrides.items():
        entry = entries.get(word_id)
        if entry and entry["level"] != override["newLevel"]:
            entry["level"] = override["newLevel"]
            changed_ids.add(word_id)

    by_path: dict[Path, list[dict]] = {}
    for word_id, path in paths.items():
        by_path.setdefault(path, []).append(entries[word_id])
    for path, words in by_path.items():
        kept = [word for word in words if word["id"] not in retired_ids]
        if len(kept) != len(words):
            changed_ids.update(word["id"] for word in words if word["id"] in retired_ids)
        if any(word_id in changed_ids for word_id, source_path in paths.items() if source_path == path):
            path.write_text(json.dumps(kept, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")

    if changed_ids:
        print("Applied reviewed catalogue changes: " + ", ".join(sorted(changed_ids)))
    else:
        print("Reviewed catalogue changes are already applied.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="apply the reviewed changes")
    parser.add_argument("--write-baseline", action="store_true", help="create the initial baseline")
    args = parser.parse_args()
    if args.write and args.write_baseline:
        raise SystemExit("Use --write-baseline before --write, not together")

    entries, paths = catalogue()
    if args.write_baseline:
        if BASELINE_PATH.exists():
            raise SystemExit(f"Baseline already exists: {BASELINE_PATH}")
        baseline = {word_id: entries[word_id]["level"] for word_id in sorted(entries)}
        BASELINE_PATH.write_text(
            json.dumps({"schemaVersion": 1, "levels": baseline}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote baseline for {len(baseline)} entries to {BASELINE_PATH}")
        return

    ledger = load_ledger()
    if args.write:
        write_catalogue(entries, paths, ledger)
        entries, _ = catalogue()

    errors = validate(entries, ledger, load_baseline())
    if errors:
        raise SystemExit("CEFR ledger validation failed:\n- " + "\n- ".join(errors))
    print(
        f"Validated CEFR baseline and {len(ledger['levelOverrides'])} reviewed level overrides; "
        f"{len(ledger['retirements'])} documented retirements."
    )


if __name__ == "__main__":
    main()
