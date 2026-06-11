import Foundation
import GRDB

enum WordStage: String, Codable, CaseIterable, Sendable {
    case new
    case skipped
    case recognition
    case production
    case mastered
}

struct UserWord: Identifiable, Sendable, Equatable {
    static let databaseTableName = "userWords"

    var id: Int64?
    var wordId: String
    var word: Word    // populated from JOIN; not persisted directly

    var stage: WordStage
    var easeFactor: Double
    var interval: Int
    var repetitions: Int
    var nextReviewDate: Date
    var lastReviewDate: Date?
    var learnedDate: Date?
    var lastWrongDate: Date?
    var totalCorrect: Int
    var totalAttempts: Int

    nonisolated init(word: Word) {
        self.id = nil
        self.wordId = word.wordId
        self.word = word
        self.stage = .new
        self.easeFactor = 2.5
        self.interval = 1
        self.repetitions = 0
        self.nextReviewDate = .now
        self.totalCorrect = 0
        self.totalAttempts = 0
    }
}

// MARK: - GRDB FetchableRecord (decodes from JOIN query — see DatabaseService.joinSQL)

extension UserWord: FetchableRecord {
    nonisolated init(row: Row) throws {
        id          = row["id"]
        wordId      = row["wordId"]
        stage       = WordStage(rawValue: row["stage"]) ?? .new
        easeFactor  = row["easeFactor"]
        interval    = row["interval"]
        repetitions = row["repetitions"]

        let nextTS: Double = row["nextReviewDate"]
        nextReviewDate = Date(timeIntervalSince1970: nextTS)

        if let ts: Double = row["lastReviewDate"] {
            lastReviewDate = Date(timeIntervalSince1970: ts)
        }
        if let ts: Double = row["learnedDate"] {
            learnedDate = Date(timeIntervalSince1970: ts)
        }
        if let ts: Double = row["lastWrongDate"] {
            lastWrongDate = Date(timeIntervalSince1970: ts)
        }

        totalCorrect  = row["totalCorrect"]
        totalAttempts = row["totalAttempts"]

        word = Word(
            wordId: wordId,
            italian: row["italian"],
            english: row["english"],
            alternatives: Word.decodeAlternatives(row["alternatives"]),
            level: row["level"],
            frequencyRank: row["frequencyRank"],
            isUserCreated: row["isUserCreated"],
            inflections: row["inflections"]
        )
    }
}

// MARK: - GRDB MutablePersistableRecord (persists only userWords columns)

extension UserWord: MutablePersistableRecord {
    nonisolated mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        if let id { container["id"] = id }
        container["wordId"]         = wordId
        container["stage"]          = stage.rawValue
        container["easeFactor"]     = easeFactor
        container["interval"]       = interval
        container["repetitions"]    = repetitions
        container["nextReviewDate"] = nextReviewDate.timeIntervalSince1970
        container["lastReviewDate"] = lastReviewDate?.timeIntervalSince1970
        container["learnedDate"]    = learnedDate?.timeIntervalSince1970
        container["lastWrongDate"]  = lastWrongDate?.timeIntervalSince1970
        container["totalCorrect"]   = totalCorrect
        container["totalAttempts"]  = totalAttempts
    }
}
