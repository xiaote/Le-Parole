import Foundation
import UIKit
import GRDB

struct ConjugationReviewRecord: Sendable {
    let verb: String
    let tense: String
    let pronoun: String
}

final class DatabaseService: @unchecked Sendable {
    nonisolated static let shared = DatabaseService()

    nonisolated let db: DatabaseQueue
    private var memoryWarningObserver: Any?
    private var backgroundObserver: Any?

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dbPath = appSupport.appendingPathComponent("le_parole.sqlite").path

        do {
            try fileManager.createDirectory(
                at: appSupport,
                withIntermediateDirectories: true
            )
            var config = Configuration()
            config.foreignKeysEnabled = true
            config.prepareDatabase { db in
                // Cap cache size to 1MB (negative value specifies size in KiB)
                try db.execute(sql: "PRAGMA cache_size = -1000;")
            }
            db = try DatabaseQueue(path: dbPath, configuration: config)
            try Self.makeMigrator().migrate(db)
            setupMemoryTrimming()
        } catch {
            fatalError("DatabaseService init failed: \(error.localizedDescription)")
        }
    }

    private func setupMemoryTrimming() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.shrinkMemory()
        }

        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.shrinkMemory()
        }
    }

    func shrinkMemory() {
        Task.detached { [db] in
            try? db.write { database in
                try database.execute(sql: "PRAGMA shrink_memory;")
            }
        }
    }

    // MARK: - Backup and restore

    func exportDatabase() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeParoleBackup_\(formatter.string(from: Date())).sqlite")

        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
        // VACUUM INTO writes a compact copy without free pages, so deleted
        // content (such as the Gemini key older versions kept in userSettings)
        // cannot travel with a backup.
        try db.vacuum(into: exportURL.path)
        return exportURL
    }

    /// Restores a backup into the live connection. The picked file is copied
    /// and validated first, so an unusable file leaves current progress intact.
    nonisolated func importDatabase(from url: URL) throws {
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("LeParoleRestore_\(UUID().uuidString).sqlite")
        defer { try? fileManager.removeItem(at: tempURL) }

        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: url, to: tempURL)
        }

        let backupSource = try Self.openValidatedBackup(atPath: tempURL.path)
        try backupSource.backup(to: db)
        try backupSource.close()

        // The backup may predate the current schema.
        try Self.makeMigrator().migrate(db)

        // The backup API bypasses transaction observers, so tell active
        // ValueObservations that everything may have changed.
        try db.write { db in
            try db.notifyChanges(in: .fullDatabase)
        }
    }

    /// Opens a backup read-only and checks it is a Le Parole database that
    /// has reached `oldestSupportedMigration`.
    nonisolated static func openValidatedBackup(atPath path: String) throws -> DatabaseQueue {
        let requiredTables = ["words", "userWords", "grdb_migrations"]
        let backup: DatabaseQueue
        let missingTables: [String]
        let isSupported: Bool
        do {
            var config = Configuration()
            config.readonly = true
            backup = try DatabaseQueue(path: path, configuration: config)
            (missingTables, isSupported) = try backup.read { db in
                let missing = try requiredTables.filter { try !db.tableExists($0) }
                guard missing.isEmpty else { return (missing, false) }
                let supported = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS (SELECT 1 FROM grdb_migrations WHERE identifier = ?)",
                    arguments: [oldestSupportedMigration]
                ) ?? false
                return (missing, supported)
            }
        } catch {
            throw RestoreError.notADatabase
        }
        guard missingTables.isEmpty else {
            throw RestoreError.missingTables(missingTables)
        }
        guard isSupported else {
            throw RestoreError.unsupportedVersion
        }
        return backup
    }

    nonisolated enum RestoreError: LocalizedError {
        case notADatabase
        case missingTables([String])
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .notADatabase:
                "The selected file is not a Le Parole backup. Your current progress was not changed."
            case .missingTables(let tables):
                "The selected file is not a Le Parole backup (missing \(tables.joined(separator: ", "))). Your current progress was not changed."
            case .unsupportedVersion:
                "This backup was made by a version of Le Parole from before August 2026, which can no longer be restored. Your current progress was not changed."
            }
        }
    }

    // MARK: - Migrations

    /// Every database, fresh or restored, must have applied this migration.
    /// Identifiers of removed, older migrations may remain in
    /// `grdb_migrations`; GRDB ignores unknown applied identifiers.
    nonisolated static let oldestSupportedMigration = "v27_current_schema"

    /// - Parameter storeLegacyGeminiKey: Receives a Gemini key found in the
    ///   retired `userSettings.geminiApiKey` column. Tests inject a stub.
    nonisolated static func makeMigrator(
        storeLegacyGeminiKey: @escaping @Sendable (String) -> Void = moveGeminiKeyToKeychain
    ) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration(oldestSupportedMigration) { db in
            if try !db.tableExists("words") {
                try createCurrentSchema(db)
            }
        }

        migrator.registerMigration("v28_performance_indexes") { db in
            try db.create(index: "idx_uw_stage_review", on: "userWords", columns: ["stage", "nextReviewDate"], ifNotExists: true)
            try db.create(index: "idx_uw_learned_date", on: "userWords", columns: ["learnedDate"], ifNotExists: true)
            try db.create(index: "idx_uw_last_wrong_date", on: "userWords", columns: ["lastWrongDate"], ifNotExists: true)
            try db.create(index: "idx_uw_last_review", on: "userWords", columns: ["lastReviewDate"], ifNotExists: true)
        }

        migrator.registerMigration("v29_index_cleanup") { db in
            // Old installs could hold several progress rows for one word. Keep
            // the most practised (oldest on ties) so wordId can become unique.
            try db.execute(sql: """
                DELETE FROM userWords
                WHERE EXISTS (
                    SELECT 1 FROM userWords keep
                    WHERE keep.wordId = userWords.wordId
                      AND (keep.totalAttempts > userWords.totalAttempts
                           OR (keep.totalAttempts = userWords.totalAttempts AND keep.id < userWords.id))
                )
                """)
            // idx_uw_stage is a prefix of idx_uw_stage_review.
            try db.execute(sql: "DROP INDEX IF EXISTS idx_uw_stage")
            try db.execute(sql: "DROP INDEX IF EXISTS idx_uw_word")
            try db.create(index: "idx_uw_word_unique", on: "userWords", columns: ["wordId"], unique: true, ifNotExists: true)
        }

        migrator.registerMigration("v30_drop_legacy_columns") { db in
            let settingsColumns = try Set(db.columns(in: "userSettings").map(\.name))
            if settingsColumns.contains("geminiApiKey"),
               let legacyKey = try String.fetchOne(
                   db,
                   sql: "SELECT geminiApiKey FROM userSettings WHERE geminiApiKey != '' LIMIT 1"
               ) {
                storeLegacyGeminiKey(legacyKey)
            }
            try dropColumns(["geminiApiKey", "extraConjugationCards"], ifIn: settingsColumns, from: "userSettings", db)

            // Per-day stage snapshots, superseded by the per-answer counters.
            let activityColumns = try Set(db.columns(in: "dailyActivity").map(\.name))
            try dropColumns(["recognition", "production", "mastered", "hasDetailedMetrics"], ifIn: activityColumns, from: "dailyActivity", db)

            if try UserSettings.fetchCount(db) == 0 {
                var settings = UserSettings()
                try settings.insert(db)
            }
        }
        return migrator
    }

    nonisolated private static func dropColumns(_ columns: [String], ifIn existing: Set<String>, from table: String, _ db: Database) throws {
        let present = columns.filter(existing.contains)
        guard !present.isEmpty else { return }
        try db.alter(table: table) { t in
            for column in present { t.drop(column: column) }
        }
    }

    /// Keeps a key already in the Keychain; otherwise stores the legacy one.
    nonisolated static func moveGeminiKeyToKeychain(_ legacyKey: String) {
        guard (KeychainStore.get(KeychainStore.geminiApiKey) ?? "").isEmpty else { return }
        if !KeychainStore.set(legacyKey, for: KeychainStore.geminiApiKey) {
            print("Could not move the legacy Gemini key to the Keychain")
        }
    }

    nonisolated private static func createCurrentSchema(_ db: Database) throws {
        try db.create(table: "words") { t in
            t.primaryKey("wordId", .text)
            t.column("italian", .text).notNull()
            t.column("english", .text).notNull()
            t.column("alternatives", .text).notNull().defaults(to: "[]")
            t.column("level", .text).notNull()
            t.column("frequencyRank", .integer).notNull()
            t.column("isUserCreated", .boolean).notNull().defaults(to: false)
            t.column("inflections", .text)
            t.column("partOfSpeech", .text)
        }

        try db.create(table: "userWords") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("wordId", .text).notNull().references("words", onDelete: .cascade)
            t.column("stage", .text).notNull().defaults(to: "new")
            t.column("easeFactor", .double).notNull().defaults(to: 2.5)
            t.column("interval", .integer).notNull().defaults(to: 1)
            t.column("repetitions", .integer).notNull().defaults(to: 0)
            t.column("nextReviewDate", .double).notNull()
            t.column("lastReviewDate", .double)
            t.column("learnedDate", .double)
            t.column("lastWrongDate", .double)
            t.column("totalCorrect", .integer).notNull().defaults(to: 0)
            t.column("totalAttempts", .integer).notNull().defaults(to: 0)
        }

        // Defaults live in `UserSettings.init`; v30 inserts the single row.
        try db.create(table: "userSettings") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("dailyPracticeGoal", .integer).notNull()
            t.column("dailyNewWordGoal", .integer).notNull()
            t.column("autoPlayPronunciation", .boolean).notNull()
            t.column("conjugationLevel", .integer).notNull()
            t.column("targetLevel", .text).notNull()
        }

        try db.create(table: "dailyActivity") { t in
            t.primaryKey("date", .text)
            t.column("reviewAttempts", .integer).notNull().defaults(to: 0)
            t.column("correctAnswers", .integer).notNull().defaults(to: 0)
            t.column("wordsIntroduced", .integer).notNull().defaults(to: 0)
            t.column("movedToProduction", .integer).notNull().defaults(to: 0)
            t.column("movedToMastered", .integer).notNull().defaults(to: 0)
        }

        try db.create(table: "tenseStats") { t in
            t.primaryKey("tense", .text)
            t.column("score", .double).notNull().defaults(to: 0.5)
            t.column("attempts", .integer).notNull().defaults(to: 0)
        }

        try db.create(table: "conjugationStats") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("verb", .text).notNull()
            t.column("tense", .text).notNull()
            t.column("pronoun", .text).notNull()
            t.column("score", .double).notNull().defaults(to: 0.5)
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.uniqueKey(["verb", "tense", "pronoun"])
        }

        try db.create(index: "idx_uw_review", on: "userWords", columns: ["nextReviewDate"])
        try db.create(index: "idx_uw_word_unique", on: "userWords", columns: ["wordId"], unique: true)
        try db.create(index: "idx_uw_stage_review", on: "userWords", columns: ["stage", "nextReviewDate"])
        try db.create(index: "idx_uw_learned_date", on: "userWords", columns: ["learnedDate"])
        try db.create(index: "idx_uw_last_wrong_date", on: "userWords", columns: ["lastWrongDate"])
        try db.create(index: "idx_uw_last_review", on: "userWords", columns: ["lastReviewDate"])
        try db.create(index: "idx_w_italian", on: "words", columns: ["italian"])
        try db.create(index: "idx_w_level_freq", on: "words", columns: ["level", "frequencyRank"])
    }

    // MARK: - Fetch helpers

    nonisolated static let userWordSelectSQL = """
        SELECT uw.id, uw.wordId, uw.stage, uw.easeFactor, uw.interval, uw.repetitions,
               uw.nextReviewDate, uw.lastReviewDate, uw.learnedDate, uw.lastWrongDate,
               uw.totalCorrect, uw.totalAttempts,
               w.italian, w.english, w.alternatives, w.level, w.frequencyRank, w.isUserCreated, w.inflections, w.partOfSpeech
        FROM userWords uw
        JOIN words w ON uw.wordId = w.wordId
        """

    /// Words not yet introduced: user-created first (in CEFR order), then by frequency.
    nonisolated static func fetchNewWords(_ db: Database, limit: Int) throws -> [UserWord] {
        try UserWord.fetchAll(db, sql: """
            \(userWordSelectSQL)
            WHERE uw.stage = 'new'
            ORDER BY w.isUserCreated DESC,
                     CASE WHEN w.isUserCreated THEN \(Word.cefrOrderSQL) ELSE 0 END,
                     w.frequencyRank,
                     w.wordId
            LIMIT ?
            """, arguments: [limit])
    }

    // MARK: - Review persistence

    /// Upsert clause shared by tense and conjugation scores: an exponentially
    /// weighted moving average of correctness, seeded by the first answer.
    nonisolated private static let scoreUpsertSQL = """
        score = CASE WHEN attempts = 0 THEN excluded.score
                     ELSE score * 0.85 + excluded.score * 0.15 END,
        attempts = attempts + 1
        """

    /// Persists all state produced by one answer in a single transaction. This
    /// keeps the user word, daily totals, and optional conjugation scores atomic.
    /// Called from the main actor, `asyncWrite` enqueues reviews in answer order.
    func persistReview(
        userWord: UserWord,
        correct: Bool,
        introduced: Bool,
        movedToProduction: Bool,
        movedToMastered: Bool,
        conjugation: ConjugationReviewRecord?
    ) {
        let today = AppDateFormatter.string(from: .now)

        db.asyncWrite({ db in
            try userWord.update(db)
            try db.execute(sql: """
                INSERT INTO dailyActivity (
                    date, reviewAttempts, correctAnswers, wordsIntroduced,
                    movedToProduction, movedToMastered
                )
                VALUES (?, 1, ?, ?, ?, ?)
                ON CONFLICT(date) DO UPDATE SET
                    reviewAttempts = reviewAttempts + 1,
                    correctAnswers = correctAnswers + excluded.correctAnswers,
                    wordsIntroduced = wordsIntroduced + excluded.wordsIntroduced,
                    movedToProduction = movedToProduction + excluded.movedToProduction,
                    movedToMastered = movedToMastered + excluded.movedToMastered
                """, arguments: [
                    today,
                    correct ? 1 : 0,
                    introduced ? 1 : 0,
                    movedToProduction ? 1 : 0,
                    movedToMastered ? 1 : 0,
                ])

            guard let conjugation else { return }
            let score = correct ? 1.0 : 0.0
            try db.execute(sql: """
                INSERT INTO tenseStats (tense, score, attempts) VALUES (?, ?, 1)
                ON CONFLICT(tense) DO UPDATE SET \(Self.scoreUpsertSQL)
                """, arguments: [conjugation.tense, score])
            try db.execute(sql: """
                INSERT INTO conjugationStats (verb, tense, pronoun, score, attempts) VALUES (?, ?, ?, ?, 1)
                ON CONFLICT(verb, tense, pronoun) DO UPDATE SET \(Self.scoreUpsertSQL)
                """, arguments: [conjugation.verb, conjugation.tense, conjugation.pronoun, score])
        }, completion: { _, result in
            if case .failure(let error) = result {
                print("Failed to persist review: \(error)")
            }
        })
    }
}
