import Foundation
import GRDB

struct TenseStat: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "tenseStats"
    
    var tense: String
    var score: Double
    
    init(tense: String, score: Double = 0.5) {
        self.tense = tense
        self.score = score
    }
}

struct ConjugationStat: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "conjugationStats"
    
    var id: Int64?
    var verb: String
    var tense: String
    var pronoun: String
    var score: Double
    var attempts: Int
    
    init(id: Int64? = nil, verb: String, tense: String, pronoun: String, score: Double = 0.5, attempts: Int = 0) {
        self.id = id
        self.verb = verb
        self.tense = tense
        self.pronoun = pronoun
        self.score = score
        self.attempts = attempts
    }
}
