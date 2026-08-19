# Le Parole

Le Parole is an iPhone and iPad app for learning Italian vocabulary and verb conjugations. It pairs an SM-2 spaced-repetition study queue with native pronunciation, progress tracking, and optional AI-generated conjugation exercises.

## Highlights

- Learn from bundled Italian vocabulary across CEFR levels A1–C1, or add your own words.
- Review recognition and production cards using SM-2 scheduling.
- Practice verb conjugations in contextual fill-in-the-blank sentences.
- Track progress, mastery, and conjugation performance.
- Back up and restore local learning data from Settings.

Study data is stored locally in a SQLite database via [GRDB](https://github.com/groue/GRDB.swift). The app seeds that database from the vocabulary JSON files in `Le Parole/Data/`.

## Requirements

- Xcode with the iOS 26.5 SDK
- iOS 26.5 or later

## Run locally

1. Clone this repository.
2. Open `Le Parole.xcodeproj` in Xcode.
3. Allow Xcode to resolve the Swift Package Manager dependencies.
4. Select the **Le Parole** scheme and an iPhone or iPad simulator/device, then press `Cmd+R`.

## AI conjugation exercises

Conjugation prompts can be generated with Apple Intelligence on supported devices or with Google Gemini. To use Gemini, add your API key in the app’s Settings screen; never commit keys to the repository.

Learning data remains on device. When Gemini is enabled, requests to generate conjugation exercises are sent to Google Gemini. Database backups can contain learning data and configured settings, so store them securely.

## Intellectual property and license

Copyright © 2026 xiaote. All rights reserved. See [LICENSE.md](LICENSE.md) for the full terms.

This repository is **not** open source. No license is granted to use, copy, modify, distribute, sublicense, or create derivative works from project materials without the copyright holder’s prior written permission. Third-party components remain subject to their own licenses.
