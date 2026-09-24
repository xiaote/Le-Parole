import Foundation

/// Pure construction of a regular study session's card queue.
nonisolated enum StudyQueueBuilder {
    /// Orders due and new words into one session queue.
    ///
    /// Words needing attention (recognition stage or an unresolved mistake),
    /// learning words (new words alternating with due production words) and
    /// mastered maintenance words are rotated together, then a few ordinary
    /// cards are pulled to the front while conjugation challenges generate.
    static func buildQueue(
        dueWords: [UserWord],
        newWords: [UserWord],
        conjugationAvailable: Bool,
        now: Date = .now
    ) -> [StudyCard] {
        var attentionWords: [UserWord] = []
        var learningWords: [UserWord] = []
        var maintenanceWords: [UserWord] = []

        for userWord in dueWords {
            switch userWord.stage {
            case .recognition:
                attentionWords.append(userWord)
            case .production:
                if hasUnresolvedMistake(userWord) {
                    attentionWords.append(userWord)
                } else {
                    learningWords.append(userWord)
                }
            case .mastered:
                if hasUnresolvedMistake(userWord) {
                    attentionWords.append(userWord)
                } else {
                    maintenanceWords.append(userWord)
                }
            case .new, .skipped:
                break
            }
        }

        attentionWords.sort { isHigherPriority($0, than: $1, now: now) }
        learningWords.sort { isHigherPriority($0, than: $1, now: now) }
        maintenanceWords.sort { isHigherPriority($0, than: $1, now: now) }

        let dueCard = { (userWord: UserWord, intent: StudyCard.SchedulingIntent) in
            makeDueCard(userWord, intent: intent, conjugationAvailable: conjugationAvailable)
        }

        let attentionCards = attentionWords.map { userWord in
            if userWord.stage == .recognition {
                return StudyCard(userWord: userWord, cardType: .recognition)
            }
            let intent: StudyCard.SchedulingIntent =
                hasUnresolvedMistake(userWord) && SM2.isLapseRecoveryCandidate(userWord)
                ? .lapseRecovery
                : .standard
            return dueCard(userWord, intent)
        }
        let newCards = newWords.map { StudyCard(userWord: $0, cardType: .recognition) }
        let learningCards = alternating(newCards, learningWords.map { dueCard($0, .standard) })
        let maintenanceCards = maintenanceWords.map { dueCard($0, .standard) }

        let queue = rotateQueue(
            attention: attentionCards,
            learning: learningCards,
            maintenance: maintenanceCards
        )
        return delayingInitialConjugations(in: queue)
    }

    /// Verbs are practised as conjugation challenges when generation is
    /// available; everything else is a production card.
    static func makeDueCard(
        _ userWord: UserWord,
        intent: StudyCard.SchedulingIntent,
        conjugationAvailable: Bool
    ) -> StudyCard {
        let isVerb = userWord.word.english.lowercased().hasPrefix("to ")
        let type: StudyCard.CardType = conjugationAvailable && isVerb ? .conjugation : .production
        return StudyCard(userWord: userWord, cardType: type, schedulingIntent: intent)
    }

    /// A mistake remains unresolved until the word is subsequently answered
    /// correctly. This uses the existing timestamps, so queue prioritization
    /// does not need another persistence field.
    static func hasUnresolvedMistake(_ userWord: UserWord) -> Bool {
        guard let lastWrong = userWord.lastWrongDate else { return false }
        guard let lastReview = userWord.lastReviewDate else { return true }
        return lastWrong >= lastReview
    }

    /// Unresolved mistakes first, then most overdue, then lowest accuracy,
    /// then most frequent.
    static func isHigherPriority(_ lhs: UserWord, than rhs: UserWord, now: Date) -> Bool {
        let lhsMistake = hasUnresolvedMistake(lhs)
        let rhsMistake = hasUnresolvedMistake(rhs)
        if lhsMistake != rhsMistake { return lhsMistake }

        let lhsOverdue = now.timeIntervalSince(lhs.nextReviewDate)
        let rhsOverdue = now.timeIntervalSince(rhs.nextReviewDate)
        if lhsOverdue != rhsOverdue { return lhsOverdue > rhsOverdue }

        let lhsAccuracy = lhs.totalAttempts == 0 ? 0 : Double(lhs.totalCorrect) / Double(lhs.totalAttempts)
        let rhsAccuracy = rhs.totalAttempts == 0 ? 0 : Double(rhs.totalCorrect) / Double(rhs.totalAttempts)
        if lhsAccuracy != rhsAccuracy { return lhsAccuracy < rhsAccuracy }

        return lhs.word.frequencyRank < rhs.word.frequencyRank
    }

    static func alternating(_ first: [StudyCard], _ second: [StudyCard]) -> [StudyCard] {
        var result: [StudyCard] = []
        result.reserveCapacity(first.count + second.count)
        for index in 0..<max(first.count, second.count) {
            if index < first.count { result.append(first[index]) }
            if index < second.count { result.append(second[index]) }
        }
        return result
    }

    /// Keeps one streamlined session while ensuring that any stopping point
    /// contains a useful mix of attention, learning, and maintenance work.
    /// Each round takes attention, learning, maintenance, learning.
    static func rotateQueue(
        attention: [StudyCard],
        learning: [StudyCard],
        maintenance: [StudyCard]
    ) -> [StudyCard] {
        var result: [StudyCard] = []
        result.reserveCapacity(attention.count + learning.count + maintenance.count)
        var attentionIndex = 0
        var learningIndex = 0
        var maintenanceIndex = 0

        while attentionIndex < attention.count || learningIndex < learning.count || maintenanceIndex < maintenance.count {
            if attentionIndex < attention.count {
                result.append(attention[attentionIndex])
                attentionIndex += 1
            }
            if learningIndex < learning.count {
                result.append(learning[learningIndex])
                learningIndex += 1
            }
            if maintenanceIndex < maintenance.count {
                result.append(maintenance[maintenanceIndex])
                maintenanceIndex += 1
            }
            if learningIndex < learning.count {
                result.append(learning[learningIndex])
                learningIndex += 1
            }
        }
        return result
    }

    /// Conjugation generation is asynchronous. Pulling up to three ordinary
    /// learning cards forward gives it time to finish without allowing mastered
    /// maintenance to displace higher-value work at the start of a session.
    static func delayingInitialConjugations(in queue: [StudyCard]) -> [StudyCard] {
        let initialCards = Array(queue.lazy.filter {
            $0.cardType != .conjugation && $0.userWord.stage != .mastered
        }.prefix(3))
        guard !initialCards.isEmpty else { return queue }
        let initialIDs = Set(initialCards.map(\.id))
        return initialCards + queue.filter { !initialIDs.contains($0.id) }
    }
}
