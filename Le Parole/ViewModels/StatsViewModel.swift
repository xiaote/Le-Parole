import Foundation
import GRDB

struct DailyCount: Identifiable, FetchableRecord, TableRecord {
    static let databaseTableName = "dailyActivity"
    
    var dateString: String // stored as "date" in db, but we need to map to Date
    var reviewAttempts: Int
    var correctAnswers: Int
    var wordsIntroduced: Int
    var movedToProduction: Int
    var movedToMastered: Int
    var hasDetailedMetrics: Bool
    
    var total: Int { reviewAttempts }
    var id: String { dateString }
    
    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString) ?? .now
    }
    
    init(
        dateString: String,
        reviewAttempts: Int = 0,
        correctAnswers: Int = 0,
        wordsIntroduced: Int = 0,
        movedToProduction: Int = 0,
        movedToMastered: Int = 0,
        hasDetailedMetrics: Bool = false
    ) {
        self.dateString = dateString
        self.reviewAttempts = reviewAttempts
        self.correctAnswers = correctAnswers
        self.wordsIntroduced = wordsIntroduced
        self.movedToProduction = movedToProduction
        self.movedToMastered = movedToMastered
        self.hasDetailedMetrics = hasDetailedMetrics
    }
    
    init(row: GRDB.Row) {
        dateString = row["date"]
        reviewAttempts = row["reviewAttempts"]
        correctAnswers = row["correctAnswers"]
        wordsIntroduced = row["wordsIntroduced"]
        movedToProduction = row["movedToProduction"]
        movedToMastered = row["movedToMastered"]
        hasDetailedMetrics = row["hasDetailedMetrics"]
    }
}

struct LevelStats: Equatable, Sendable {
    var level: String
    var mastered: Int
    var production: Int
    var recognition: Int
    var total: Int
}

struct StatsSnapshot: Equatable, Sendable {
    var mastered: Int = 0
    var production: Int = 0
    var recognition: Int = 0
    var notStarted: Int = 0
    var skipped: Int = 0
    var total: Int = 0
    
    var customCategories: [String] = []
    var levelStats: [String: LevelStats] = [:]
}

struct CumulativeProgressEntry: Identifiable, Equatable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct IntroducedWord: Sendable, Equatable {
    let level: String
    let learnedDate: Double
    let count: Int
}

@Observable
final class StatsViewModel {
    var snapshot = StatsSnapshot()
    var dailyActivities: [DailyCount] = []
    var tenseStats: [TenseStat] = []
    var settings: UserSettings?
    var introducedWords: [IntroducedWord] = []

    private var statsCancellable: AnyDatabaseCancellable?
    private var activityCancellable: AnyDatabaseCancellable?
    private var tenseStatsCancellable: AnyDatabaseCancellable?
    private var settingsCancellable: AnyDatabaseCancellable?
    private var introducedWordsCancellable: AnyDatabaseCancellable?

    static let cefrLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    static let supportedTenses = [
        "presente",
        "passato prossimo",
        "imperfetto",
        "presente progressivo",
        "futuro semplice",
        "imperativo",
        "condizionale presente",
        "condizionale passato",
        "congiuntivo presente",
        "congiuntivo imperfetto",
    ]

    init() {
        let db = DatabaseService.shared
        
        statsCancellable = ValueObservation.tracking { db in
            let mastered = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'mastered'") ?? 0
            let production = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'production'") ?? 0
            let recognition = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'recognition'") ?? 0
            let notStarted = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'new'") ?? 0
            let skipped = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'skipped'") ?? 0
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage != 'skipped'") ?? 0
            
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.level,
                       SUM(CASE WHEN uw.stage = 'mastered' THEN 1 ELSE 0 END) as mastered,
                       SUM(CASE WHEN uw.stage = 'production' THEN 1 ELSE 0 END) as production,
                       SUM(CASE WHEN uw.stage = 'recognition' THEN 1 ELSE 0 END) as recognition,
                       SUM(CASE WHEN uw.stage != 'skipped' THEN 1 ELSE 0 END) as total
                FROM userWords uw
                JOIN words w ON uw.wordId = w.wordId
                GROUP BY w.level
            """)
            
            var levelStats: [String: LevelStats] = [:]
            var allLevels: Set<String> = []
            
            for row in rows {
                let level: String = row["level"]
                allLevels.insert(level)
                levelStats[level] = LevelStats(
                    level: level,
                    mastered: row["mastered"],
                    production: row["production"],
                    recognition: row["recognition"],
                    total: row["total"]
                )
            }
            
            let builtIn: Set<String> = ["A1", "A2", "B1", "B2", "C1", "C2"]
            let customCategories = allLevels.subtracting(builtIn).sorted()
            
            return StatsSnapshot(
                mastered: mastered,
                production: production,
                recognition: recognition,
                notStarted: notStarted,
                skipped: skipped,
                total: total,
                customCategories: customCategories,
                levelStats: levelStats
            )
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] snapshot in self?.snapshot = snapshot }
        )
        
        activityCancellable = ValueObservation.tracking { db in
            try DailyCount.fetchAll(db)
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] activities in self?.dailyActivities = activities }
        )
        settingsCancellable = db.makeSettingsObservation().start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] s in self?.settings = s }
        )
        
        tenseStatsCancellable = ValueObservation.tracking { db in
            let stats = try TenseStat.fetchAll(db)
            let ranks = Dictionary(uniqueKeysWithValues: Self.supportedTenses.enumerated().map { ($0.element, $0.offset) })
            return stats
                .filter { ranks[$0.tense] != nil }
                .sorted { ranks[$0.tense, default: .max] < ranks[$1.tense, default: .max] }
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] stats in self?.tenseStats = stats }
        )
        
        introducedWordsCancellable = ValueObservation.tracking { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.level,
                       MIN(uw.learnedDate) AS learnedDate,
                       COUNT(*) AS count
                FROM userWords uw
                JOIN words w ON w.wordId = uw.wordId
                WHERE uw.learnedDate IS NOT NULL AND uw.stage != 'skipped'
                GROUP BY w.level, strftime('%Y-%m-%d', uw.learnedDate, 'unixepoch', 'localtime')
                ORDER BY learnedDate ASC
                """)
            return rows.map { row in
                IntroducedWord(
                    level: row["level"],
                    learnedDate: row["learnedDate"],
                    count: row["count"]
                )
            }
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] words in self?.introducedWords = words }
        )
    }

    var targetLevel: String {
        get { settings?.targetLevel ?? "None" }
        set {
            guard var s = settings else { return }
            s.targetLevel = newValue
            settings = s
            Task {
                try? DatabaseService.shared.db.write { db in try s.save(db) }
            }
        }
    }

    var mastered:    Int { snapshot.mastered }
    var production:  Int { snapshot.production }
    var recognition: Int { snapshot.recognition }
    var notStarted:  Int { snapshot.notStarted }
    var skipped:     Int { snapshot.skipped }
    var total:       Int { snapshot.total }

    var customCategories: [String] { snapshot.customCategories }

    func statsFor(level: String) -> LevelStats {
        snapshot.levelStats[level] ?? LevelStats(level: level, mastered: 0, production: 0, recognition: 0, total: 0)
    }

    func dailyWordCounts(days: Int = 30) -> [DailyCount] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        
        let activityDict = Dictionary(uniqueKeysWithValues: dailyActivities.map { ($0.dateString, $0) })
        
        return (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dateStr = formatter.string(from: date)
            
            if let existing = activityDict[dateStr] {
                return existing
            } else {
                return DailyCount(dateString: dateStr)
            }
        }
    }

    var thisWeekWordCount: Int {
        dailyWordCounts().suffix(7).reduce(0) { $0 + $1.total }
    }
    func cumulativeProgressData() -> [CumulativeProgressEntry] {
        guard
            let targetIndex = Self.cefrLevels.firstIndex(of: targetLevel)
        else {
            return []
        }

        let includedLevels = Set(Self.cefrLevels.prefix(through: targetIndex))
        let eligibleWords = introducedWords.filter { includedLevels.contains($0.level) }
        guard !eligibleWords.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        
        var dailyCounts: [Date: Int] = [:]
        for word in eligibleWords {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: word.learnedDate))
            dailyCounts[day, default: 0] += word.count
        }
        
        let sortedDays = dailyCounts.keys.sorted()
        guard let firstDay = sortedDays.first else { return [] }
        
        var entries: [CumulativeProgressEntry] = []
        var runningTotal = 0
        
        var currentDay = firstDay
        while currentDay <= today {
            runningTotal += dailyCounts[currentDay] ?? 0
            entries.append(CumulativeProgressEntry(date: currentDay, count: runningTotal))
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
        }
        return entries
    }

    func targetWordCount(for level: String) -> Int {
        guard let targetIndex = Self.cefrLevels.firstIndex(of: level) else { return 0 }
        return Self.cefrLevels.prefix(through: targetIndex).reduce(0) { total, level in
            total + statsFor(level: level).total
        }
    }

    func benchmarks(for level: String) -> [(level: String, count: Int)] {
        guard let targetIndex = Self.cefrLevels.firstIndex(of: level) else { return [] }
        var total = 0
        return Self.cefrLevels.prefix(through: targetIndex).map { level in
            total += statsFor(level: level).total
            return (level, total)
        }
    }
}
