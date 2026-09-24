import Foundation

nonisolated struct ReviewScheduleFeedback: Sendable {
    let title: String
    let detail: String
}

nonisolated enum ReviewOutcome: Sendable {
    case stageChanged(from: WordStage, to: WordStage)
    case lapseRecovered(ReviewScheduleFeedback)
    case reviewScheduled(ReviewScheduleFeedback)
    case none
}

/// The result of scheduling one answered card.
nonisolated struct ReviewResult: Sendable {
    /// The word with attempt counters, review dates, stage and SM-2 values updated.
    let userWord: UserWord
    let outcome: ReviewOutcome
    /// The word was introduced (given a learned date) by this answer.
    let introduced: Bool
    let movedToProduction: Bool
    /// The word newly reached mastery. Recovering a lapse does not count.
    let movedToMastered: Bool
    /// A recognition card was answered correctly (a session "graduation").
    let graduated: Bool
    /// A brand-new word was recognised at first sight; confirm it with a
    /// production card later in the session.
    let needsFamiliarityConfirmation: Bool
}

/// Pure answer scheduling: given a card's word and the answer, computes the
/// word's next state. Has no side effects, so the caller persists the result.
nonisolated enum ReviewScheduler {
    static func schedule(
        _ userWord: UserWord,
        cardType: StudyCard.CardType,
        intent: StudyCard.SchedulingIntent,
        correct: Bool,
        isTestMode: Bool,
        now: Date = .now
    ) -> ReviewResult {
        let stageBefore = userWord.stage
        let wasIntroduced = userWord.learnedDate != nil
        var word = userWord

        word.totalAttempts += 1
        if correct { word.totalCorrect += 1 }
        word.lastReviewDate = now
        if !correct { word.lastWrongDate = now }

        var graduated = false
        var needsFamiliarityConfirmation = false

        if isTestMode {
            scheduleTestAnswer(&word, correct: correct, now: now)
        } else {
            switch cardType {
            case .recognition:
                if correct {
                    word.learnedDate = word.learnedDate ?? now
                    word.stage = .production
                    apply(SM2.evaluate(userWord: word, correct: true), to: &word, now: now)
                    graduated = true
                    needsFamiliarityConfirmation = stageBefore == .new
                } else {
                    if word.stage == .new {
                        word.learnedDate = now
                        word.stage = .recognition
                    }
                    word.nextReviewDate = SM2.nextReviewDate(interval: 1, from: now)
                }

            case .production, .conjugation:
                scheduleProductionAnswer(&word, intent: intent, correct: correct, now: now)
            }
        }

        let didTransitionToMastered = stageBefore != .mastered && word.stage == .mastered

        let outcome: ReviewOutcome
        if intent == .lapseRecovery, correct, didTransitionToMastered {
            outcome = .lapseRecovered(feedback(forInterval: word.interval))
        } else if stageBefore != word.stage {
            outcome = .stageChanged(from: stageBefore, to: word.stage)
        } else if correct, stageBefore == .mastered, word.stage == .mastered {
            outcome = .reviewScheduled(feedback(forInterval: word.interval))
        } else {
            outcome = .none
        }

        return ReviewResult(
            userWord: word,
            outcome: outcome,
            introduced: !wasIntroduced && word.learnedDate != nil,
            movedToProduction: stageBefore != .production && stageBefore != .mastered && word.stage == .production,
            movedToMastered: intent != .lapseRecovery && didTransitionToMastered,
            graduated: graduated,
            needsFamiliarityConfirmation: needsFamiliarityConfirmation
        )
    }

    /// Test mode checks whether a word is already known: a correct answer
    /// masters it outright, a wrong one leaves it to the normal schedule.
    private static func scheduleTestAnswer(_ word: inout UserWord, correct: Bool, now: Date) {
        if correct {
            word.stage = .mastered
            word.learnedDate = word.learnedDate ?? now
            word.interval = SM2.masteryThreshold
            word.repetitions = 1
            word.easeFactor = 2.5
            word.nextReviewDate = SM2.nextReviewDate(interval: SM2.masteryThreshold, from: now)
        } else if word.stage != .new {
            word.nextReviewDate = SM2.nextReviewDate(interval: 1, from: now)
        }
    }

    private static func scheduleProductionAnswer(
        _ word: inout UserWord,
        intent: StudyCard.SchedulingIntent,
        correct: Bool,
        now: Date
    ) {
        let isMasteredLapse = !correct && word.stage == .mastered
        let result: SM2Result
        if intent == .familiarityConfirmation && correct {
            result = SM2.acceleratedMastery(for: word)
        } else if intent == .lapseRecovery && correct {
            result = SM2.completeLapseRecovery(for: word)
        } else if isMasteredLapse {
            result = SM2.beginLapseRecovery(for: word)
        } else {
            result = SM2.evaluate(userWord: word, correct: correct)
        }
        apply(result, to: &word, now: now)

        if isMasteredLapse {
            word.nextReviewDate = SM2.nextReviewDate(interval: SM2.lapseReviewDelay, from: now)
            word.stage = .production
        } else if correct && result.interval >= SM2.masteryThreshold {
            word.stage = .mastered
        }
    }

    private static func apply(_ result: SM2Result, to word: inout UserWord, now: Date) {
        word.interval = result.interval
        word.easeFactor = result.easeFactor
        word.repetitions = result.repetitions
        word.nextReviewDate = SM2.nextReviewDate(interval: result.interval, from: now)
    }

    static func feedback(forInterval interval: Int) -> ReviewScheduleFeedback {
        let title: String
        switch interval {
        case ...1: title = "Nice start"
        case 2...6: title = "Getting familiar"
        case 7...20: title = "Coming along"
        case 21...59: title = "You know this"
        case 60...179: title = "Sticking with you"
        default: title = "Second nature"
        }

        let duration: String
        switch interval {
        case ..<14:
            duration = interval == 1 ? "1 day" : "\(interval) days"
        case ..<60:
            let weeks = max(2, Int(round(Double(interval) / 7)))
            duration = "\(weeks) weeks"
        case ..<365:
            let months = max(2, Int(round(Double(interval) / 30)))
            duration = "\(months) months"
        default:
            let years = max(1, Int(round(Double(interval) / 365)))
            duration = years == 1 ? "1 year" : "\(years) years"
        }
        return ReviewScheduleFeedback(title: title, detail: "See it again in \(duration)")
    }
}
