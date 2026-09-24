import Foundation
import GRDB
import Testing
@testable import Le_Parole

@Suite("WordLoader")
struct WordLoaderTests {
    private func makeDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try DatabaseService.makeMigrator(storeLegacyGeminiKey: { _ in }).migrate(queue)
        return queue
    }

    private func entry(_ id: String, _ italian: String, _ english: String, rank: Int = 1) -> CatalogueEntry {
        CatalogueEntry(
            id: id, italian: italian, english: english, alternatives: ["alt"],
            level: "A1", frequencyRank: rank, inflections: nil, partOfSpeech: "noun"
        )
    }

    @Test func importPreservesUserWordsAndHistory() throws {
        let queue = try makeDatabase()
        try queue.write { db in
            // A user-created word whose id collides with a bundled entry.
            try Word(wordId: "u1", italian: "mio", english: "mine", level: "A1", frequencyRank: 0, isUserCreated: true).insert(db)
            // A retired bundled word kept for its learning history.
            try Word(wordId: "retired", italian: "Claro", english: "clear", level: "A1", frequencyRank: 9).insert(db)
            var progress = UserWord(word: Word(wordId: "retired", italian: "Claro", english: "clear", level: "A1", frequencyRank: 9))
            progress.totalAttempts = 4
            try progress.insert(db)

            try WordLoader.importCatalogue([
                entry("1", "casa", "house"),
                entry("u1", "bundled", "bundled"),
                entry("new", "claro", "clear"),
            ], into: db, version: 5)
        }

        try queue.read { db in
            #expect(try Int.fetchOne(db, sql: "PRAGMA user_version") == 5)

            let user = try Word.fetchOne(db, key: "u1")
            #expect(user?.italian == "mio")
            #expect(user?.isUserCreated == true)

            #expect(try Word.fetchOne(db, key: "new") == nil)
            #expect(try Word.fetchOne(db, key: "retired") != nil)

            let casa = try Word.fetchOne(db, key: "1")
            #expect(casa?.alternatives == ["alt"])
            #expect(casa?.isUserCreated == false)

            let progress = try String.fetchAll(db, sql: "SELECT wordId FROM userWords ORDER BY wordId")
            #expect(progress == ["1", "retired"])
        }
    }

    @Test func reimportUpdatesBundledWordsWithoutResettingProgress() throws {
        let queue = try makeDatabase()
        try queue.write { db in
            try WordLoader.importCatalogue([entry("1", "casa", "house")], into: db)
            try db.execute(sql: "UPDATE userWords SET totalAttempts = 3, stage = 'production' WHERE wordId = '1'")
            try WordLoader.importCatalogue([entry("1", "casa", "home", rank: 2)], into: db)
        }
        try queue.read { db in
            let casa = try Word.fetchOne(db, key: "1")
            #expect(casa?.english == "home")
            #expect(casa?.frequencyRank == 2)
            let rows = try Row.fetchAll(db, sql: "SELECT stage, totalAttempts FROM userWords")
            #expect(rows.count == 1)
            #expect(rows.first?["stage"] == "production")
            #expect(rows.first?["totalAttempts"] == 3)
        }
    }

    @Test func coldImportOfBundledCatalogue() throws {
        let clock = ContinuousClock()
        var entries: [CatalogueEntry] = []
        let decode = try clock.measure { entries = try WordLoader.bundledEntries() }
        #expect(entries.count == 14_184)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeParoleImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = try DatabaseQueue(path: directory.appendingPathComponent("db.sqlite").path)
        try DatabaseService.makeMigrator(storeLegacyGeminiKey: { _ in }).migrate(queue)

        let firstImport = try clock.measure {
            try queue.write { db in try WordLoader.importCatalogue(entries, into: db) }
        }
        let reimport = try clock.measure {
            try queue.write { db in try WordLoader.importCatalogue(entries, into: db) }
        }
        print("Catalogue timing: decode \(decode), first import \(firstImport), re-import \(reimport)")

        let counts = try queue.read { db in
            (try Word.fetchCount(db), try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords"))
        }
        #expect(counts.0 == 14_184)
        #expect(counts.1 == 14_184)
    }
}
