# Le Parole

Le Parole is a modern iOS/macOS application built with SwiftUI designed to help users learn Italian vocabulary and master verb conjugations. It leverages a spaced-repetition system (SM-2) for flashcards and uses on-device Apple Intelligence (or the Google Gemini API) to dynamically generate natural-language conjugation exercises!

## Features

- **Spaced Repetition System (SRS):** Employs the SM-2 algorithm to optimally schedule flashcard reviews for vocabulary retention.
- **Dynamic Conjugation Exercises:** Rather than memorizing static tables, the app dynamically generates full, contextual Italian sentences with blanks for verbs, requiring you to understand the grammar and conjugate on the fly. 
- **AI Integration:** Uses local, on-device Apple Intelligence or the Google Gemini API to generate challenging, varied, and grammatically precise conjugation exercises.
- **Comprehensive Word Banks:** Comes pre-seeded with an extensive Italian vocabulary database categorized by CEFR levels (A1 to C1).
- **Test Out Mechanism:** Quickly bypass words you already know by translating them correctly in one shot, instantly advancing them to the mastered stage.
- **Adaptive Study Sessions:** Learn at your own pace with a daily goal, and use "Learn More" to optionally introduce extra words—automatically paced so new words aren't introduced if you have a backlog of struggling cards.
- **Data Backup & Restore:** Manually export your entire database and progress to a file, and restore from backups at any time.
- **Offline First:** Vocabulary data and your learning progress are stored entirely locally using an SQLite database (via [GRDB](https://github.com/groue/GRDB.swift)).
- **Text-to-Speech:** Native iOS/macOS text-to-speech integration to hear the proper pronunciation of Italian sentences.

## Project Structure

The codebase is organized into several key directories:

- `Models/`: Contains the core data structures (e.g., `Word`, `UserWord`, `UserSettings`, `ConjugationStats`) that represent the app's domain and map directly to SQLite tables.
- `Services/`: Contains the business logic and external integrations:
  - `DatabaseService.swift`: Manages the GRDB SQLite connection, schema migrations, and local persistence.
  - `AppleIntelligenceService.swift` & `GeminiService.swift`: Handle the complex system prompts and network/on-device requests to generate conjugation flashcards.
  - `WordLoader.swift`: Responsible for parsing the raw JSON word lists, cleaning formatting, and seeding the local database.
  - `SM2.swift`: The spaced-repetition algorithm logic.
- `ViewModels/`: Includes `StudySessionViewModel`, which orchestrates the complex logic of fetching due cards, pre-fetching AI-generated sentences, progressive ordering, and handling user answers.
- `Views/`: All the SwiftUI user interface components, separated into logical views like `HomeView`, `SettingsView`, `WordBankView`, and the `StudySession/` interactive flashcard UI.
- `Data/`: Contains the static JSON files used to seed the initial vocabulary database and manage word lists.

## Getting Started

### Prerequisites

- **Xcode 16.0** or newer (required for the latest Swift features and `PBXFileSystemSynchronizedRootGroup` structure).
- **iOS 18.0+** or **macOS 15.0+** deployment target.

### Installation

1. Clone this repository and open `Le Parole.xcodeproj` in Xcode.
2. Xcode will automatically resolve the Swift Package Manager dependencies (e.g., `GRDB.swift`).
3. Select your target simulator or device and build the project (`Cmd + R`).

### Enabling AI Conjugations

By default, the app uses on-device Apple Intelligence to generate conjugation sentences (requires iOS 18.1+ / macOS 15.1+ on supported devices). 

If you do not have an Apple Intelligence capable device, or if you prefer a faster and more capable model, you can use the Google Gemini API:
1. Obtain a free API key from [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Open the **Le Parole** app and navigate to the **Settings** tab.
3. Paste your API key into the "Gemini API Key" field.
4. The app will immediately start batch-generating high-quality conjugation flashcards using Gemini!

## License

This project is intended for personal and educational use.
