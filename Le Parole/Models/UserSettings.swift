import Foundation
import GRDB

struct UserSettings: Identifiable, Sendable {
    static let databaseTableName = "userSettings"

    var id: Int64?
    var dailyPracticeGoal: Int
    var dailyNewWordGoal: Int
    var autoPlayPronunciation: Bool
    var conjugationLevel: Int
    var geminiApiKey: String
    var targetLevel: String

    init(dailyPracticeGoal: Int = 20, dailyNewWordGoal: Int = 20, autoPlayPronunciation: Bool = true, conjugationLevel: Int = 1, geminiApiKey: String = "", targetLevel: String = "None") {
        self.dailyPracticeGoal = dailyPracticeGoal
        self.dailyNewWordGoal = dailyNewWordGoal
        self.autoPlayPronunciation = autoPlayPronunciation
        self.conjugationLevel = conjugationLevel
        self.geminiApiKey = geminiApiKey
        self.targetLevel = targetLevel
    }
}

extension UserSettings: FetchableRecord {
    nonisolated init(row: Row) throws {
        id                    = row["id"]
        dailyPracticeGoal     = row["dailyPracticeGoal"]
        dailyNewWordGoal      = row["dailyNewWordGoal"]
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
        container["dailyPracticeGoal"] = dailyPracticeGoal
        container["dailyNewWordGoal"] = dailyNewWordGoal
        container["autoPlayPronunciation"] = autoPlayPronunciation
        container["conjugationLevel"] = conjugationLevel
        container["geminiApiKey"] = geminiApiKey
        container["targetLevel"] = targetLevel
    }
}
