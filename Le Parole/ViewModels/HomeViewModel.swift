import Foundation
import GRDB

struct HomeStats: Equatable, Sendable {
    var mastered: Int
    var inProgress: Int
    var reviewsDue: Int
    var reviewAttemptsToday: Int
    var wordsLearnedToday: Int
    var newAvailable: Int
    var mistakesToday: [UserWord]
    var testQueueCount: Int
    var recognitionBacklog: Int
}

@Observable
final class HomeViewModel {
    var stats = HomeStats(mastered: 0, inProgress: 0, reviewsDue: 0, reviewAttemptsToday: 0, wordsLearnedToday: 0, newAvailable: 0, mistakesToday: [], testQueueCount: 0, recognitionBacklog: 0)

    private let settings = SettingsStore.shared
    private var statsCancellable: AnyDatabaseCancellable?

    init() {
        setObserving(true)
    }

    func setObserving(_ shouldObserve: Bool) {
        guard shouldObserve else {
            statsCancellable = nil
            return
        }
        guard statsCancellable == nil else { return }

        statsCancellable = ValueObservation.tracking(Self.fetchStats).start(
            in: DatabaseService.shared.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] stats in self?.stats = stats }
        )
    }

    private nonisolated static func fetchStats(_ db: Database) throws -> HomeStats {
        let now = Date.now.timeIntervalSince1970
        let todayStart = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: .now)?.timeIntervalSince1970 ?? now
        let todayKey = AppDateFormatter.string(from: .now)

        let counts = try Row.fetchOne(db, sql: """
            SELECT
                SUM(stage = 'mastered') AS mastered,
                SUM(stage IN ('recognition', 'production')) AS inProgress,
                SUM(stage IN ('recognition', 'production', 'mastered') AND nextReviewDate <= :now) AS reviewsDue,
                SUM(learnedDate >= :todayStart) AS wordsLearnedToday,
                SUM(stage = 'new') AS newAvailable,
                SUM(stage NOT IN ('mastered', 'skipped')
                    AND (lastReviewDate IS NULL OR lastReviewDate < :sixDaysAgo)
                    AND NOT (stage IN ('recognition', 'production') AND nextReviewDate <= :now)) AS testQueueCount,
                SUM(stage = 'recognition') AS recognitionBacklog
            FROM userWords
            """, arguments: ["now": now, "todayStart": todayStart, "sixDaysAgo": sixDaysAgo])
        func count(_ column: String) -> Int { (counts?[column] as Int?) ?? 0 }

        let reviewAttemptsToday = try Int.fetchOne(db, sql: "SELECT reviewAttempts FROM dailyActivity WHERE date = ?", arguments: [todayKey]) ?? 0
        let mistakesToday = try UserWord.fetchAll(db, sql: """
            \(DatabaseService.userWordSelectSQL)
            WHERE uw.lastWrongDate >= ?
            ORDER BY w.frequencyRank
            """, arguments: [todayStart])

        return HomeStats(
            mastered: count("mastered"),
            inProgress: count("inProgress"),
            reviewsDue: count("reviewsDue"),
            reviewAttemptsToday: reviewAttemptsToday,
            wordsLearnedToday: count("wordsLearnedToday"),
            newAvailable: count("newAvailable"),
            mistakesToday: mistakesToday,
            testQueueCount: count("testQueueCount"),
            recognitionBacklog: count("recognitionBacklog")
        )
    }

    /// Re-reads time-dependent counts (e.g. reviews that became due) that the
    /// observation only recomputes when the database changes.
    func refresh() async {
        if let stats = try? await DatabaseService.shared.db.read(Self.fetchStats) {
            self.stats = stats
        }
    }

    var dailyPracticeGoal: Int { settings.dailyPracticeGoal }
    var newWordPacing: Int { settings.dailyNewWordGoal }

    var mastered: Int { stats.mastered }
    var inProgress: Int { stats.inProgress }
    var reviewsDue: Int { stats.reviewsDue }
    var reviewAttemptsToday: Int { stats.reviewAttemptsToday }
    var wordsLearnedToday: Int { stats.wordsLearnedToday }
    var newAvailable: Int { stats.newAvailable }
    var mistakesToday: [UserWord] { stats.mistakesToday }
    var testQueueCount: Int { stats.testQueueCount }

    var newToLearnToday: Int { min(newAvailable, max(0, newWordPacing - wordsLearnedToday)) }
    var dueToday: Int { reviewsDue + newToLearnToday }
    var hasWork: Bool { dueToday > 0 }
    var canLearnMore: Bool { dueToday == 0 && newAvailable > 0 }
    var canStudy: Bool { hasWork || (newAvailable + inProgress + mastered > 0) }

    var sessionAction: String {
        if hasWork {
            return "Start practice"
        } else if newAvailable > 0 {
            return "Keep learning"
        } else if inProgress > 0 || mastered > 0 {
            return "Keep practicing"
        } else {
            return "All caught up"
        }
    }
    
    var recognitionBacklog: Int { stats.recognitionBacklog }
    
    var extraSessionDailyLimit: Int {
        // If the backlog of unrecognized words is high (>= 1.5x new-word pace),
        // don't introduce new words in the extra session. Just drill the backlog.
        if recognitionBacklog >= Int(Double(newWordPacing) * 1.5) {
            return wordsLearnedToday
        } else {
            return wordsLearnedToday + newWordPacing
        }
    }

    private func fetchWords(stageIn stages: [WordStage]) async -> [UserWord] {
        (try? await DatabaseService.shared.db.read { db in
            try UserWord.fetchAll(db, sql: """
                \(DatabaseService.userWordSelectSQL)
                WHERE uw.stage IN (\(databaseQuestionMarks(count: stages.count)))
                ORDER BY w.frequencyRank
                """, arguments: StatementArguments(stages.map(\.rawValue)))
        }) ?? []
    }

    func getInProgressWords() async -> [UserWord] {
        await fetchWords(stageIn: [.recognition, .production])
    }

    func getMasteredWords() async -> [UserWord] {
        await fetchWords(stageIn: [.mastered])
    }
}
