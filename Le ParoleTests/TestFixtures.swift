import Foundation
@testable import Le_Parole

enum Fixtures {
    /// A fixed reference instant so scheduled dates are deterministic.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func day(_ offset: Double) -> Date {
        now.addingTimeInterval(offset * 86_400)
    }

    static func word(
        _ italian: String = "casa",
        _ english: String = "house",
        alternatives: [String] = [],
        rank: Int = 1,
        inflections: String? = nil
    ) -> Word {
        Word(
            wordId: "w_\(italian)",
            italian: italian,
            english: english,
            alternatives: alternatives,
            level: "A1",
            frequencyRank: rank,
            inflections: inflections
        )
    }

    static func userWord(
        _ italian: String = "casa",
        _ english: String = "house",
        id: Int64 = 1,
        stage: WordStage = .new,
        interval: Int = 1,
        repetitions: Int = 0,
        easeFactor: Double = 2.5,
        nextReviewDate: Date = Fixtures.now,
        lastReviewDate: Date? = nil,
        lastWrongDate: Date? = nil,
        learnedDate: Date? = nil,
        totalCorrect: Int = 0,
        totalAttempts: Int = 0,
        rank: Int = 1
    ) -> UserWord {
        var userWord = UserWord(word: word(italian, english, rank: rank))
        userWord.id = id
        userWord.stage = stage
        userWord.interval = interval
        userWord.repetitions = repetitions
        userWord.easeFactor = easeFactor
        userWord.nextReviewDate = nextReviewDate
        userWord.lastReviewDate = lastReviewDate
        userWord.lastWrongDate = lastWrongDate
        userWord.learnedDate = learnedDate ?? (stage == .new ? nil : day(-30))
        userWord.totalCorrect = totalCorrect
        userWord.totalAttempts = totalAttempts
        return userWord
    }

    static func card(
        _ italian: String,
        _ english: String = "thing",
        stage: WordStage = .production,
        type: StudyCard.CardType = .production
    ) -> StudyCard {
        StudyCard(userWord: userWord(italian, english, stage: stage), cardType: type)
    }
}

extension ReviewOutcome {
    /// ReviewOutcome is not Equatable; compare a readable description instead.
    var summary: String {
        switch self {
        case .stageChanged(let from, let to): "stage \(from.rawValue)->\(to.rawValue)"
        case .lapseRecovered(let feedback): "lapseRecovered \(feedback.title) | \(feedback.detail)"
        case .reviewScheduled(let feedback): "reviewScheduled \(feedback.title) | \(feedback.detail)"
        case .none: "none"
        }
    }
}
