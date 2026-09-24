import Foundation
import GRDB
import Testing
@testable import Le_Parole

@Suite("Database migrations")
struct DatabaseMigrationTests {
    private func columns(_ table: String, _ db: Database) throws -> Set<String> {
        try Set(db.columns(in: table).map(\.name))
    }

    /// Records keys the migration would move to the Keychain, so tests never
    /// touch the real Keychain.
    final class KeyRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var keys: [String] { lock.withLock { stored } }
        func record(_ key: String) { lock.withLock { stored.append(key) } }
    }

    private func migrate(_ queue: DatabaseQueue, recorder: KeyRecorder = KeyRecorder()) throws {
        try DatabaseService.makeMigrator(storeLegacyGeminiKey: recorder.record).migrate(queue)
    }

    @Test func freshInstallCreatesCurrentSchemaAndSettingsRow() throws {
        let queue = try DatabaseQueue()
        let recorder = KeyRecorder()
        try migrate(queue, recorder: recorder)

        try queue.read { db in
            #expect(try columns("userSettings", db) == [
                "id", "dailyPracticeGoal", "dailyNewWordGoal", "autoPlayPronunciation",
                "conjugationLevel", "targetLevel",
            ])
            #expect(try columns("dailyActivity", db) == [
                "date", "reviewAttempts", "correctAnswers", "wordsIntroduced",
                "movedToProduction", "movedToMastered",
            ])
            let indexes = try Set(db.indexes(on: "userWords").map(\.name))
            #expect(indexes.isSuperset(of: [
                "idx_uw_review", "idx_uw_word_unique", "idx_uw_stage_review",
                "idx_uw_learned_date", "idx_uw_last_wrong_date", "idx_uw_last_review",
            ]))
            #expect(try db.indexes(on: "userWords").first { $0.name == "idx_uw_word_unique" }?.isUnique == true)

            let settings = try UserSettings.fetchAll(db)
            #expect(settings.count == 1)
            #expect(settings.first?.dailyPracticeGoal == UserSettings().dailyPracticeGoal)
            #expect(settings.first?.targetLevel == UserSettings().targetLevel)

            #expect(try DatabaseService.makeMigrator(storeLegacyGeminiKey: { _ in }).hasCompletedMigrations(db))
        }
        #expect(recorder.keys.isEmpty)

        // Migrating again is a no-op.
        try migrate(queue)
        #expect(try queue.read { try UserSettings.fetchCount($0) } == 1)
    }

    @Test func legacyV27DatabaseMigratesToCurrentSchema() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in try Self.createLegacyV27Database(db) }

        let recorder = KeyRecorder()
        try migrate(queue, recorder: recorder)

        #expect(recorder.keys == ["legacy-secret"])
        try queue.read { db in
            #expect(try !columns("userSettings", db).contains("geminiApiKey"))
            #expect(try !columns("userSettings", db).contains("extraConjugationCards"))
            #expect(try columns("dailyActivity", db).isDisjoint(with: ["recognition", "production", "mastered", "hasDetailedMetrics"]))

            let settings = try UserSettings.fetchAll(db)
            #expect(settings.count == 1)
            #expect(settings.first?.targetLevel == "B1")
            #expect(settings.first?.dailyPracticeGoal == 35)

            let activity = try Row.fetchOne(db, sql: "SELECT * FROM dailyActivity")
            #expect(activity?["reviewAttempts"] == 7)
            #expect(activity?["correctAnswers"] == 5)

            // The duplicate progress row with fewer attempts is gone.
            let progress = try Row.fetchAll(db, sql: "SELECT wordId, totalAttempts FROM userWords ORDER BY wordId")
            #expect(progress.map { $0["wordId"] as String } == ["1", "2"])
            #expect(progress.first?["totalAttempts"] == 9)

            let indexes = try Set(db.indexes(on: "userWords").map(\.name))
            #expect(indexes.contains("idx_uw_word_unique"))
            #expect(!indexes.contains("idx_uw_word"))
            #expect(!indexes.contains("idx_uw_stage"))
        }
    }

    @Test func backupValidationRejectsPreV27Backups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeParoleTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldPath = directory.appendingPathComponent("old.sqlite").path
        try DatabaseQueue(path: oldPath).write { db in
            try Self.createLegacyV27Database(db)
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'v27_current_schema'")
        }
        #expect {
            try DatabaseService.openValidatedBackup(atPath: oldPath)
        } throws: { error in
            if case DatabaseService.RestoreError.unsupportedVersion = error { true } else { false }
        }

        let currentPath = directory.appendingPathComponent("current.sqlite").path
        let current = try DatabaseQueue(path: currentPath)
        try migrate(current)
        try current.close()
        try DatabaseService.openValidatedBackup(atPath: currentPath).close()
    }

    /// The v27 schema as upgraded installs had it, before v28–v30.
    static func createLegacyV27Database(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations VALUES ('v1_schema'), ('v25_daily_practice_goal'), ('v27_current_schema');

            CREATE TABLE words (
                wordId TEXT PRIMARY KEY NOT NULL, italian TEXT NOT NULL, english TEXT NOT NULL,
                alternatives TEXT NOT NULL DEFAULT '[]', level TEXT NOT NULL,
                frequencyRank INTEGER NOT NULL, isUserCreated BOOLEAN NOT NULL DEFAULT 0,
                inflections TEXT, partOfSpeech TEXT
            );
            CREATE TABLE userWords (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                wordId TEXT NOT NULL REFERENCES words(wordId) ON DELETE CASCADE,
                stage TEXT NOT NULL DEFAULT 'new', easeFactor DOUBLE NOT NULL DEFAULT 2.5,
                interval INTEGER NOT NULL DEFAULT 1, repetitions INTEGER NOT NULL DEFAULT 0,
                nextReviewDate DOUBLE NOT NULL, lastReviewDate DOUBLE, learnedDate DOUBLE,
                lastWrongDate DOUBLE, totalCorrect INTEGER NOT NULL DEFAULT 0,
                totalAttempts INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX idx_uw_word ON userWords(wordId);
            CREATE INDEX idx_uw_stage ON userWords(stage);
            CREATE INDEX idx_uw_review ON userWords(nextReviewDate);
            CREATE TABLE userSettings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dailyNewWordGoal INTEGER NOT NULL DEFAULT 20,
                extraConjugationCards INTEGER NOT NULL DEFAULT 2,
                autoPlayPronunciation BOOLEAN NOT NULL DEFAULT 1,
                conjugationLevel INTEGER NOT NULL DEFAULT 1,
                geminiApiKey TEXT NOT NULL DEFAULT '',
                targetLevel TEXT NOT NULL DEFAULT 'None',
                dailyPracticeGoal INTEGER NOT NULL DEFAULT 20
            );
            CREATE TABLE dailyActivity (
                date TEXT PRIMARY KEY NOT NULL,
                recognition INTEGER NOT NULL DEFAULT 0, production INTEGER NOT NULL DEFAULT 0,
                mastered INTEGER NOT NULL DEFAULT 0, reviewAttempts INTEGER NOT NULL DEFAULT 0,
                correctAnswers INTEGER NOT NULL DEFAULT 0, wordsIntroduced INTEGER NOT NULL DEFAULT 0,
                movedToProduction INTEGER NOT NULL DEFAULT 0, movedToMastered INTEGER NOT NULL DEFAULT 0,
                hasDetailedMetrics BOOLEAN NOT NULL DEFAULT 0
            );
            CREATE TABLE tenseStats (tense TEXT PRIMARY KEY NOT NULL, score DOUBLE NOT NULL DEFAULT 0.5, attempts INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE conjugationStats (
                id INTEGER PRIMARY KEY AUTOINCREMENT, verb TEXT NOT NULL, tense TEXT NOT NULL,
                pronoun TEXT NOT NULL, score DOUBLE NOT NULL DEFAULT 0.5, attempts INTEGER NOT NULL DEFAULT 0,
                UNIQUE (verb, tense, pronoun)
            );

            INSERT INTO words (wordId, italian, english, level, frequencyRank) VALUES
                ('1', 'essere', 'to be', 'A1', 1), ('2', 'avere', 'to have', 'A1', 2);
            INSERT INTO userWords (wordId, nextReviewDate, totalAttempts) VALUES
                ('1', 0, 3), ('1', 0, 9), ('2', 0, 0);
            INSERT INTO userSettings (geminiApiKey, targetLevel, dailyPracticeGoal) VALUES ('legacy-secret', 'B1', 35);
            INSERT INTO dailyActivity (date, recognition, reviewAttempts, correctAnswers, hasDetailedMetrics)
                VALUES ('2026-08-01', 4, 7, 5, 1);
            """)
    }
}
