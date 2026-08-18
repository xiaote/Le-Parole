# Le Parole

Le Parole is a SwiftUI app for learning Italian vocabulary and verb conjugations. It combines local word banks, SM-2 spaced repetition, native text-to-speech, and optional AI-generated conjugation prompts.

The app is offline-first for study data: vocabulary and progress are stored locally in SQLite through GRDB. AI features use either on-device Apple Intelligence when available or a user-provided Google Gemini API key saved through the app settings.

## What It Does

- Schedules vocabulary review with the SM-2 spaced-repetition algorithm.
- Introduces new bundled vocabulary by Italian usage frequency while keeping
  reviews and user-added words prioritized appropriately.
- Seeds the local database from CEFR-aligned Italian word lists from A1 through C1.
- Lets users test out of words they already know.
- Generates contextual conjugation exercises instead of static verb tables.
- Tracks daily progress, mastered words, in-progress words, and conjugation stats.
- Supports manual backup and restore of the local app database.
- Uses native pronunciation playback for Italian study prompts.

## Repository Layout

- `Le Parole.xcodeproj/` - Xcode project and Swift Package Manager dependency metadata.
- `Le Parole/` - SwiftUI app source.
- `Le Parole/Models/` - GRDB-backed domain models such as `Word`, `UserWord`, `UserSettings`, and `ConjugationStats`.
- `Le Parole/Services/` - Persistence, word loading, spaced repetition, speech, Apple Intelligence, and Gemini integration.
- `Le Parole/ViewModels/` - App state and study-session orchestration.
- `Le Parole/Views/` - SwiftUI screens and reusable UI components.
- `Le Parole/Data/` - Static JSON vocabulary data used to seed the database.
- `enrich_db.py` - Optional helper for enriching word data with Gemini.
- `validate_translations.py` - Optional helper for validating generated translation alternatives.

## Requirements

- Xcode 16 or newer.
- iOS 18 or newer, or macOS 15 or newer.
- A simulator or device supported by the selected deployment target.
- Optional: a Google Gemini API key for remote AI conjugation generation.

## Getting Started

1. Clone the repository.
2. Open `Le Parole.xcodeproj` in Xcode.
3. Let Xcode resolve Swift Package Manager dependencies.
4. Select the `Le Parole` scheme and a simulator or device.
5. Build and run with `Cmd+R`.

## AI Setup

The app can generate conjugation prompts in two ways:

- Apple Intelligence: available on supported devices and OS versions.
- Google Gemini: available when the user enters a Gemini API key in the app's Settings screen.

Do not hardcode API keys into the repository. The app stores the Gemini key in the local app database after the user enters it in Settings. The Python helper scripts read `GEMINI_API_KEY` from the shell environment:

```bash
GEMINI_API_KEY="your_key_here" python3 enrich_db.py
GEMINI_API_KEY="your_key_here" python3 validate_translations.py
```

## Sensitive Data

This repository is intended to be safe for public GitHub hosting. Generated build output, virtual environments, environment files, local Xcode state, and common local secret/config files are ignored by `.gitignore`.

Before pushing, run a quick check for accidental secrets:

```bash
rg -n -i "api[_ -]?key|token|secret|password|credential|bearer|authorization" .
```

Expected matches include code that refers to user-provided API keys, empty defaults, README instructions, and vocabulary data containing ordinary words such as "secret" or "token".

## Data And Persistence

The bundled JSON files in `Le Parole/Data/` are the source vocabulary lists. On first launch, the app seeds a local SQLite database and then stores user progress there. Backup and restore are handled from the Settings screen.

Bundled words have a single collision-free `frequencyRank`, regenerated with the
pinned Italian `wordfreq` data in `tools/requirements-vocabulary.txt`. It is a
relative frequency ordering for this catalogue, not a CEFR classification. The
KELLY Italian word list provides source-backed CEFR assignments where an exact
headword and compatible part of speech are available; unresolved senses remain
unchanged instead of being guessed. To intentionally refresh this metadata:

```bash
python3 -m pip install -r tools/requirements-vocabulary.txt
curl -L --fail --silent --show-error \
  https://ssharoff.github.io/kelly/it_m3.xls -o /tmp/it_m3.xls
python3 tools/consolidate_catalogue_duplicates.py --write
python3 tools/retire_composite_number_cards.py --write
python3 tools/rebuild_frequency_ranks.py --write
python3 tools/apply_kelly_cefr.py --source /tmp/it_m3.xls --write
python3 tools/validate_vocabulary_data.py
```

The generated reports in `tools/audits/` record the source and coverage:
`frequency_audit.json` covers ranks, while `cefr_audit.json` covers the KELLY
assignments and any cases deliberately left for manual review.

Catalogue refreshes update existing words in place and must not delete an entry
with a `userWords` record. User learning history is preserved even when a word's
translation, CEFR label, or frequency metadata is corrected.

## Notes For Contributors

- Keep generated files out of commits, especially `build/`, `DerivedData/`, and `venv/`.
- Keep user-specific Xcode files out of commits, especially `xcuserdata/`.
- Keep secrets in environment variables, app settings, Keychain, or ignored local config files.
- If you add a new dependency, commit the updated Swift Package resolution metadata when appropriate.

## License

This project is intended for personal and educational use.
