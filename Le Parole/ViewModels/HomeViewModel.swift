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
}

@Observable
final class HomeViewModel {
    var stats = HomeStats(mastered: 0, inProgress: 0, reviewsDue: 0, reviewAttemptsToday: 0, wordsLearnedToday: 0, newAvailable: 0, mistakesToday: [], testQueueCount: 0)

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
                    AND NOT (stage IN ('recognition', 'production') AND nextReviewDate <= :now)) AS testQueueCount
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
            testQueueCount: count("testQueueCount")
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

    var newToLearnToday: Int { min(stats.newAvailable, max(0, newWordPacing - stats.wordsLearnedToday)) }
    var dueToday: Int { stats.reviewsDue + newToLearnToday }
    var hasWork: Bool { dueToday > 0 }
    var canStudy: Bool { hasWork || (stats.newAvailable + stats.inProgress + stats.mastered > 0) }

    var sessionAction: String {
        if hasWork {
            return "Start practice"
        } else if stats.newAvailable > 0 {
            return "Keep learning"
        } else if stats.inProgress > 0 || stats.mastered > 0 {
            return "Keep practicing"
        } else {
            return "All caught up"
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
