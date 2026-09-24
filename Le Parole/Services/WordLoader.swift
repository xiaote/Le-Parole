import Foundation
import GRDB

/// One entry of the bundled `Data/words.json` catalogue.
nonisolated struct CatalogueEntry: Decodable, Sendable {
    let id: String
    let italian: String
    let english: String
    let alternatives: [String]?
    let level: String
    let frequencyRank: Int
    let inflections: String?
    let partOfSpeech: String?
}

/// Imports the bundled catalogue into the database. The imported version is
/// stored in `PRAGMA user_version`, so it travels with backups.
enum WordLoader {
    /// Bump whenever `words.json` changes.
    nonisolated static let catalogueVersion = 23

    /// Makes sure the bundled catalogue is imported. If a catalogue is already
    /// present, a pending refresh runs in the background and this returns at
    /// once; a database without words waits for the import.
    /// - Returns: Whether a usable catalogue is available.
    @discardableResult
    static func prepare() async -> Bool {
        let db = DatabaseService.shared.db
        let state = try? await db.read { db in
            (version: try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0,
             hasWords: try Word.fetchCount(db) > 0)
        }
        let hasWords = state?.hasWords ?? false
        guard !hasWords || (state?.version ?? 0) < catalogueVersion else { return true }

        let refresh = Task.detached(priority: hasWords ? .utility : .userInitiated) {
            do {
                let entries = try bundledEntries()
                try await db.write { db in try importCatalogue(entries, into: db) }
                return true
            } catch {
                print("WordLoader error: \(error)")
                return false
            }
        }
        return hasWords ? true : await refresh.value
    }

    nonisolated static func bundledEntries() throws -> [CatalogueEntry] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([CatalogueEntry].self, from: Data(contentsOf: url))
    }

    /// Upserts `entries` and creates missing progress rows in the current
    /// transaction. User-created words are never touched, and a new entry is
    /// skipped when its headword belongs to a retired bundled word still kept
    /// in the database for its learning history.
    nonisolated static func importCatalogue(
        _ entries: [CatalogueEntry],
        into db: Database,
        version: Int = catalogueVersion,
        now: Date = .now
    ) throws {
        try db.execute(sql: """
            CREATE TEMP TABLE catalogueImport (
                wordId TEXT PRIMARY KEY NOT NULL,
                italian TEXT NOT NULL,
                english TEXT NOT NULL,
                alternatives TEXT NOT NULL,
                level TEXT NOT NULL,
                frequencyRank INTEGER NOT NULL,
                inflections TEXT,
                partOfSpeech TEXT
            )
            """)
        let insert = try db.makeStatement(sql: "INSERT INTO catalogueImport VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
        for entry in entries {
            try insert.execute(arguments: [
                entry.id, entry.italian, entry.english,
                Word.encodeAlternatives(entry.alternatives ?? []),
                entry.level, entry.frequencyRank, entry.inflections, entry.partOfSpeech,
            ])
        }

        try db.execute(sql: """
            DELETE FROM catalogueImport
            WHERE wordId NOT IN (SELECT wordId FROM words)
              AND swiftLowercaseString(italian) IN (
                  SELECT swiftLowercaseString(italian) FROM words
                  WHERE NOT isUserCreated
                    AND wordId NOT IN (SELECT wordId FROM catalogueImport)
              );

            INSERT INTO words (wordId, italian, english, alternatives, level, frequencyRank, isUserCreated, inflections, partOfSpeech)
            SELECT wordId, italian, english, alternatives, level, frequencyRank, 0, inflections, partOfSpeech
            FROM catalogueImport WHERE true
            ON CONFLICT(wordId) DO UPDATE SET
                italian = excluded.italian,
                english = excluded.english,
                alternatives = excluded.alternatives,
                level = excluded.level,
                frequencyRank = excluded.frequencyRank,
                inflections = excluded.inflections,
                partOfSpeech = excluded.partOfSpeech
            WHERE NOT words.isUserCreated;
            """)
        try db.execute(sql: """
            INSERT INTO userWords (wordId, stage, easeFactor, interval, repetitions, nextReviewDate, totalCorrect, totalAttempts)
            SELECT i.wordId, 'new', 2.5, 1, 0, ?, 0, 0
            FROM catalogueImport i
            JOIN words w ON w.wordId = i.wordId AND NOT w.isUserCreated
            WHERE NOT EXISTS (SELECT 1 FROM userWords uw WHERE uw.wordId = i.wordId)
            """, arguments: [now.timeIntervalSince1970])
        try db.execute(sql: "DROP TABLE temp.catalogueImport")
        try db.execute(sql: "PRAGMA user_version = \(version)")
    }
}
