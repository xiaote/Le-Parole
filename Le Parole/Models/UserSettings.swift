import Foundation
import GRDB

struct UserSettings: Identifiable, Sendable {
    static let databaseTableName = "userSettings"

    var id: Int64?
    var dailyNewWordGoal: Int
    var extraConjugationCards: Int
    var autoPlayPronunciation: Bool
    var conjugationLevel: Int
    var geminiApiKey: String
    var targetLevel: String

    init(dailyNewWordGoal: Int = 20, extraConjugationCards: Int = 2, autoPlayPronunciation: Bool = true, conjugationLevel: Int = 1, geminiApiKey: String = "", targetLevel: String = "None") {
        self.dailyNewWordGoal = dailyNewWordGoal
        self.extraConjugationCards = extraConjugationCards
        self.autoPlayPronunciation = autoPlayPronunciation
        self.conjugationLevel = conjugationLevel
        self.geminiApiKey = geminiApiKey
        self.targetLevel = targetLevel
    }
}

extension UserSettings: FetchableRecord {
    nonisolated init(row: Row) throws {
        id                    = row["id"]
        dailyNewWordGoal      = row["dailyNewWordGoal"]
        extraConjugationCards = row["extraConjugationCards"]
        autoPlayPronunciation = row["autoPlayPronunciation"]
        conjugationLevel      = row["conjugationLevel"]
        geminiApiKey          = row["geminiApiKey"] ?? ""
        targetLevel           = row["targetLevel"] ?? "None"
    }
}

extension UserSettings: MutablePersistableRecord {
    nonisolated mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    nonisolated func encode(to container: inout PersistenceContainer) throws {
        if let id { container["id"] = id }
        container["dailyNewWordGoal"] = dailyNewWordGoal
        container["extraConjugationCards"] = extraConjugationCards
        container["autoPlayPronunciation"] = autoPlayPronunciation
        container["conjugationLevel"] = conjugationLevel
        container["geminiApiKey"] = geminiApiKey
        container["targetLevel"] = targetLevel
    }
}
