import Foundation
import GRDB

@Observable
final class WordBankViewModel {
    var userWords: [UserWord] = []
    var customLevels: [String] = []
    
    var searchText: String = "" { didSet { updateObservation() } }
    var showingSkipped: Bool = false { didSet { updateObservation() } }
    var selectedLevel: String? = nil { didSet { updateObservation() } }
    
    private var cancellable: AnyDatabaseCancellable?
    private var levelsCancellable: AnyDatabaseCancellable?
    
    init() {
        let db = DatabaseService.shared
        
        levelsCancellable = ValueObservation.tracking { db in
            let levels = try String.fetchAll(db, sql: "SELECT DISTINCT level FROM words")
            let builtIn: Set<String> = ["A1", "A2", "B1", "B2", "C1", "C2"]
            return Set(levels).subtracting(builtIn).sorted()
        }.start(
            in: db.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] levels in self?.customLevels = levels }
        )
        
        updateObservation()
    }
    
    private func updateObservation() {
        let text = searchText
        let skipped = showingSkipped
        let level = selectedLevel
        
        cancellable = ValueObservation.tracking { db in
            let baseSQL = """
                SELECT uw.id, uw.wordId, uw.stage, uw.easeFactor, uw.interval, uw.repetitions,
                       uw.nextReviewDate, uw.lastReviewDate, uw.learnedDate, uw.lastWrongDate,
                       uw.totalCorrect, uw.totalAttempts,
                       w.italian, w.english, w.alternatives, w.level, w.frequencyRank, w.isUserCreated, w.inflections, w.partOfSpeech
                FROM userWords uw
                JOIN words w ON uw.wordId = w.wordId
                """
            var conditions: [String] = []
            var arguments: [DatabaseValueConvertible] = []
            
            if skipped {
                conditions.append("uw.stage = 'skipped'")
            } else {
                conditions.append("uw.stage != 'skipped'")
            }
            
            if let level {
                conditions.append("w.level = ?")
                arguments.append(level)
            }
            
            if !text.isEmpty {
                conditions.append("(w.italian LIKE ? OR w.english LIKE ?)")
                arguments.append("%\(text)%")
                arguments.append("%\(text)%")
            }
            
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = "\(baseSQL) \(whereClause) ORDER BY w.frequencyRank"
            
            return try UserWord.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }.start(
            in: DatabaseService.shared.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] words in self?.userWords = words }
        )
    }

    func applyStage(_ stage: WordStage, to ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        Task.detached {
            try? DatabaseService.shared.db.write { db in
                for id in ids {
                    try db.execute(
                        sql: "UPDATE userWords SET stage = ? WHERE id = ?",
                        arguments: [stage.rawValue, id]
                    )
                    if stage == .new {
                        try db.execute(
                            sql: """
                                UPDATE userWords
                                SET nextReviewDate = ?, interval = 1, repetitions = 0, easeFactor = 2.5
                                WHERE id = ?
                                """,
                            arguments: [Date.now.timeIntervalSince1970, id]
                        )
                    }
                }
            }
        }
    }
}
