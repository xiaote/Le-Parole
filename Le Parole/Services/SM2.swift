import Foundation

struct SM2Result {
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
}

enum SM2 {
    // Words with SM-2 interval >= this threshold are considered mastered.
    static let masteryThreshold = 21
    static let acceleratedMasteryInterval = 30

    /// Evaluates a production-stage review and returns updated SM-2 values.
    static func evaluate(userWord: UserWord, correct: Bool) -> SM2Result {
        guard correct else {
            return SM2Result(
                interval: 1,
                easeFactor: max(1.3, userWord.easeFactor - 0.2),
                repetitions: 0
            )
        }

        let newRepetitions = userWord.repetitions + 1
        let newInterval: Int
        switch userWord.repetitions {
        case 0:  newInterval = 1
        case 1:  newInterval = 6
        default:
            let streakMultiplier: Double
            switch newRepetitions {
            case 8...: streakMultiplier = 1.5
            case 5...: streakMultiplier = 1.3
            case 3...: streakMultiplier = 1.15
            default: streakMultiplier = 1.0
            }
            newInterval = max(
                userWord.interval + 1,
                Int(round(Double(userWord.interval) * userWord.easeFactor * streakMultiplier))
            )
        }
        let stabilityGain = newRepetitions >= 5 ? 0.05 : 0
        let newEaseFactor = min(3.0, max(1.3, userWord.easeFactor + stabilityGain))

        return SM2Result(interval: newInterval, easeFactor: newEaseFactor, repetitions: newRepetitions)
    }

    /// Used only after a brand-new word is recalled in both recognition and
    /// production during the same session. The next review still verifies
    /// retention, but avoids the ordinary 1- and 6-day onboarding sequence.
    static func acceleratedMastery(for userWord: UserWord) -> SM2Result {
        SM2Result(
            interval: acceleratedMasteryInterval,
            easeFactor: max(2.5, userWord.easeFactor),
            repetitions: max(3, userWord.repetitions)
        )
    }

    static func nextReviewDate(interval: Int) -> Date {
        let future = Calendar.current.date(byAdding: .day, value: interval, to: .now) ?? .now
        return Calendar.current.startOfDay(for: future)
    }
}
