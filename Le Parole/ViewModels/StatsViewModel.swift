import Foundation
import GRDB

struct DailyCount: Identifiable, FetchableRecord, TableRecord {
    static let databaseTableName = "dailyActivity"
    
    var dateString: String // stored as "date" in db, but we need to map to Date
    var recognition: Int
    var production: Int
    var mastered: Int
    
    var total: Int { recognition + production + mastered }
    var id: String { dateString }
    
    var date: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString) ?? .now
    }
    
    init(dateString: String, recognition: Int, production: Int, mastered: Int) {
        self.dateString = dateString
        self.recognition = recognition
        self.production = production
        self.mastered = mastered
    }
    
    init(row: GRDB.Row) {
        dateString = row["date"]
        recognition = row["recognition"]
        production = row["production"]
        mastered = row["mastered"]
    }
}

struct LevelStats: Equatable, Sendable {
    var level: String
    var mastered: Int
    var production: Int
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
    let id = UUID()
    let date: Date
    let count: Int
    let isProjected: Bool
}

@Observable
final class StatsViewModel {
    var snapshot = StatsSnapshot()
    var dailyActivities: [DailyCount] = []
    var tenseStats: [TenseStat] = []
    var settings: UserSettings?
    var learnedDates: [Double] = []

    private var statsCancellable: AnyDatabaseCancellable?
    private var activityCancellable: AnyDatabaseCancellable?
    private var tenseStatsCancellable: AnyDatabaseCancellable?
    private var settingsCancellable: AnyDatabaseCancellable?
    private var learnedDatesCancellable: AnyDatabaseCancellable?

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
            try TenseStat.fetchAll(db, sql: "SELECT * FROM tenseStats ORDER BY score DESC")
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] stats in self?.tenseStats = stats }
        )
        
        learnedDatesCancellable = ValueObservation.tracking { db in
            try Double.fetchAll(db, sql: "SELECT learnedDate FROM userWords WHERE learnedDate IS NOT NULL ORDER BY learnedDate ASC")
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] dates in self?.learnedDates = dates }
        )
    }

    var targetLevel: String {
        get { settings?.targetLevel ?? "None" }
        set {
            guard var s = settings else { return }
            s.targetLevel = newValue
            Task.detached {
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

    var dailyGoal: Int { settings?.dailyNewWordGoal ?? 20 }

    var customCategories: [String] { snapshot.customCategories }

    func statsFor(level: String) -> LevelStats {
        snapshot.levelStats[level] ?? LevelStats(level: level, mastered: 0, production: 0, total: 0)
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
                return DailyCount(dateString: dateStr, recognition: 0, production: 0, mastered: 0)
            }
        }
    }

    var thisWeekWordCount: Int {
        dailyWordCounts().suffix(7).reduce(0) { $0 + $1.total }
    }

    func cumulativeProgressData() -> [CumulativeProgressEntry] {
        guard !learnedDates.isEmpty else { return [] }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        
        var dailyCounts: [Date: Int] = [:]
        for ts in learnedDates {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: ts))
            dailyCounts[day, default: 0] += 1
        }
        
        let sortedDays = dailyCounts.keys.sorted()
        guard let firstDay = sortedDays.first else { return [] }
        
        var entries: [CumulativeProgressEntry] = []
        var runningTotal = 0
        
        var currentDay = firstDay
        while currentDay <= today {
            runningTotal += dailyCounts[currentDay] ?? 0
            entries.append(CumulativeProgressEntry(date: currentDay, count: runningTotal, isProjected: false))
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay)!
        }
        
        if targetLevel != "None" {
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
            let count7DaysAgo: Int
            let daysForVelocity: Double
            if let entry = entries.last(where: { $0.date <= sevenDaysAgo }) {
                count7DaysAgo = entry.count
                daysForVelocity = 7.0
            } else {
                count7DaysAgo = 0
                daysForVelocity = max(1.0, Double(entries.count))
            }
            let learnedInPast7Days = runningTotal - count7DaysAgo
            let velocity = Double(learnedInPast7Days) / daysForVelocity
            
            if velocity > 0 {
                let targetLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
                var totalTargetWords = 0
                for lvl in targetLevels {
                    totalTargetWords += statsFor(level: lvl).total
                    if lvl == targetLevel { break }
                }
                
                if runningTotal < totalTargetWords {
                    // Start projection from the current day to connect the lines
                    entries.append(CumulativeProgressEntry(date: today, count: runningTotal, isProjected: true))
                    
                    var projDate = calendar.date(byAdding: .day, value: 1, to: today)!
                    var projTotal = Double(runningTotal)
                    var futureDays = 0
                    
                    while projTotal < Double(totalTargetWords) && futureDays < 730 { // 2 years max
                        futureDays += 1
                        projTotal += velocity
                        if projTotal >= Double(totalTargetWords) {
                            entries.append(CumulativeProgressEntry(date: projDate, count: totalTargetWords, isProjected: true))
                            break
                        } else {
                            entries.append(CumulativeProgressEntry(date: projDate, count: Int(projTotal), isProjected: true))
                        }
                        projDate = calendar.date(byAdding: .day, value: 1, to: projDate)!
                    }
                }
            }
        }
        
        return entries
    }
}
