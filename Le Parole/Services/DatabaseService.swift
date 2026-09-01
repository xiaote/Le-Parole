import Foundation
import GRDB

struct ConjugationReviewRecord: Sendable {
    let verb: String
    let tense: String
    let pronoun: String
}

final class DatabaseService: @unchecked Sendable {
    nonisolated static let shared = DatabaseService()

    nonisolated let db: DatabaseQueue

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dbPath = appSupport.appendingPathComponent("le_parole.sqlite").path

        do {
            var config = Configuration()
            config.foreignKeysEnabled = true
            db = try DatabaseQueue(path: dbPath, configuration: config)
            try migrate()
        } catch {
            fatalError("DatabaseService init failed: \(error.localizedDescription)")
        }
    }

    func exportDatabase() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeParoleBackup_\(formatter.string(from: Date())).sqlite")

        if FileManager.default.fileExists(atPath: exportURL.path) {
            try FileManager.default.removeItem(at: exportURL)
        }
        let backupDB = try DatabaseQueue(path: exportURL.path)
        try db.backup(to: backupDB)
        return exportURL
    }

    func importDatabase(from url: URL) throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let databaseURL = appSupport.appendingPathComponent("le_parole.sqlite")
        let fileManager = FileManager.default

        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        for url in [
            databaseURL,
            appSupport.appendingPathComponent("le_parole.sqlite-wal"),
            appSupport.appendingPathComponent("le_parole.sqlite-shm"),
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.copyItem(at: url, to: databaseURL)
    }

    // The app has one active, already-current installation. v27 intentionally
    // replaces the historic migration chain: fresh databases get the complete
    // current schema, while the known local database only receives the final
    // catalogue-history reconciliation.
    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v27_current_schema") { db in
            if try db.tableExists("words") {
                try Self.reconcileKnownCatalogueRetirements(db)
            } else {
                try Self.createCurrentSchema(db)
            }
        }
        try migrator.migrate(db)
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

        try db.create(table: "userSettings") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("dailyPracticeGoal", .integer).notNull().defaults(to: 20)
            t.column("dailyNewWordGoal", .integer).notNull().defaults(to: 20)
            t.column("autoPlayPronunciation", .boolean).notNull().defaults(to: true)
            t.column("conjugationLevel", .integer).notNull().defaults(to: 1)
            t.column("geminiApiKey", .text).notNull().defaults(to: "")
            t.column("targetLevel", .text).notNull().defaults(to: "None")
        }

        try db.create(table: "dailyActivity") { t in
            t.primaryKey("date", .text)
            t.column("recognition", .integer).notNull().defaults(to: 0)
            t.column("production", .integer).notNull().defaults(to: 0)
            t.column("mastered", .integer).notNull().defaults(to: 0)
            t.column("reviewAttempts", .integer).notNull().defaults(to: 0)
            t.column("correctAnswers", .integer).notNull().defaults(to: 0)
            t.column("wordsIntroduced", .integer).notNull().defaults(to: 0)
            t.column("movedToProduction", .integer).notNull().defaults(to: 0)
            t.column("movedToMastered", .integer).notNull().defaults(to: 0)
            t.column("hasDetailedMetrics", .boolean).notNull().defaults(to: false)
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

        try db.create(index: "idx_uw_stage", on: "userWords", columns: ["stage"])
        try db.create(index: "idx_uw_review", on: "userWords", columns: ["nextReviewDate"])
        try db.create(index: "idx_uw_word", on: "userWords", columns: ["wordId"])
        try db.create(index: "idx_w_italian", on: "words", columns: ["italian"])
        try db.create(index: "idx_w_level_freq", on: "words", columns: ["level", "frequencyRank"])
    }

    nonisolated private static func reconcileKnownCatalogueRetirements(_ db: Database) throws {
        try mergeCatalogueDuplicates(db, redirects: [
            "comm_15943": "comm_444", // claro (obsolete) → chiaro
            "comm_11974": "2050",     // sù → su
        ])
    }

    nonisolated private static func mergeCatalogueDuplicates(_ db: Database, redirects: [String: String]) throws {
        for (retiredID, canonicalID) in redirects {
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words WHERE wordId = ?", arguments: [canonicalID]) ?? 0 > 0 else {
                continue
            }

            let retired = try Row.fetchOne(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [retiredID])
            let canonical = try Row.fetchOne(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [canonicalID])

            switch (retired, canonical) {
            case let (retired?, canonical?):
                try merge(retired: retired, into: canonical, canonicalID: canonicalID, db: db)
                try db.execute(sql: "DELETE FROM userWords WHERE wordId = ?", arguments: [retiredID])
            case (let retired?, nil):
                let userWordID: Int64 = retired["id"]
                try db.execute(
                    sql: "UPDATE userWords SET wordId = ? WHERE id = ?",
                    arguments: [canonicalID, userWordID]
                )
            case (nil, _):
                break
            }
            try db.execute(sql: "DELETE FROM words WHERE wordId = ?", arguments: [retiredID])
        }
    }

    nonisolated private static func merge(retired: Row, into canonical: Row, canonicalID: String, db: Database) throws {
        let retiredStage: String = retired["stage"]
        let canonicalStage: String = canonical["stage"]
        let mergedStage: String
        if retiredStage == "skipped" { mergedStage = canonicalStage }
        else if canonicalStage == "skipped" { mergedStage = retiredStage }
        else if retiredStage == "recognition" || canonicalStage == "recognition" { mergedStage = "recognition" }
        else if retiredStage == "production" || canonicalStage == "production" { mergedStage = "production" }
        else if retiredStage == "mastered" && canonicalStage == "mastered" { mergedStage = "mastered" }
        else { mergedStage = "new" }

        func later(_ first: Double?, _ second: Double?) -> Double? {
            switch (first, second) {
            case let (left?, right?): max(left, right)
            case let (left?, nil): left
            case let (nil, right?): right
            case (nil, nil): nil
            }
        }

        func earlier(_ first: Double?, _ second: Double?) -> Double? {
            switch (first, second) {
            case let (left?, right?): min(left, right)
            case let (left?, nil): left
            case let (nil, right?): right
            case (nil, nil): nil
            }
        }

        let retiredEase: Double = retired["easeFactor"]
        let canonicalEase: Double = canonical["easeFactor"]
        let retiredInterval: Int = retired["interval"]
        let canonicalInterval: Int = canonical["interval"]
        let retiredRepetitions: Int = retired["repetitions"]
        let canonicalRepetitions: Int = canonical["repetitions"]
        let retiredNextReview: Double = retired["nextReviewDate"]
        let canonicalNextReview: Double = canonical["nextReviewDate"]
        let retiredCorrect: Int = retired["totalCorrect"]
        let canonicalCorrect: Int = canonical["totalCorrect"]
        let retiredAttempts: Int = retired["totalAttempts"]
        let canonicalAttempts: Int = canonical["totalAttempts"]
        let retiredLastReview: Double? = retired["lastReviewDate"]
        let canonicalLastReview: Double? = canonical["lastReviewDate"]
        let retiredLearned: Double? = retired["learnedDate"]
        let canonicalLearned: Double? = canonical["learnedDate"]
        let retiredLastWrong: Double? = retired["lastWrongDate"]
        let canonicalLastWrong: Double? = canonical["lastWrongDate"]

        try db.execute(sql: """
            UPDATE userWords
            SET stage = ?, easeFactor = ?, interval = ?, repetitions = ?, nextReviewDate = ?,
                lastReviewDate = ?, learnedDate = ?, lastWrongDate = ?,
                totalCorrect = ?, totalAttempts = ?
            WHERE wordId = ?
            """, arguments: [
                mergedStage,
                min(retiredEase, canonicalEase),
                min(retiredInterval, canonicalInterval),
                min(retiredRepetitions, canonicalRepetitions),
                min(retiredNextReview, canonicalNextReview),
                later(retiredLastReview, canonicalLastReview),
                earlier(retiredLearned, canonicalLearned),
                later(retiredLastWrong, canonicalLastWrong),
                retiredCorrect + canonicalCorrect,
                retiredAttempts + canonicalAttempts,
                canonicalID,
            ])
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

    nonisolated static let joinSQL = """
        \(userWordSelectSQL)
        ORDER BY w.frequencyRank
        """

    nonisolated static func fetchUserWords(_ db: Database) throws -> [UserWord] {
        try UserWord.fetchAll(db, sql: joinSQL)
    }

    nonisolated func fetchUserWords() throws -> [UserWord] {
        try db.read { db in try Self.fetchUserWords(db) }
    }

    nonisolated func makeSettingsObservation() -> ValueObservation<ValueReducers.Fetch<UserSettings?>> {
        ValueObservation.tracking { db in try UserSettings.fetchOne(db) }
    }

    // MARK: - Review persistence

    /// Persists all state produced by one answer in a single transaction. This
    /// keeps the user word, daily totals, and optional conjugation scores atomic
    /// while avoiding two or three separate writer-queue hops per card.
    func persistReview(
        userWord: UserWord,
        correct: Bool,
        introduced: Bool,
        movedToProduction: Bool,
        movedToMastered: Bool,
        conjugation: ConjugationReviewRecord?
    ) async {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let today = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )

        do {
            try await db.write { db in
                try userWord.update(db)
                try db.execute(sql: """
                    INSERT INTO dailyActivity (
                        date, recognition, production, mastered,
                        reviewAttempts, correctAnswers, wordsIntroduced,
                        movedToProduction, movedToMastered, hasDetailedMetrics
                    )
                    VALUES (?, 0, 0, 0, 1, ?, ?, ?, ?, 1)
                    ON CONFLICT(date) DO UPDATE SET
                        reviewAttempts = reviewAttempts + 1,
                        correctAnswers = correctAnswers + CASE WHEN hasDetailedMetrics THEN excluded.correctAnswers ELSE 0 END,
                        wordsIntroduced = wordsIntroduced + CASE WHEN hasDetailedMetrics THEN excluded.wordsIntroduced ELSE 0 END,
                        movedToProduction = movedToProduction + CASE WHEN hasDetailedMetrics THEN excluded.movedToProduction ELSE 0 END,
                        movedToMastered = movedToMastered + CASE WHEN hasDetailedMetrics THEN excluded.movedToMastered ELSE 0 END
                    """, arguments: [
                        today,
                        correct ? 1 : 0,
                        introduced ? 1 : 0,
                        movedToProduction ? 1 : 0,
                        movedToMastered ? 1 : 0,
                    ])

                guard let conjugation else { return }
                let currentTense = try TenseStat.fetchOne(db, key: conjugation.tense)
                    ?? TenseStat(tense: conjugation.tense)
                let tenseScore = currentTense.attempts == 0
                    ? (correct ? 1.0 : 0.0)
                    : (currentTense.score * 0.85) + (correct ? 0.15 : 0.0)
                try TenseStat(
                    tense: conjugation.tense,
                    score: tenseScore,
                    attempts: currentTense.attempts + 1
                ).save(db)

                let currentConjugation = try ConjugationStat.fetchOne(
                    db,
                    sql: "SELECT * FROM conjugationStats WHERE verb = ? AND tense = ? AND pronoun = ?",
                    arguments: [conjugation.verb, conjugation.tense, conjugation.pronoun]
                ) ?? ConjugationStat(
                    verb: conjugation.verb,
                    tense: conjugation.tense,
                    pronoun: conjugation.pronoun
                )
                let conjugationScore = currentConjugation.attempts == 0
                    ? (correct ? 1.0 : 0.0)
                    : (currentConjugation.score * 0.85) + (correct ? 0.15 : 0.0)
                try ConjugationStat(
                    id: currentConjugation.id,
                    verb: conjugation.verb,
                    tense: conjugation.tense,
                    pronoun: conjugation.pronoun,
                    score: conjugationScore,
                    attempts: currentConjugation.attempts + 1
                ).save(db)
            }
        } catch {
            print("Failed to persist review: \(error)")
        }
    }
}
