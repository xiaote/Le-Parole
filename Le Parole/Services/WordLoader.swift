import Foundation
import GRDB

private struct WordEntry: Decodable, Sendable {
    let id: String
    let italian: String
    let english: String
    let alternatives: [String]?
    let level: String
    let frequencyRank: Int
    let inflections: String?
    let partOfSpeech: String?
}

enum WordLoader {
    // v22 adds reviewed CEFR overrides and merges two retired spelling cards
    // without losing their existing learning history (migration v26).
    static let dataVersion = 22

    private static let fileNames = [
        "words_a1", "words_a2", "words_b1", "words_b2", "words_c1",
        "words_more_a2b1", "words_more_b2", "words_more_c1",
        "words_a1_complete", "words_a2_complete",
        "words_community",
    ]

    static func loadIfNeeded() async {
        let storedVersion = UserDefaults.standard.integer(forKey: "wordDataVersion")
        #if !DEBUG
        guard storedVersion < dataVersion else { return }
        #endif

        var allEntries: [WordEntry] = []
        for name in fileNames {
            guard
                let url = Bundle.main.url(forResource: name, withExtension: "json"),
                let data = try? Data(contentsOf: url),
                let entries = try? JSONDecoder().decode([WordEntry].self, from: data)
            else { continue }
            allEntries += entries
        }

        // Deduplicate across files before touching the DB.
        // existingItalian (built below) only reflects words already persisted,
        // so without this step a word present in two JSON files under different IDs
        // would survive the guard inside the write block and produce duplicate rows.
        // Earlier files win (fileNames order determines priority).
        var seenIds     = Set<String>()
        var seenItalian = Set<String>()
        allEntries = allEntries.filter { entry in
            let italian = entry.italian.lowercased()
            guard !seenIds.contains(entry.id) && !seenItalian.contains(italian) else { return false }
            seenIds.insert(entry.id)
            seenItalian.insert(italian)
            return true
        }

        let db = DatabaseService.shared.db

        do {
            let existingWords = try await db.read { db in try Word.fetchAll(db) }
            let existingById = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.wordId, $0) })
            let existingItalian = Set(existingWords.filter { !$0.isUserCreated }.map { $0.italian.lowercased() })

            let existingUserWordIds = try await db.read { db in
                try String.fetchAll(db, sql: "SELECT wordId FROM userWords")
            }
            let existingUserWordIdSet = Set(existingUserWordIds)

            try await db.write { [allEntries] db in
                // Never delete bundled words during a catalogue refresh. A word
                // may have a userWords record whose review history must survive
                // a source-data rename or correction. Dedicated migrations must
                // remap any retired IDs before removal instead.

                for entry in allEntries {
                    if let existing = existingById[entry.id] {
                        guard !existing.isUserCreated else { continue }
                        var updated = existing
                        updated.italian = entry.italian
                        updated.english = entry.english
                        updated.alternatives = entry.alternatives ?? []
                        updated.level = entry.level
                        updated.frequencyRank = entry.frequencyRank
                        updated.inflections = entry.inflections
                        updated.partOfSpeech = entry.partOfSpeech
                        try updated.update(db)

                        if !existingUserWordIdSet.contains(entry.id) {
                            var uw = UserWord(word: updated)
                            try uw.insert(db)
                        }
                    } else {
                        guard !existingItalian.contains(entry.italian.lowercased()) else { continue }

                        let word = Word(
                            wordId: entry.id,
                            italian: entry.italian,
                            english: entry.english,
                            alternatives: entry.alternatives ?? [],
                            level: entry.level,
                            frequencyRank: entry.frequencyRank,
                            inflections: entry.inflections,
                            partOfSpeech: entry.partOfSpeech
                        )
                        try word.insert(db)

                        if !existingUserWordIdSet.contains(entry.id) {
                            var uw = UserWord(word: word)
                            try uw.insert(db)
                        }
                    }
                }
            }

            // Cleanup any dummy words that were not found in the JSON dictionaries
            try await db.write { db in
                try db.execute(sql: "DELETE FROM words WHERE italian = 'dummy_migrated' AND english = 'dummy'")
            }

            UserDefaults.standard.set(dataVersion, forKey: "wordDataVersion")
        } catch {
            print("WordLoader error: \(error)")
        }
    }

    static func ensureSettings() {
        let db = DatabaseService.shared.db
        do {
            let count = try db.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userSettings") ?? 0
            }
            if count == 0 {
                try db.write { db in
                    var settings = UserSettings()
                    try settings.insert(db)
                }
            }
        } catch {
            print("ensureSettings error: \(error)")
        }
    }
}
