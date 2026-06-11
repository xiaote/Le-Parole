import Foundation

struct SM2Result {
    let interval: Int
    let easeFactor: Double
    let repetitions: Int
}

enum SM2 {
    // Words with SM-2 interval >= this threshold are considered mastered.
    static let masteryThreshold = 21

    /// Evaluates a production-stage review and returns updated SM-2 values.
    static func evaluate(userWord: UserWord, correct: Bool) -> SM2Result {
        guard correct else {
            return SM2Result(interval: 1, easeFactor: userWord.easeFactor, repetitions: 0)
        }

        let grade = 4
        let newRepetitions = userWord.repetitions + 1
        let newInterval: Int
        switch userWord.repetitions {
        case 0:  newInterval = 1
        case 1:  newInterval = 6
        default: newInterval = Int(round(Double(userWord.interval) * userWord.easeFactor))
        }
        let delta = 0.1 - Double(5 - grade) * (0.08 + Double(5 - grade) * 0.02)
        let newEaseFactor = max(1.3, userWord.easeFactor + delta)

        return SM2Result(interval: newInterval, easeFactor: newEaseFactor, repetitions: newRepetitions)
    }

    static func nextReviewDate(interval: Int) -> Date {
        let future = Calendar.current.date(byAdding: .day, value: interval, to: .now) ?? .now
        return Calendar.current.startOfDay(for: future)
    }
}
