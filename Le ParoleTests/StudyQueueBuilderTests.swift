import Foundation
import Testing
@testable import Le_Parole

@Suite("StudyQueueBuilder")
struct StudyQueueBuilderTests {
    let now = Fixtures.now

    private func names(_ cards: [StudyCard]) -> [String] {
        cards.map(\.userWord.word.italian)
    }

    @Test("Unresolved mistake detection", arguments: [
        // (lastWrong offset, lastReview offset, unresolved)
        (nil, nil, false),
        (-1.0, nil, true),
        (-1.0, -1.0, true),   // wrong on the latest review
        (-1.0, -2.0, true),
        (-2.0, -1.0, false),  // answered correctly since
    ] as [(Double?, Double?, Bool)])
    func unresolvedMistake(wrong: Double?, review: Double?, expected: Bool) {
        let word = Fixtures.userWord(
            stage: .production,
            lastReviewDate: review.map { Fixtures.day($0) },
            lastWrongDate: wrong.map { Fixtures.day($0) }
        )
        #expect(StudyQueueBuilder.hasUnresolvedMistake(word) == expected)
    }

    @Test func priorityOrdersMistakesThenOverdueThenAccuracyThenFrequency() {
        let mistake = Fixtures.userWord("a", id: 1, stage: .production, nextReviewDate: now,
                                        lastReviewDate: Fixtures.day(-2), lastWrongDate: Fixtures.day(-2))
        let overdue = Fixtures.userWord("b", id: 2, stage: .production, nextReviewDate: Fixtures.day(-5))
        let inaccurate = Fixtures.userWord("c", id: 3, stage: .production, totalCorrect: 1, totalAttempts: 4)
        let accurate = Fixtures.userWord("d", id: 4, stage: .production, totalCorrect: 4, totalAttempts: 4, rank: 1)
        let accurateRare = Fixtures.userWord("e", id: 5, stage: .production, totalCorrect: 4, totalAttempts: 4, rank: 900)

        let sorted = [accurateRare, accurate, inaccurate, overdue, mistake]
            .sorted { StudyQueueBuilder.isHigherPriority($0, than: $1, now: now) }
        #expect(sorted.map(\.word.italian) == ["a", "b", "c", "d", "e"])
    }

    @Test func unresolvedMistakesComeFirst() {
        let overdue = Fixtures.userWord("overdue", id: 1, stage: .production, nextReviewDate: Fixtures.day(-10))
        let missed = Fixtures.userWord("missed", id: 2, stage: .production, nextReviewDate: now,
                                       lastReviewDate: Fixtures.day(-1), lastWrongDate: Fixtures.day(-1))
        let queue = StudyQueueBuilder.buildQueue(
            dueWords: [overdue, missed], newWords: [], conjugationAvailable: false, now: now
        )
        #expect(names(queue) == ["missed", "overdue"])
    }

    @Test func recognitionAndNewWordsBecomeRecognitionCards() {
        let recognition = Fixtures.userWord("rec", id: 1, stage: .recognition)
        let new = Fixtures.userWord("nuovo", id: 2, stage: .new)
        let production = Fixtures.userWord("prod", id: 3, stage: .production)
        let queue = StudyQueueBuilder.buildQueue(
            dueWords: [recognition, production], newWords: [new], conjugationAvailable: false, now: now
        )
        let types = Dictionary(uniqueKeysWithValues: queue.map { ($0.userWord.word.italian, $0.cardType) })
        #expect(types == ["rec": .recognition, "nuovo": .recognition, "prod": .production])
    }

    @Test func newAndSkippedDueWordsAreIgnored() {
        let queue = StudyQueueBuilder.buildQueue(
            dueWords: [Fixtures.userWord("a", stage: .new), Fixtures.userWord("b", stage: .skipped)],
            newWords: [], conjugationAvailable: true, now: now
        )
        #expect(queue.isEmpty)
    }

    @Test("Verbs become conjugation cards only when generation is available", arguments: [
        ("to go", true, StudyCard.CardType.conjugation),
        ("to go", false, .production),
        ("To Eat", true, .conjugation),
        ("house", true, .production),
    ])
    func verbCardType(english: String, available: Bool, expected: StudyCard.CardType) {
        let word = Fixtures.userWord("parola", english, stage: .production)
        let card = StudyQueueBuilder.makeDueCard(word, intent: .standard, conjugationAvailable: available)
        #expect(card.cardType == expected)

        let queue = StudyQueueBuilder.buildQueue(dueWords: [word], newWords: [], conjugationAvailable: available, now: now)
        #expect(queue.map(\.cardType) == [expected])
    }

    @Test func mistakenLapseCandidateGetsLapseRecoveryIntent() {
        let lapsed = Fixtures.userWord("lapsed", id: 1, stage: .production, interval: 10, repetitions: 3,
                                       lastReviewDate: Fixtures.day(-1), lastWrongDate: Fixtures.day(-1))
        let ordinary = Fixtures.userWord("ordinary", id: 2, stage: .production, interval: 10, repetitions: 3,
                                         lastReviewDate: Fixtures.day(-1))
        let queue = StudyQueueBuilder.buildQueue(dueWords: [lapsed, ordinary], newWords: [], conjugationAvailable: false, now: now)
        let intents = Dictionary(uniqueKeysWithValues: queue.map { ($0.userWord.word.italian, $0.schedulingIntent) })
        #expect(intents == ["lapsed": .lapseRecovery, "ordinary": .standard])
    }

    @Test func alternatingInterleavesThenAppendsRemainder() {
        let result = StudyQueueBuilder.alternating(
            ["n1", "n2", "n3"].map { Fixtures.card($0) },
            [Fixtures.card("d1")]
        )
        #expect(names(result) == ["n1", "d1", "n2", "n3"])
    }

    @Test func rotationTakesAttentionLearningMaintenanceLearning() {
        let result = StudyQueueBuilder.rotateQueue(
            attention: ["a1", "a2"].map { Fixtures.card($0) },
            learning: ["l1", "l2", "l3", "l4", "l5"].map { Fixtures.card($0) },
            maintenance: ["m1"].map { Fixtures.card($0, stage: .mastered) }
        )
        #expect(names(result) == ["a1", "l1", "m1", "l2", "a2", "l3", "l4", "l5"])
    }

    @Test func firstThreeOrdinaryCardsArePulledAheadOfConjugations() {
        let queue = [
            Fixtures.card("c1", type: .conjugation),
            Fixtures.card("m1", stage: .mastered),
            Fixtures.card("c2", type: .conjugation),
            Fixtures.card("p1"),
            Fixtures.card("r1", stage: .recognition, type: .recognition),
            Fixtures.card("p2"),
            Fixtures.card("p3"),
        ]
        let result = StudyQueueBuilder.delayingInitialConjugations(in: queue)
        #expect(names(result) == ["p1", "r1", "p2", "c1", "m1", "c2", "p3"])
    }

    @Test func queueWithoutOrdinaryCardsIsUnchanged() {
        let queue = [
            Fixtures.card("c1", type: .conjugation),
            Fixtures.card("m1", stage: .mastered),
        ]
        #expect(names(StudyQueueBuilder.delayingInitialConjugations(in: queue)) == ["c1", "m1"])
    }

    @Test func fullQueueMixesAllBuckets() {
        let due = [
            Fixtures.userWord("rec", id: 1, stage: .recognition),
            Fixtures.userWord("prod", id: 2, stage: .production),
            Fixtures.userWord("verb", "to run", id: 3, stage: .production, nextReviewDate: Fixtures.day(-1)),
            Fixtures.userWord("old", id: 4, stage: .mastered),
        ]
        let new = [Fixtures.userWord("n1", id: 5), Fixtures.userWord("n2", id: 6)]
        let queue = StudyQueueBuilder.buildQueue(dueWords: due, newWords: new, conjugationAvailable: true, now: now)
        // attention [rec]; learning = alternating([n1, n2], [verb, prod]) = [n1, verb, n2, prod];
        // maintenance [old]. Rotation: rec, n1, old, verb, n2, prod.
        // Then the first three non-conjugation, non-mastered cards move ahead.
        #expect(names(queue) == ["rec", "n1", "n2", "old", "verb", "prod"])
        #expect(queue.first { $0.userWord.word.italian == "verb" }?.cardType == .conjugation)
    }
}
