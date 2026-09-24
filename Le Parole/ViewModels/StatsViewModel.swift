import Foundation
import GRDB

struct DailyCount: Identifiable, FetchableRecord, TableRecord {
    static let databaseTableName = "dailyActivity"
    
    var dateString: String // stored as "date" in db, but we need to map to Date
    var reviewAttempts: Int
    var correctAnswers: Int
    var wordsIntroduced: Int
    var movedToMastered: Int
    
    var total: Int { reviewAttempts }
    var id: String { dateString }
    let date: Date
    
    init(
        dateString: String,
        reviewAttempts: Int = 0,
        correctAnswers: Int = 0,
        wordsIntroduced: Int = 0,
        movedToMastered: Int = 0
    ) {
        self.dateString = dateString
        self.reviewAttempts = reviewAttempts
        self.correctAnswers = correctAnswers
        self.wordsIntroduced = wordsIntroduced
        self.movedToMastered = movedToMastered
        self.date = AppDateFormatter.date(from: dateString) ?? .now
    }
    
    init(row: GRDB.Row) {
        dateString = row["date"]
        reviewAttempts = row["reviewAttempts"]
        correctAnswers = row["correctAnswers"]
        wordsIntroduced = row["wordsIntroduced"]
        movedToMastered = row["movedToMastered"]
        date = AppDateFormatter.date(from: dateString) ?? .now
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

struct CoverageProjection: Equatable {
    let startDate: Date
    let projectedDate: Date
    let currentCount: Int
    let targetCount: Int
    let recentDailyRate: Double
    let sampleDays: Int

    var remainingCount: Int { targetCount - currentCount }
}

struct IntroducedWord: Sendable, Equatable {
    let level: String
    let learnedDate: Double
    let count: Int
}

@Observable
final class StatsViewModel {
    var snapshot = StatsSnapshot() { didSet { updateProgress() } }
    var dailyActivities: [DailyCount] = [] { didSet { updateDailyCounts() } }
    var tenseStats: [TenseStat] = []
    var introducedWords: [IntroducedWord] = [] { didSet { updateProgress() } }

    // Derived values, recomputed only when the observed data above changes.
    private(set) var dailyCounts: [DailyCount] = []
    private(set) var weekTotal = 0
    private(set) var progressEntries: [CumulativeProgressEntry] = []
    private(set) var targetWordCount = 0
    private(set) var benchmarks: [(level: String, count: Int)] = []
    private(set) var coverageProjection: CoverageProjection?

    private var statsCancellable: AnyDatabaseCancellable?
    private var activityCancellable: AnyDatabaseCancellable?
    private var tenseStatsCancellable: AnyDatabaseCancellable?
    private var targetLevelTask: Task<Void, Never>?
    private var introducedWordsCancellable: AnyDatabaseCancellable?

    static let coverageProjectionSampleDays = 7
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
        updateDailyCounts()
    }

    func setObserving(_ shouldObserve: Bool) {
        guard shouldObserve else {
            statsCancellable = nil
            activityCancellable = nil
            tenseStatsCancellable = nil
            targetLevelTask?.cancel()
            targetLevelTask = nil
            introducedWordsCancellable = nil
            return
        }
        guard statsCancellable == nil else { return }

        let db = DatabaseService.shared
        
        statsCancellable = ValueObservation.tracking { db in
            // userWords.wordId references words (cascading), so the per-level
            // rows add up to the overall totals.
            let rows = try Row.fetchAll(db, sql: """
                SELECT w.level,
                       SUM(uw.stage = 'mastered') AS mastered,
                       SUM(uw.stage = 'production') AS production,
                       SUM(uw.stage = 'recognition') AS recognition,
                       SUM(uw.stage = 'new') AS notStarted,
                       SUM(uw.stage = 'skipped') AS skipped,
                       SUM(uw.stage != 'skipped') AS total
                FROM userWords uw
                JOIN words w ON uw.wordId = w.wordId
                GROUP BY w.level
            """)

            var snapshot = StatsSnapshot()
            for row in rows {
                let level = LevelStats(
                    level: row["level"],
                    mastered: row["mastered"],
                    production: row["production"],
                    recognition: row["recognition"],
                    total: row["total"]
                )
                snapshot.levelStats[level.level] = level
                snapshot.mastered += level.mastered
                snapshot.production += level.production
                snapshot.recognition += level.recognition
                snapshot.notStarted += row["notStarted"] as Int
                snapshot.skipped += row["skipped"] as Int
                snapshot.total += level.total
            }
            snapshot.customCategories = Set(snapshot.levelStats.keys).subtracting(Word.cefrLevels).sorted()
            return snapshot
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
        targetLevelTask = Task { [weak self] in
            for await _ in Observations({ @MainActor in SettingsStore.shared.targetLevel }) {
                self?.updateProgress()
            }
        }

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
        get { SettingsStore.shared.targetLevel }
        set { SettingsStore.shared.update { $0.targetLevel = newValue } }
    }

    func statsFor(level: String) -> LevelStats {
        snapshot.levelStats[level] ?? LevelStats(level: level, mastered: 0, production: 0, recognition: 0, total: 0)
    }

    // MARK: - Derived data

    private func updateDailyCounts(days: Int = 30) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let activityDict = Dictionary(uniqueKeysWithValues: dailyActivities.map { ($0.dateString, $0) })

        dailyCounts = (0..<days).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dateStr = AppDateFormatter.string(from: date)
            return activityDict[dateStr] ?? DailyCount(dateString: dateStr)
        }
        weekTotal = dailyCounts.suffix(7).reduce(0) { $0 + $1.total }
    }

    private func updateProgress() {
        guard let targetIndex = Word.cefrLevels.firstIndex(of: targetLevel) else {
            progressEntries = []
            targetWordCount = 0
            benchmarks = []
            coverageProjection = nil
            return
        }
        let includedLevels = Word.cefrLevels.prefix(through: targetIndex)

        var total = 0
        benchmarks = includedLevels.map { level in
            total += statsFor(level: level).total
            return (level, total)
        }
        targetWordCount = total
        progressEntries = cumulativeProgressData(levels: Set(includedLevels))
        coverageProjection = makeCoverageProjection(entries: progressEntries, targetCount: total)
    }

    private func cumulativeProgressData(levels: Set<String>) -> [CumulativeProgressEntry] {
        let eligibleWords = introducedWords.filter { levels.contains($0.level) }
        guard !eligibleWords.isEmpty else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        var dailyCounts: [Date: Int] = [:]
        for word in eligibleWords {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: word.learnedDate))
            dailyCounts[day, default: 0] += word.count
        }

        guard let firstDay = dailyCounts.keys.min() else { return [] }

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

    private func makeCoverageProjection(entries: [CumulativeProgressEntry], targetCount: Int) -> CoverageProjection? {
        let currentCount = entries.last?.count ?? 0
        guard targetCount > currentCount else { return nil }

        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: .now)
        let sampleDays = Self.coverageProjectionSampleDays
        let sampleStart = calendar.date(byAdding: .day, value: -(sampleDays - 1), to: startDate)!
        let countBeforeSample = entries.last(where: { $0.date < sampleStart })?.count ?? 0
        let introducedInSample = currentCount - countBeforeSample
        let recentDailyRate = Double(introducedInSample) / Double(sampleDays)
        guard recentDailyRate > 0 else { return nil }

        let daysNeeded = Int(ceil(Double(targetCount - currentCount) / recentDailyRate))
        guard let projectedDate = calendar.date(byAdding: .day, value: daysNeeded, to: startDate) else {
            return nil
        }

        return CoverageProjection(
            startDate: startDate,
            projectedDate: projectedDate,
            currentCount: currentCount,
            targetCount: targetCount,
            recentDailyRate: recentDailyRate,
            sampleDays: sampleDays
        )
    }
}
