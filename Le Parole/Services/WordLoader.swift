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
    /// Debug-only Xcode launch argument for deliberately exercising the full
    /// catalogue import. Normal Debug launches use the same version gate as
    /// Release builds, avoiding a needless rewrite of every bundled word.
    private static let forceRefreshLaunchArgument = "-refresh-word-catalogue"

    private static let fileNames = [
        "words_a1", "words_a2", "words_b1", "words_b2", "words_c1",
        "words_more_a2b1", "words_more_b2", "words_more_c1",
        "words_a1_complete", "words_a2_complete",
        "words_community",
    ]

    static func loadIfNeeded() async {
        let storedVersion = UserDefaults.standard.integer(forKey: "wordDataVersion")
        #if DEBUG
        let forceRefresh = ProcessInfo.processInfo.arguments.contains(forceRefreshLaunchArgument)
        #else
        let forceRefresh = false
        #endif
        let hasCatalogue = await hasCatalogue()
        guard forceRefresh || storedVersion < dataVersion || !hasCatalogue else { return }

        var seenIds     = Set<String>()
        var seenItalian = Set<String>()

        let db = DatabaseService.shared.db

        do {
            let existingWords = try await db.read { db in try Word.fetchAll(db) }
            var existingById = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.wordId, $0) })
            var existingItalian = Set(existingWords.filter { !$0.isUserCreated }.map { $0.italian.lowercased() })

            let existingUserWordIds = try await db.read { db in
                try String.fetchAll(db, sql: "SELECT wordId FROM userWords")
            }
            var existingUserWordIdSet = Set(existingUserWordIds)

            for name in fileNames {
                guard
                    let url = Bundle.main.url(forResource: name, withExtension: "json"),
                    let data = try? Data(contentsOf: url),
                    let entries = try? JSONDecoder().decode([WordEntry].self, from: data)
                else { continue }

                let fileEntries = entries.filter { entry in
                    let italian = entry.italian.lowercased()
                    guard !seenIds.contains(entry.id) && !seenItalian.contains(italian) else { return false }
                    seenIds.insert(entry.id)
                    seenItalian.insert(italian)
                    return true
                }
                guard !fileEntries.isEmpty else { continue }

                try await db.write { db in
                    for entry in fileEntries {
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
                                existingUserWordIdSet.insert(entry.id)
                            }
                            existingById[entry.id] = updated
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
                                existingUserWordIdSet.insert(entry.id)
                            }
                            existingById[entry.id] = word
                            existingItalian.insert(entry.italian.lowercased())
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

    /// A version preference can outlive a restored or recreated SQLite file.
    /// Treat an empty catalogue as needing import even when the preference says
    /// the bundled data has already been loaded.
    static func hasCatalogue() async -> Bool {
        do {
            return try await DatabaseService.shared.db.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words") ?? 0) > 0
            }
        } catch {
            return false
        }
    }

    static func ensureSettings() async {
        let db = DatabaseService.shared.db
        do {
            let count = try await db.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userSettings") ?? 0
            }
            if count == 0 {
                try await db.write { db in
                    var settings = UserSettings()
                    try settings.insert(db)
                }
            }
        } catch {
            print("ensureSettings error: \(error)")
        }
    }
}
