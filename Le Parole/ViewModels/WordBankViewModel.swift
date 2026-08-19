import Foundation
import GRDB

@Observable
final class WordBankViewModel {
    var userWords: [UserWord] = []
    var customLevels: [String] = []
    private(set) var hasMoreResults = false
    private(set) var isLoadingMore = false
    
    var searchText: String = "" { didSet { resetResults() } }
    var showingSkipped: Bool = false { didSet { resetResults() } }
    var selectedLevel: String? = nil { didSet { resetResults() } }
    
    private var cancellable: AnyDatabaseCancellable?
    private var levelsCancellable: AnyDatabaseCancellable?
    private static let pageSize = 250
    private var cursor: ResultCursor?
    private var activeRequestID: UUID?
    private var deliveredRequestID: UUID?

    private struct ResultCursor {
        let frequencyRank: Int
        let userWordID: Int64
    }
    
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
        
        loadNextPage(replacingResults: true)
    }
    
    private func loadNextPage(replacingResults: Bool = false) {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        let text = searchText
        let skipped = showingSkipped
        let level = selectedLevel
        let pageCursor = cursor
        let requestID = UUID()
        let pageStartIndex = replacingResults ? 0 : userWords.count
        activeRequestID = requestID
        
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

            if let pageCursor {
                conditions.append("(w.frequencyRank > ? OR (w.frequencyRank = ? AND uw.id > ?))")
                arguments.append(pageCursor.frequencyRank)
                arguments.append(pageCursor.frequencyRank)
                arguments.append(pageCursor.userWordID)
            }
            
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = "\(baseSQL) \(whereClause) ORDER BY w.frequencyRank, uw.id LIMIT ?"
            arguments.append(Self.pageSize)
            
            return try UserWord.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }.start(
            in: DatabaseService.shared.db,
            scheduling: .async(onQueue: .main),
            onError: { _ in },
            onChange: { [weak self] words in
                guard self?.activeRequestID == requestID else { return }

                if replacingResults {
                    self?.userWords = words
                } else if self?.deliveredRequestID == requestID {
                    self?.userWords.replaceSubrange(pageStartIndex..., with: words)
                } else {
                    self?.userWords.append(contentsOf: words)
                }

                self?.deliveredRequestID = requestID
                self?.cursor = words.last.flatMap { word in
                    guard let id = word.id else { return nil }
                    return ResultCursor(frequencyRank: word.word.frequencyRank, userWordID: id)
                } ?? pageCursor
                self?.hasMoreResults = words.count == Self.pageSize
                self?.isLoadingMore = false
            }
        )
    }

    func loadMoreIfNeeded(after userWordID: Int64?) {
        guard userWordID == userWords.last?.id, hasMoreResults else { return }
        loadNextPage()
    }

    private func resetResults() {
        activeRequestID = UUID()
        isLoadingMore = false
        cursor = nil
        deliveredRequestID = nil
        hasMoreResults = false
        userWords = []
        loadNextPage(replacingResults: true)
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
