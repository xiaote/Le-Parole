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
    var settings: UserSettings?

    private var statsCancellable: AnyDatabaseCancellable?
    private var settingsCancellable: AnyDatabaseCancellable?

    init() {
        setupObservation()
        
        let db = DatabaseService.shared
        settingsCancellable = db.makeSettingsObservation().start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] s in self?.settings = s }
        )
    }

    private func setupObservation() {
        let db = DatabaseService.shared
        
        statsCancellable = ValueObservation.tracking { db in
            let now = Date.now.timeIntervalSince1970
            let todayStart = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
            let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: .now)?.timeIntervalSince1970 ?? now
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = .current
            let todayKey = dateFormatter.string(from: .now)

            let mastered = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'mastered'") ?? 0
            let inProgress = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage IN ('recognition', 'production')") ?? 0
            let reviewsDue = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage IN ('recognition', 'production', 'mastered') AND nextReviewDate <= ?", arguments: [now]) ?? 0
            let reviewAttemptsToday = try Int.fetchOne(db, sql: "SELECT reviewAttempts FROM dailyActivity WHERE date = ?", arguments: [todayKey]) ?? 0
            let wordsLearnedToday = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE learnedDate >= ?", arguments: [todayStart]) ?? 0
            let newAvailable = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'new'") ?? 0
            
            let mistakesSQL = """
                SELECT uw.id, uw.wordId, uw.stage, uw.easeFactor, uw.interval, uw.repetitions,
                       uw.nextReviewDate, uw.lastReviewDate, uw.learnedDate, uw.lastWrongDate,
                       uw.totalCorrect, uw.totalAttempts,
                       w.italian, w.english, w.alternatives, w.level, w.frequencyRank, w.isUserCreated, w.inflections, w.partOfSpeech
                FROM userWords uw
                JOIN words w ON uw.wordId = w.wordId
                WHERE uw.lastWrongDate >= ?
                ORDER BY w.frequencyRank
                """
            let mistakesToday = try UserWord.fetchAll(db, sql: mistakesSQL, arguments: [todayStart])
            
            let testQueueCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM userWords 
                WHERE stage NOT IN ('mastered', 'skipped')
                AND (lastReviewDate IS NULL OR lastReviewDate < ?)
                AND NOT (stage IN ('recognition', 'production') AND nextReviewDate <= ?)
                """, arguments: [sixDaysAgo, now]) ?? 0

            let recognitionBacklog = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'recognition'") ?? 0

            return HomeStats(
                mastered: mastered,
                inProgress: inProgress,
                reviewsDue: reviewsDue,
                reviewAttemptsToday: reviewAttemptsToday,
                wordsLearnedToday: wordsLearnedToday,
                newAvailable: newAvailable,
                mistakesToday: mistakesToday,
                testQueueCount: testQueueCount,
                recognitionBacklog: recognitionBacklog
            )
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] stats in self?.stats = stats }
        )
    }

    func refresh() async {
        setupObservation()
        // Short delay to allow the async DB read to complete before the refresh spinner dismisses
        try? await Task.sleep(for: .milliseconds(300))
    }

    var dailyPracticeGoal: Int { settings?.dailyPracticeGoal ?? 20 }
    var newWordPacing: Int { settings?.dailyNewWordGoal ?? 20 }

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
    
    private func fetchWords(stageIn: [String]) -> [UserWord] {
        (try? DatabaseService.shared.db.read { db in
            let stages = stageIn.map { "'\($0)'" }.joined(separator: ", ")
            let sql = """
                SELECT uw.id, uw.wordId, uw.stage, uw.easeFactor, uw.interval, uw.repetitions,
                       uw.nextReviewDate, uw.lastReviewDate, uw.learnedDate, uw.lastWrongDate,
                       uw.totalCorrect, uw.totalAttempts,
                       w.italian, w.english, w.alternatives, w.level, w.frequencyRank, w.isUserCreated, w.inflections, w.partOfSpeech
                FROM userWords uw
                JOIN words w ON uw.wordId = w.wordId
                WHERE uw.stage IN (\(stages))
                ORDER BY w.frequencyRank
                """
            return try UserWord.fetchAll(db, sql: sql)
        }) ?? []
    }
    
    func getInProgressWords() -> [UserWord] {
        fetchWords(stageIn: ["recognition", "production"])
    }
    
    func getMasteredWords() -> [UserWord] {
        fetchWords(stageIn: ["mastered"])
    }
}
