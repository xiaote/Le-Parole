#!/usr/bin/env python3
"""Exercise and review the app's live Gemini conjugation-card generator.

The app creates these cards at review time, so there is no static collection to
validate. This audit renders the current batch-generation prompt from the Swift
source, submits a broad tense/pronoun fixture set, and asks a separate Gemini
pass to check each returned card for grammar and naturalness.

The API key is read only from a local database or GEMINI_API_KEY. It is never
written to the report or printed.

Example:
    python3 tools/audit_conjugation_cards.py \
      --database /path/to/LeParoleBackup.sqlite
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any

import requests


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "Le Parole" / "Data"
SERVICE = ROOT / "Le Parole" / "Services" / "AppleIntelligenceService.swift"
REPORT_PATH = ROOT / "tools" / "audits" / "conjugation_card_audit.json"
MODEL = "gemini-3.1-flash-lite"
ENDPOINT = f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent"
ALL_PRONOUNS = ["io", "tu", "lui/lei", "noi", "voi", "loro"]


def load_api_key(database: Path | None) -> str:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key and database:
        with sqlite3.connect(database) as connection:
            row = connection.execute(
                "SELECT geminiApiKey FROM userSettings "
                "WHERE length(trim(geminiApiKey)) > 0 LIMIT 1"
            ).fetchone()
        key = (row[0] if row else "").strip()
    if not key:
        raise SystemExit("No Gemini API key found in GEMINI_API_KEY or the selected database.")
    return key


def load_verbs() -> dict[str, str]:
    verbs: dict[str, str] = {}
    for path in sorted(DATA.glob("words_*.json")):
        for word in json.loads(path.read_text(encoding="utf-8")):
            if word.get("partOfSpeech") == "verb":
                verbs[word["italian"].casefold()] = word.get("english", "")
    return verbs


def build_cases(verbs: dict[str, str]) -> list[dict[str, str]]:
    """Cover all app tenses, then focus heavily on high-risk forms."""
    cases: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()

    def add(verb: str, tense: str, pronoun: str, suite: str) -> None:
        key = (verb, tense, pronoun)
        if key in seen:
            return
        if verb.casefold() not in verbs:
            raise ValueError(f"Audit verb is absent from the current catalogue: {verb}")
        seen.add(key)
        cases.append({
            "id": f"case-{len(cases) + 1:03d}",
            "verb": verb,
            "englishMeaning": verbs[verb.casefold()],
            "tense": tense,
            "pronoun": pronoun,
            "suite": suite,
        })

    # One complete app-valid pronoun sweep for every tense. Imperative excludes
    # io, exactly as StudySessionViewModel does.
    representative = {
        "presente": "mangiare",
        "passato prossimo": "andare",
        "imperfetto": "capire",
        "presente progressivo": "fare",
        "futuro semplice": "venire",
        "imperativo": "dire",
        "condizionale presente": "volere",
        "condizionale passato": "andare",
        "congiuntivo presente": "essere",
        "congiuntivo imperfetto": "fare",
    }
    for tense, verb in representative.items():
        pronouns = [p for p in ALL_PRONOUNS if not (tense == "imperativo" and p == "io")]
        for pronoun in pronouns:
            add(verb, tense, pronoun, "all_tenses_pronouns")

    # The conjugation levels introduce both subjunctives last, so run a much
    # broader cross-section of regular endings, spelling changes, irregulars,
    # reflexives, inverted verbs, and impersonals for them.
    subjunctive_verbs = [
        "parlare", "leggere", "dormire", "capire", "pagare", "mangiare",
        "essere", "avere", "andare", "fare", "dare", "stare", "sapere",
        "dire", "bere", "venire", "tenere", "volere", "potere", "dovere",
        "uscire", "rimanere", "svegliarsi", "accorgersi", "piacere", "mancare",
        "piovere",
    ]
    for index, verb in enumerate(subjunctive_verbs):
        pronoun = "lui/lei" if verb == "piovere" else ALL_PRONOUNS[index % len(ALL_PRONOUNS)]
        add(verb, "congiuntivo presente", pronoun, "subjunctive_stress")
        add(verb, "congiuntivo imperfetto", pronoun, "subjunctive_stress")

    # Compound forms have the most common answer-format and agreement failures.
    for verb in ["andare", "venire", "rimanere", "svegliarsi"]:
        for tense in ["passato prossimo", "condizionale passato"]:
            for pronoun in ["io", "tu", "noi", "voi"]:
                add(verb, tense, pronoun, "compound_gender_agreement")

    # Inverted verbs can accidentally use the requested pronoun as an indirect
    # object; impersonal verbs have a deliberately restricted pronoun range.
    for verb in ["piacere", "mancare"]:
        for tense, pronoun in [
            ("presente", "voi"), ("passato prossimo", "loro"),
            ("imperfetto", "noi"), ("futuro semplice", "tu"),
            ("condizionale presente", "lui/lei"), ("congiuntivo presente", "voi"),
        ]:
            add(verb, tense, pronoun, "inverted_verb")
    for tense in representative:
        if tense != "imperativo":
            add("piovere", tense, "lui/lei", "impersonal_verb")

    return cases


def current_app_prompt(requests_for_batch: list[dict[str, str]]) -> str:
    """Render the production batch prompt directly from the Swift source."""
    source = SERVICE.read_text(encoding="utf-8")
    method_start = source.index("static func generateBatchedConjugationChallenges")
    method = source[method_start:]
    match = re.search(
        r'let instructions = """\n(.*?)\n        """\n\s*let cleanApiKey',
        method,
        flags=re.DOTALL,
    )
    if not match:
        raise RuntimeError("Could not extract Gemini's batch prompt from AppleIntelligenceService.swift")
    template = match.group(1).replace(r"\(requests.count)", str(len(requests_for_batch)))
    before_requests, marker, _ = template.partition("        REQUESTS:\n")
    if not marker:
        raise RuntimeError("The extracted batch prompt has no REQUESTS marker")
    request_lines = "\n".join(
        f"- ID: {item['id']} | Verb: {item['verb']} (English: {item['englishMeaning']}) "
        f"| Tense: {item['tense']} | Pronoun: {item['pronoun']}"
        for item in requests_for_batch
    )
    return before_requests + marker + request_lines


def decode_json(text: str) -> Any:
    clean = text.strip()
    clean = re.sub(r"^```(?:json)?\s*", "", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\s*```$", "", clean)
    start_positions = [index for index in (clean.find("["), clean.find("{")) if index >= 0]
    if not start_positions:
        raise ValueError("Gemini response did not contain JSON")
    decoder = json.JSONDecoder()
    value, _ = decoder.raw_decode(clean[min(start_positions):])
    return value


def call_gemini(api_key: str, prompt: str, minimum_delay: float = 5.1) -> Any:
    # Matches the app's conservative twelve-requests-per-minute pacing.
    if hasattr(call_gemini, "last_call"):
        pause = minimum_delay - (time.monotonic() - call_gemini.last_call)
        if pause > 0:
            time.sleep(pause)
    response = requests.post(
        ENDPOINT,
        params={"key": api_key},
        headers={"Content-Type": "application/json"},
        json={
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        },
        timeout=120,
    )
    call_gemini.last_call = time.monotonic()
    if response.status_code != 200:
        try:
            message = response.json().get("error", {}).get("message", "Unknown API error")
        except ValueError:
            message = "Non-JSON API error"
        raise RuntimeError(f"Gemini API returned HTTP {response.status_code}: {message}")
    body = response.json()
    try:
        text = body["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError) as error:
        raise RuntimeError("Gemini returned no candidate text") from error
    return decode_json(text)


def structural_issues(request: dict[str, str], card: dict[str, Any] | None) -> list[str]:
    if not card:
        return ["missing_generated_card"]
    issues: list[str] = []
    if card.get("tense") != request["tense"]:
        issues.append("returned_tense_mismatch")
    if card.get("pronoun") != request["pronoun"]:
        issues.append("returned_pronoun_mismatch")
    sentence = str(card.get("sentence", ""))
    answer = str(card.get("answer", "")).strip()
    if "_____" not in sentence:
        issues.append("blank_missing")
    if f"({request['verb']})" not in sentence:
        issues.append("infinitive_label_mismatch")
    if not answer:
        issues.append("answer_missing")
    return issues


def reviewer_prompt(items: list[dict[str, Any]]) -> str:
    return """You are a meticulous native Italian linguist auditing AI-generated
fill-in-the-blank conjugation flashcards. Review EVERY item independently.

For each item, determine whether it is both grammatically correct and natural
Italian. Check all of the following:
1. The answer is the correct conjugation of the exact infinitive for the target
   tense and grammatical subject.
2. The answer fits the sentence and the sentence genuinely licenses that tense.
   Pay particular attention to correct triggers and sequence of tenses for both
   congiuntivo presente and congiuntivo imperfetto.
3. Compound forms use the correct auxiliary and agreement. A slash-separated
   masculine/feminine answer is valid when gender is genuinely unspecified.
4. Reflexive, inverted (piacere/mancare), impersonal, and formal imperative
   forms use the stated grammatical subject correctly.
5. The blank, infinitive label, explanation, and English translation are
   coherent; the Italian should sound natural rather than merely possible.

Return ONLY a JSON object with a `results` array. Each result must have:
`id`, `verdict` (`pass` or `fail`), `categories` (array), `reason`,
`suggestedAnswer` (or null), and `suggestedSentence` (or null).

Items:
""" + json.dumps(items, ensure_ascii=False, indent=2)


def chunks(items: list[dict[str, str]], size: int) -> list[list[dict[str, str]]]:
    return [items[index:index + size] for index in range(0, len(items), size)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True, help="SQLite backup containing your Gemini key")
    parser.add_argument("--batch-size", type=int, default=6, help="cards per generate/review request (default: 6)")
    parser.add_argument("--max-cases", type=int, help="limit cases for a smoke test or resumable segment")
    parser.add_argument("--case-offset", type=int, default=0, help="skip this many cases before applying --max-cases")
    parser.add_argument("--case-ids", help="comma-separated fixture IDs to run, for example case-061,case-083")
    parser.add_argument("--report", type=Path, default=REPORT_PATH, help="where to write the JSON audit report")
    args = parser.parse_args()
    if args.batch_size < 1:
        raise SystemExit("--batch-size must be positive")
    if not args.database.is_file():
        raise SystemExit(f"Database does not exist: {args.database}")

    api_key = load_api_key(args.database)
    all_cases = build_cases(load_verbs())
    if args.case_ids:
        requested_ids = [case_id.strip() for case_id in args.case_ids.split(",") if case_id.strip()]
        cases_by_id = {case["id"]: case for case in all_cases}
        missing_ids = [case_id for case_id in requested_ids if case_id not in cases_by_id]
        if missing_ids:
            raise SystemExit("Unknown fixture IDs: " + ", ".join(missing_ids))
        cases = [cases_by_id[case_id] for case_id in requested_ids]
    else:
        cases = all_cases
    if args.case_offset < 0:
        raise SystemExit("--case-offset cannot be negative")
    if not args.case_ids:
        cases = cases[args.case_offset:]
        if args.max_cases:
            cases = cases[:args.max_cases]
    print(f"Auditing {len(cases)} dynamic cards across {len(set(case['tense'] for case in cases))} tenses.")

    all_results: list[dict[str, Any]] = []
    all_review_results: list[dict[str, Any]] = []
    failed_batches: list[dict[str, Any]] = []
    batches = chunks(cases, args.batch_size)
    for batch_number, batch in enumerate(batches, start=1):
        print(f"Generating and reviewing batch {batch_number}/{len(batches)}...", flush=True)
        try:
            generated = call_gemini(api_key, current_app_prompt(batch))
            if not isinstance(generated, list):
                raise ValueError("Generator response was not a JSON array")
            generated_by_id = {item.get("id"): item for item in generated if isinstance(item, dict)}
            records = []
            for request in batch:
                card = generated_by_id.get(request["id"])
                record = {"request": request, "card": card, "structuralIssues": structural_issues(request, card)}
                records.append(record)
                all_results.append(record)
            review_input = [
                {"id": record["request"]["id"], **record["request"], "generatedCard": record["card"]}
                for record in records
            ]
            review = call_gemini(api_key, reviewer_prompt(review_input))
            review_items = review.get("results") if isinstance(review, dict) else None
            if not isinstance(review_items, list):
                raise ValueError("Reviewer response did not contain a results array")
            all_review_results.extend(item for item in review_items if isinstance(item, dict))
        except Exception as error:  # preserve successful batches for diagnosis
            failed_batches.append({"batch": batch_number, "caseIds": [case["id"] for case in batch], "error": str(error)})
            print(f"  Batch {batch_number} failed: {error}", file=sys.stderr, flush=True)

    reviews_by_id = {item.get("id"): item for item in all_review_results}
    for record in all_results:
        record["review"] = reviews_by_id.get(record["request"]["id"])
    failed_cards = [
        record for record in all_results
        if record["structuralIssues"] or record.get("review", {}).get("verdict") == "fail"
    ]
    category_counts: Counter[str] = Counter()
    for record in failed_cards:
        category_counts.update(record["structuralIssues"])
        category_counts.update(record.get("review", {}).get("categories", []))
    report = {
        "model": MODEL,
        "scope": {
            "generatedCards": len(all_results),
            "requestedCards": len(cases),
            "tenses": sorted({case["tense"] for case in cases}),
            "subjunctiveCards": sum(case["tense"].startswith("congiuntivo") for case in cases),
        },
        "summary": {
            "failedCards": len(failed_cards),
            "failedBatches": len(failed_batches),
            "issueCategories": dict(sorted(category_counts.items())),
        },
        "failedBatches": failed_batches,
        "failedCards": failed_cards,
        "allCards": all_results,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"Completed: {len(all_results)}/{len(cases)} cards generated; "
        f"{len(failed_cards)} flagged. Report: {args.report}"
    )
    if failed_batches:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
