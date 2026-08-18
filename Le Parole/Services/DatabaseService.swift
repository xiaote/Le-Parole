import Foundation
import GRDB

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
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let dateString = formatter.string(from: Date())
        
        let exportUrl = fileManager.temporaryDirectory.appendingPathComponent("LeParoleBackup_\(dateString).sqlite")
        if fileManager.fileExists(atPath: exportUrl.path) {
            try fileManager.removeItem(at: exportUrl)
        }
        
        let backupDB = try DatabaseQueue(path: exportUrl.path)
        try db.backup(to: backupDB)
        return exportUrl
    }
    
    func importDatabase(from url: URL) throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbPath = appSupport.appendingPathComponent("le_parole.sqlite")
        let walPath = appSupport.appendingPathComponent("le_parole.sqlite-wal")
        let shmPath = appSupport.appendingPathComponent("le_parole.sqlite-shm")
        
        let fileManager = FileManager.default
        
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        try? fileManager.removeItem(at: dbPath)
        try? fileManager.removeItem(at: walPath)
        try? fileManager.removeItem(at: shmPath)
        
        try fileManager.copyItem(at: url, to: dbPath)
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_schema") { db in
            try db.create(table: "words") { t in
                t.primaryKey("wordId", .text)
                t.column("italian", .text).notNull()
                t.column("english", .text).notNull()
                t.column("alternatives", .text).notNull().defaults(to: "[]")
                t.column("level", .text).notNull()
                t.column("frequencyRank", .integer).notNull()
                t.column("isUserCreated", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "userWords") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("wordId", .text).notNull()
                    .references("words", onDelete: .cascade)
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

            try db.create(index: "idx_uw_stage",     on: "userWords", columns: ["stage"])
            try db.create(index: "idx_uw_review",    on: "userWords", columns: ["nextReviewDate"])
            try db.create(index: "idx_uw_word",      on: "userWords", columns: ["wordId"])
            try db.create(index: "idx_w_italian",    on: "words",     columns: ["italian"])
            try db.create(index: "idx_w_level_freq", on: "words",     columns: ["level", "frequencyRank"])
        }

        migrator.registerMigration("v2_cleanup_conjugated_verbs") { db in
            // Empty placeholder to prevent GRDB crash for users who already applied this migration.
            // The actual cleanup logic has been moved to v7_cleanup_conjugated_verbs.
        }

        migrator.registerMigration("v2_schema_settings") { db in
            try db.create(table: "userSettings", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("dailyNewWordGoal", .integer).notNull().defaults(to: 20)
            }
        }

        // One-time cleanup for duplicate userWords created by the cross-file
        // deduplication bug (different wordIds, same Italian text).
        // Deletes directly from userWords — no cascade complexity.
        // Orphan words rows are harmless; WordLoader's existingItalian guard
        // already blocks new userWords from being created for them.
        migrator.registerMigration("v2_dedup_words") { db in
            let italians = try String.fetchAll(db, sql: """
                SELECT w.italian
                FROM userWords uw
                JOIN words w ON w.wordId = uw.wordId
                WHERE w.isUserCreated = 0
                GROUP BY w.italian COLLATE NOCASE
                HAVING COUNT(*) > 1
                """)
            for italian in italians {
                let ids = try Int64.fetchAll(db, sql: """
                    SELECT uw.id
                    FROM userWords uw
                    JOIN words w ON w.wordId = uw.wordId
                    WHERE w.italian = ? COLLATE NOCASE
                      AND w.isUserCreated = 0
                    ORDER BY
                        CASE uw.stage
                            WHEN 'skipped'     THEN 5
                            WHEN 'mastered'    THEN 4
                            WHEN 'production'  THEN 3
                            WHEN 'recognition' THEN 2
                            WHEN 'new'         THEN 1
                            ELSE 0
                        END DESC,
                        uw.totalCorrect DESC,
                        uw.id DESC
                    """, arguments: [italian])
                for id in ids.dropFirst() {
                    try db.execute(sql: "DELETE FROM userWords WHERE id = ?",
                                   arguments: [id])
                }
            }
        }

        migrator.registerMigration("v3_daily_activity") { db in
            try db.create(table: "dailyActivity", ifNotExists: true) { t in
                t.primaryKey("date", .text) // YYYY-MM-DD
                t.column("recognition", .integer).notNull().defaults(to: 0)
                t.column("production", .integer).notNull().defaults(to: 0)
                t.column("mastered", .integer).notNull().defaults(to: 0)
            }
            
            // Backfill today's data from UserWords based on lastReviewDate
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            let todayStr = formatter.string(from: Date())
            
            // We just aggregate current stage of words that were reviewed today
            // Note: This only captures their *current* stage, which is fine for a one-time backfill.
            let todayStart = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            
            try db.execute(sql: """
                INSERT INTO dailyActivity (date, recognition, production, mastered)
                SELECT 
                    ?,
                    SUM(CASE WHEN stage = 'recognition' THEN 1 ELSE 0 END),
                    SUM(CASE WHEN stage = 'production' THEN 1 ELSE 0 END),
                    SUM(CASE WHEN stage = 'mastered' THEN 1 ELSE 0 END)
                FROM userWords
                WHERE lastReviewDate >= ?
                """, arguments: [todayStr, todayStart])
        }

        migrator.registerMigration("v4_dedup_words") { db in
            let italians = try String.fetchAll(db, sql: """
                SELECT w.italian
                FROM userWords uw
                JOIN words w ON w.wordId = uw.wordId
                GROUP BY w.italian COLLATE NOCASE
                HAVING COUNT(*) > 1
                """)
            for italian in italians {
                let ids = try Int64.fetchAll(db, sql: """
                    SELECT uw.id
                    FROM userWords uw
                    JOIN words w ON w.wordId = uw.wordId
                    WHERE w.italian = ? COLLATE NOCASE
                    ORDER BY
                        CASE uw.stage
                            WHEN 'skipped'     THEN 5
                            WHEN 'mastered'    THEN 4
                            WHEN 'production'  THEN 3
                            WHEN 'recognition' THEN 2
                            WHEN 'new'         THEN 1
                            ELSE 0
                        END DESC,
                        uw.totalCorrect DESC,
                        uw.id DESC
                    """, arguments: [italian])
                for id in ids.dropFirst() {
                    try db.execute(sql: "DELETE FROM userWords WHERE id = ?", arguments: [id])
                }
            }
        }

        migrator.registerMigration("v5_dedup_all") { db in
            let italians = try String.fetchAll(db, sql: """
                SELECT w.italian
                FROM userWords uw
                JOIN words w ON w.wordId = uw.wordId
                GROUP BY w.italian COLLATE NOCASE
                HAVING COUNT(*) > 1
                """)
            for italian in italians {
                let ids = try Int64.fetchAll(db, sql: """
                    SELECT uw.id
                    FROM userWords uw
                    JOIN words w ON w.wordId = uw.wordId
                    WHERE w.italian = ? COLLATE NOCASE
                    ORDER BY
                        CASE uw.stage
                            WHEN 'skipped'     THEN 5
                            WHEN 'mastered'    THEN 4
                            WHEN 'production'  THEN 3
                            WHEN 'recognition' THEN 2
                            WHEN 'new'         THEN 1
                            ELSE 0
                        END DESC,
                        uw.totalCorrect DESC,
                        uw.id DESC
                    """, arguments: [italian])
                for id in ids.dropFirst() {
                    try db.execute(sql: "DELETE FROM userWords WHERE id = ?", arguments: [id])
                }
            }

            let duplicateItaliansInWords = try String.fetchAll(db, sql: """
                SELECT italian
                FROM words
                GROUP BY italian COLLATE NOCASE
                HAVING COUNT(*) > 1
                """)

            for italian in duplicateItaliansInWords {
                let usedWordId = try String.fetchOne(db, sql: """
                    SELECT w.wordId
                    FROM words w
                    JOIN userWords uw ON w.wordId = uw.wordId
                    WHERE w.italian = ? COLLATE NOCASE
                    LIMIT 1
                    """, arguments: [italian])
                
                if let keepId = usedWordId {
                    try db.execute(sql: """
                        DELETE FROM words
                        WHERE italian = ? COLLATE NOCASE AND wordId != ?
                        """, arguments: [italian, keepId])
                } else {
                    if let keepId = try String.fetchOne(db, sql: "SELECT wordId FROM words WHERE italian = ? COLLATE NOCASE LIMIT 1", arguments: [italian]) {
                        try db.execute(sql: """
                            DELETE FROM words
                            WHERE italian = ? COLLATE NOCASE AND wordId != ?
                            """, arguments: [italian, keepId])
                    }
                }
            }
        }

        migrator.registerMigration("v6_conjugation_setting") { db in
            try db.alter(table: "userSettings") { t in
                t.add(column: "extraConjugationCards", .integer).notNull().defaults(to: 2)
            }
        }

        migrator.registerMigration("v8_autoplay_setting") { db in
            try db.alter(table: "userSettings") { t in
                t.add(column: "autoPlayPronunciation", .boolean).notNull().defaults(to: true)
            }
        }
        
        migrator.registerMigration("v9_conjugation_level") { db in
            try db.alter(table: "userSettings") { t in
                t.add(column: "conjugationLevel", .integer).notNull().defaults(to: 1)
            }
        }

        migrator.registerMigration("v7_cleanup_conjugated_verbs") { db in
            // Logic moved to async background task to avoid SQLite errors during migration
        }
        migrator.registerMigration("v10_remove_same_words") { db in
            try db.execute(sql: """
                DELETE FROM userWords
                WHERE wordId IN (
                    SELECT wordId FROM words WHERE LOWER(italian) = LOWER(english)
                )
                """)
            try db.execute(sql: """
                DELETE FROM words 
                WHERE LOWER(italian) = LOWER(english)
                """)
        }
        
        migrator.registerMigration("v11_conjugation_stats") { db in
            try db.create(table: "tenseStats") { t in
                t.primaryKey("tense", .text)
                t.column("score", .double).notNull().defaults(to: 0.5)
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
        }

        migrator.registerMigration("v12_deduplicate_words_2026") { db in
            let stageOrder: [String: Int] = ["new": 0, "recognition": 1, "production": 2, "mastered": 3, "skipped": 4]
            
            for (deletedId, primaryId) in DuplicateMappings.wordIdRedirects {
                
                // Ensure primaryId exists in `words` so foreign key constraints don't fail
                let primaryExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM words WHERE wordId = ?", arguments: [primaryId])! > 0
                if !primaryExists {
                    try db.execute(sql: """
                        INSERT INTO words (wordId, italian, english, alternatives, level, frequencyRank, isUserCreated)
                        VALUES (?, 'dummy_migrated', 'dummy', '[]', 'A1', 999999, 0)
                        """, arguments: [primaryId])
                }
                
                // Fetch all userWords for deletedId (just in case there are duplicates)
                let deletedUserWords = try Row.fetchAll(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [deletedId])
                
                for deletedWord in deletedUserWords {
                    // Check if primaryId already has a userWord
                    if let primaryWord = try Row.fetchOne(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [primaryId]) {
                        
                        let dStage = deletedWord["stage"] as String? ?? "new"
                        let pStage = primaryWord["stage"] as String? ?? "new"
                        let mergedStage = (stageOrder[dStage] ?? 0) > (stageOrder[pStage] ?? 0) ? dStage : pStage
                        
                        let dCorrect = deletedWord["totalCorrect"] as Int? ?? 0
                        let pCorrect = primaryWord["totalCorrect"] as Int? ?? 0
                        let mergedCorrect = max(dCorrect, pCorrect)
                        
                        let dAttempts = deletedWord["totalAttempts"] as Int? ?? 0
                        let pAttempts = primaryWord["totalAttempts"] as Int? ?? 0
                        let mergedAttempts = max(dAttempts, pAttempts)
                        
                        let pId = primaryWord["id"] as Int64
                        try db.execute(sql: """
                            UPDATE userWords 
                            SET stage = ?, totalCorrect = ?, totalAttempts = ?
                            WHERE id = ?
                            """, arguments: [mergedStage, mergedCorrect, mergedAttempts, pId])
                        
                        let dId = deletedWord["id"] as Int64
                        try db.execute(sql: "DELETE FROM userWords WHERE id = ?", arguments: [dId])
                    } else {
                        // Remap this userWord to primaryId
                        let dId = deletedWord["id"] as Int64
                        try db.execute(sql: "UPDATE userWords SET wordId = ? WHERE id = ?", arguments: [primaryId, dId])
                    }
                }
                
                // Delete the deletedId from words table
                try db.execute(sql: "DELETE FROM words WHERE wordId = ?", arguments: [deletedId])
            }
        }
        
        migrator.registerMigration("v13_remove_same_words_again") { db in
            try db.execute(sql: """
                DELETE FROM userWords
                WHERE wordId IN (
                    SELECT wordId FROM words WHERE LOWER(italian) = LOWER(english)
                )
                """)
            try db.execute(sql: """
                DELETE FROM words 
                WHERE LOWER(italian) = LOWER(english)
                """)
        }

        migrator.registerMigration("v14_remove_abbreviations") { db in
            let abbrevs = ["fm", "kg", "km2", "mb", "ml", "pc", "plc", "prof", "wc"]
            let inClause = abbrevs.map { "'\($0)'" }.joined(separator: ", ")
            
            try db.execute(sql: """
                DELETE FROM userWords
                WHERE wordId IN (
                    SELECT wordId FROM words WHERE LOWER(italian) IN (\(inClause))
                )
                """)
            try db.execute(sql: """
                DELETE FROM words 
                WHERE LOWER(italian) IN (\(inClause))
                """)
        }

        migrator.registerMigration("v15_inflections") { db in
            try db.alter(table: "words") { t in
                t.add(column: "inflections", .text)
            }
        }

        migrator.registerMigration("v16_gemini_key") { db in
            try db.alter(table: "userSettings") { t in
                t.add(column: "geminiApiKey", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v17_target_level") { db in
            try db.alter(table: "userSettings") { t in
                t.add(column: "targetLevel", .text).notNull().defaults(to: "B2")
            }
        }
        
        migrator.registerMigration("v18_part_of_speech") { db in
            try db.alter(table: "words") { t in
                t.add(column: "partOfSpeech", .text)
            }
        }
        
        migrator.registerMigration("v19_cleanup_orphans") { db in
            try db.execute(sql: """
                DELETE FROM userWords 
                WHERE wordId NOT IN (SELECT wordId FROM words)
            """)
        }
        
        migrator.registerMigration("v20_ensure_userwords") { db in
            try db.execute(sql: """
                INSERT INTO userWords (wordId, stage, easeFactor, interval, repetitions, nextReviewDate, totalCorrect, totalAttempts)
                SELECT wordId, 'new', 2.5, 1, 0, 0, 0, 0
                FROM words
                WHERE wordId NOT IN (SELECT wordId FROM userWords)
            """)
        }

        // Merge spelling and source-list duplicates before retiring their IDs so
        // every review attempt remains attached to the canonical headword.
        migrator.registerMigration("v21_redirect_catalogue_duplicates") { db in
            let redirects = [
                "comm_1670": "comm_6",       // piú → più
                "1276": "comm_3313",         // geografía → geografia
            ]
            try Self.mergeCatalogueDuplicates(db, redirects: redirects)
        }

        // Consolidate spelling and formatting variants which represented the
        // same learning card. Source data has already merged their accepted
        // English answers; this preserves the user's review history as well.
        migrator.registerMigration("v22_redirect_orthographic_variants") { db in
            let redirects = [
                "comm_406": "2037",           // cosi → così
                "comm_10049": "comm_11857",   // equipe → équipe
                "comm_10851": "comm_1040",    // modalita → modalità
                "comm_384": "comm_1208",      // papa → papà
                "comm_323": "comm_6",         // piu → più
                "comm_13094": "comm_3866",    // pressochè → pressoché
                "comm_16341": "comm_1999",    // priorita → priorità
                "comm_16342": "comm_1816",    // probabilita → probabilità
                "comm_5660": "393",           // qualita → qualità
                "comm_13543": "comm_11827",   // rossoblu → rossoblù
                "comm_4578": "465",           // venerdi → venerdì
                "comm_13785": "comm_4596",    // dopodichè → dopodiché
                "comm_9145": "comm_1333",     // fin'ora → finora
                "comm_6403": "comm_2161",     // tutt'ora → tuttora
            ]
            try Self.mergeCatalogueDuplicates(db, redirects: redirects)
        }

        // These cards are mechanically derivable from the retained number
        // curriculum. Keep existing rows and all review statistics, but do not
        // schedule them again after the catalogue stops seeding them.
        migrator.registerMigration("v23_retire_composite_number_cards") { db in
            let retiredIds = [
                "comm_9227", "comm_7994", "comm_6213", "comm_5973", "comm_10902",
                "comm_10519", "comm_10132", "comm_14046", "comm_13890", "comm_11981",
                "comm_15264", "comm_10259", "comm_12681", "comm_16383", "comm_16537",
                "comm_14446", "comm_12343", "comm_13695", "comm_15727",
            ]
            let placeholders = retiredIds.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: "UPDATE userWords SET stage = 'skipped' WHERE wordId IN (\(placeholders))",
                arguments: StatementArguments(retiredIds)
            )
        }

        // The original dailyActivity columns described the card's stage after
        // an answer, which is neither an answer outcome nor a stage promotion.
        // Preserve their aggregate activity as legacy review attempts, then
        // record explicit, unambiguous events from this version forward.
        migrator.registerMigration("v24_progress_metrics") { db in
            try db.alter(table: "dailyActivity") { t in
                t.add(column: "reviewAttempts", .integer).notNull().defaults(to: 0)
                t.add(column: "correctAnswers", .integer).notNull().defaults(to: 0)
                t.add(column: "wordsIntroduced", .integer).notNull().defaults(to: 0)
                t.add(column: "movedToProduction", .integer).notNull().defaults(to: 0)
                t.add(column: "movedToMastered", .integer).notNull().defaults(to: 0)
                t.add(column: "hasDetailedMetrics", .boolean).notNull().defaults(to: false)
            }
            try db.execute(sql: """
                UPDATE dailyActivity
                SET reviewAttempts = recognition + production + mastered
                """)

            try db.alter(table: "tenseStats") { t in
                t.add(column: "attempts", .integer).notNull().defaults(to: 0)
            }
            // Individual conjugation rows already retain their attempt totals,
            // so historical sample sizes can be restored without modifying the
            // intentionally recency-weighted scores.
            try db.execute(sql: """
                UPDATE tenseStats
                SET attempts = COALESCE((
                    SELECT SUM(conjugationStats.attempts)
                    FROM conjugationStats
                    WHERE conjugationStats.tense = tenseStats.tense
                ), 0)
                """)
        }

        try migrator.migrate(db)
    }

    private static func mergeCatalogueDuplicates(_ db: Database, redirects: [String: String]) throws {
        for (retiredId, canonicalId) in redirects {
            guard
                let retired = try Row.fetchOne(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [retiredId]),
                let canonical = try Row.fetchOne(db, sql: "SELECT * FROM userWords WHERE wordId = ?", arguments: [canonicalId])
            else {
                continue
            }

            let retiredStage: String = retired["stage"]
            let canonicalStage: String = canonical["stage"]
            let mergedStage: String
            if retiredStage == "skipped" { mergedStage = canonicalStage }
            else if canonicalStage == "skipped" { mergedStage = retiredStage }
            else if retiredStage == "recognition" || canonicalStage == "recognition" { mergedStage = "recognition" }
            else if retiredStage == "production" || canonicalStage == "production" { mergedStage = "production" }
            else if retiredStage == "mastered" && canonicalStage == "mastered" { mergedStage = "mastered" }
            else { mergedStage = "new" }

            let retiredCorrect: Int = retired["totalCorrect"]
            let canonicalCorrect: Int = canonical["totalCorrect"]
            let retiredAttempts: Int = retired["totalAttempts"]
            let canonicalAttempts: Int = canonical["totalAttempts"]
            let retiredNextReview: Double = retired["nextReviewDate"]
            let canonicalNextReview: Double = canonical["nextReviewDate"]
            let retiredInterval: Int = retired["interval"]
            let canonicalInterval: Int = canonical["interval"]
            let retiredEase: Double = retired["easeFactor"]
            let canonicalEase: Double = canonical["easeFactor"]
            let retiredRepetitions: Int = retired["repetitions"]
            let canonicalRepetitions: Int = canonical["repetitions"]
            let retiredLastReview: Double? = retired["lastReviewDate"]
            let canonicalLastReview: Double? = canonical["lastReviewDate"]
            let retiredLearned: Double? = retired["learnedDate"]
            let canonicalLearned: Double? = canonical["learnedDate"]
            let retiredLastWrong: Double? = retired["lastWrongDate"]
            let canonicalLastWrong: Double? = canonical["lastWrongDate"]

            func later(_ first: Double?, _ second: Double?) -> Double? {
                switch (first, second) {
                case let (left?, right?): return max(left, right)
                case let (left?, nil): return left
                case let (nil, right?): return right
                case (nil, nil): return nil
                }
            }

            func earlier(_ first: Double?, _ second: Double?) -> Double? {
                switch (first, second) {
                case let (left?, right?): return min(left, right)
                case let (left?, nil): return left
                case let (nil, right?): return right
                case (nil, nil): return nil
                }
            }

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
                    canonicalId,
                ])
            try db.execute(sql: "DELETE FROM userWords WHERE wordId = ?", arguments: [retiredId])
            try db.execute(sql: "DELETE FROM words WHERE wordId = ?", arguments: [retiredId])
        }
    }

    // MARK: - Fetch helpers (nonisolated so they can be called from any actor)

    nonisolated static let joinSQL = """
        SELECT uw.id, uw.wordId, uw.stage, uw.easeFactor, uw.interval, uw.repetitions,
               uw.nextReviewDate, uw.lastReviewDate, uw.learnedDate, uw.lastWrongDate,
               uw.totalCorrect, uw.totalAttempts,
               w.italian, w.english, w.alternatives, w.level, w.frequencyRank, w.isUserCreated, w.inflections, w.partOfSpeech
        FROM userWords uw
        JOIN words w ON uw.wordId = w.wordId
        ORDER BY w.frequencyRank
        """

    nonisolated static func fetchUserWords(_ db: Database) throws -> [UserWord] {
        try UserWord.fetchAll(db, sql: joinSQL)
    }

    nonisolated func fetchUserWords() throws -> [UserWord] {
        try db.read { db in try Self.fetchUserWords(db) }
    }

    nonisolated func fetchSettings() throws -> UserSettings? {
        try db.read { db in try UserSettings.fetchOne(db) }
    }

    // MARK: - Observations

    nonisolated func makeSettingsObservation() -> ValueObservation<ValueReducers.Fetch<UserSettings?>> {
        ValueObservation.tracking { db in try UserSettings.fetchOne(db) }
    }

    // MARK: - Activity Logging

    func recordReview(
        correct: Bool,
        introduced: Bool,
        movedToProduction: Bool,
        movedToMastered: Bool
    ) async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())

        do {
            try await db.write { db in
                try db.execute(sql: """
                    INSERT INTO dailyActivity (
                        date, recognition, production, mastered,
                        reviewAttempts, correctAnswers, wordsIntroduced,
                        movedToProduction, movedToMastered, hasDetailedMetrics
                    )
                    VALUES (?, 0, 0, 0, 1, ?, ?, ?, ?, 1)
                    ON CONFLICT(date) DO UPDATE SET
                        reviewAttempts = reviewAttempts + 1,
                        correctAnswers = correctAnswers +
                            CASE WHEN hasDetailedMetrics THEN excluded.correctAnswers ELSE 0 END,
                        wordsIntroduced = wordsIntroduced +
                            CASE WHEN hasDetailedMetrics THEN excluded.wordsIntroduced ELSE 0 END,
                        movedToProduction = movedToProduction +
                            CASE WHEN hasDetailedMetrics THEN excluded.movedToProduction ELSE 0 END,
                        movedToMastered = movedToMastered +
                            CASE WHEN hasDetailedMetrics THEN excluded.movedToMastered ELSE 0 END
                    """, arguments: [
                        todayStr,
                        correct ? 1 : 0,
                        introduced ? 1 : 0,
                        movedToProduction ? 1 : 0,
                        movedToMastered ? 1 : 0,
                    ])
            }
        } catch {
            print("Failed to record review: \(error)")
        }
    }
    
    // MARK: - Conjugation Stats
    
    func recordConjugationResult(verb: String, tense: String, pronoun: String, correct: Bool) async {
        do {
            try await db.write { db in
                // Update TenseStat
                let currentTense = try TenseStat.fetchOne(db, key: tense) ?? TenseStat(tense: tense)
                let newTenseScore = currentTense.attempts == 0
                    ? (correct ? 1.0 : 0.0)
                    : (currentTense.score * 0.85) + (correct ? 0.15 : 0.0)
                let updatedTense = TenseStat(
                    tense: tense,
                    score: newTenseScore,
                    attempts: currentTense.attempts + 1
                )
                try updatedTense.save(db)
                
                // Update ConjugationStat
                let currentConj = try ConjugationStat.fetchOne(db, sql: "SELECT * FROM conjugationStats WHERE verb = ? AND tense = ? AND pronoun = ?", arguments: [verb, tense, pronoun]) ?? ConjugationStat(verb: verb, tense: tense, pronoun: pronoun)
                let newConjScore = currentConj.attempts == 0 ? (correct ? 1.0 : 0.0) : (currentConj.score * 0.85) + (correct ? 0.15 : 0.0)
                let updatedConj = ConjugationStat(id: currentConj.id, verb: verb, tense: tense, pronoun: pronoun, score: newConjScore, attempts: currentConj.attempts + 1)
                try updatedConj.save(db)
            }
        } catch {
            print("Failed to record conjugation result: \(error)")
        }
    }
    
    nonisolated func fetchConjugationStats(for verb: String) throws -> [ConjugationStat] {
        try db.read { db in
            try ConjugationStat.fetchAll(db, sql: "SELECT * FROM conjugationStats WHERE verb = ?", arguments: [verb])
        }
    }
}
