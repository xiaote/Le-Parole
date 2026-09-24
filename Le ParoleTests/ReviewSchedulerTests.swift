import Foundation
import Testing
@testable import Le_Parole

@Suite("ReviewScheduler")
struct ReviewSchedulerTests {
    let now = Fixtures.now

    private func schedule(
        _ userWord: UserWord,
        _ cardType: StudyCard.CardType = .production,
        intent: StudyCard.SchedulingIntent = .standard,
        correct: Bool,
        testMode: Bool = false
    ) -> ReviewResult {
        ReviewScheduler.schedule(
            userWord,
            cardType: cardType,
            intent: intent,
            correct: correct,
            isTestMode: testMode,
            now: now
        )
    }

    private func due(in days: Int) -> Date {
        SM2.nextReviewDate(interval: days, from: now)
    }

    // MARK: - Recognition

    @Test func newWordRecognisedMovesToProductionAndRequestsConfirmation() {
        let result = schedule(Fixtures.userWord(stage: .new), .recognition, correct: true)
        let word = result.userWord

        #expect(word.stage == .production)
        #expect(word.learnedDate == now)
        #expect(word.interval == 1)
        #expect(word.repetitions == 1)
        #expect(word.nextReviewDate == due(in: 1))
        #expect(word.totalAttempts == 1)
        #expect(word.totalCorrect == 1)
        #expect(word.lastReviewDate == now)
        #expect(word.lastWrongDate == nil)
        #expect(result.introduced)
        #expect(result.movedToProduction)
        #expect(!result.movedToMastered)
        #expect(result.graduated)
        #expect(result.needsFamiliarityConfirmation)
        #expect(result.outcome.summary == "stage new->production")
    }

    @Test func recognitionStageWordRecognisedDoesNotRequestConfirmation() {
        let learned = Fixtures.day(-3)
        let result = schedule(Fixtures.userWord(stage: .recognition, learnedDate: learned), .recognition, correct: true)

        #expect(result.userWord.stage == .production)
        #expect(result.userWord.learnedDate == learned)
        #expect(!result.introduced)
        #expect(result.movedToProduction)
        #expect(result.graduated)
        #expect(!result.needsFamiliarityConfirmation)
    }

    @Test func newWordMissedInRecognitionEntersRecognitionStage() {
        let result = schedule(Fixtures.userWord(stage: .new), .recognition, correct: false)
        let word = result.userWord

        #expect(word.stage == .recognition)
        #expect(word.learnedDate == now)
        #expect(word.lastWrongDate == now)
        #expect(word.totalAttempts == 1)
        #expect(word.totalCorrect == 0)
        #expect(word.nextReviewDate == due(in: 1))
        #expect(result.introduced)
        #expect(!result.movedToProduction)
        #expect(!result.graduated)
        #expect(!result.needsFamiliarityConfirmation)
        #expect(result.outcome.summary == "stage new->recognition")
    }

    @Test func recognitionStageWordMissedStaysInRecognition() {
        let result = schedule(Fixtures.userWord(stage: .recognition), .recognition, correct: false)
        #expect(result.userWord.stage == .recognition)
        #expect(result.userWord.nextReviewDate == due(in: 1))
        #expect(!result.introduced)
        #expect(result.outcome.summary == "none")
    }

    // MARK: - Production / conjugation

    @Test("Correct production answer reaches mastery at the threshold", arguments: [
        // (interval, repetitions, ease, expected new interval, mastered)
        (6, 2, 2.5, 17, false),   // 6 * 2.5 * 1.15 = 17.25
        (6, 2, 3.0, 21, true),    // 6 * 3.0 * 1.15 = 20.7 → exactly the threshold
        (10, 2, 2.5, 29, true),   // 10 * 2.5 * 1.15 = 28.75
    ])
    func productionCorrectPromotion(interval: Int, repetitions: Int, ease: Double, expected: Int, mastered: Bool) {
        let result = schedule(
            Fixtures.userWord(stage: .production, interval: interval, repetitions: repetitions, easeFactor: ease),
            correct: true
        )
        #expect(result.userWord.interval == expected)
        #expect(result.userWord.repetitions == repetitions + 1)
        #expect(result.userWord.nextReviewDate == due(in: expected))
        #expect(result.userWord.stage == (mastered ? .mastered : .production))
        #expect(result.movedToMastered == mastered)
        #expect(result.outcome.summary == (mastered ? "stage production->mastered" : "none"))
        #expect(!result.graduated)
    }

    @Test("Conjugation cards schedule exactly like production cards", arguments: [true, false])
    func conjugationMatchesProduction(correct: Bool) {
        let word = Fixtures.userWord(stage: .production, interval: 8, repetitions: 2)
        let production = schedule(word, .production, correct: correct)
        let conjugation = schedule(word, .conjugation, correct: correct)
        #expect(production.userWord == conjugation.userWord)
        #expect(production.outcome.summary == conjugation.outcome.summary)
    }

    @Test func productionMissResetsInterval() {
        let result = schedule(
            Fixtures.userWord(stage: .production, interval: 6, repetitions: 2, easeFactor: 2.5),
            correct: false
        )
        #expect(result.userWord.stage == .production)
        #expect(result.userWord.interval == 1)
        #expect(result.userWord.repetitions == 0)
        #expect(abs(result.userWord.easeFactor - 2.3) < 0.0001)
        #expect(result.userWord.lastWrongDate == now)
        #expect(result.outcome.summary == "none")
    }

    @Test func masteredLapseDropsToProductionWithLapseDelay() {
        let result = schedule(
            Fixtures.userWord(stage: .mastered, interval: 40, repetitions: 5, easeFactor: 2.5),
            correct: false
        )
        let word = result.userWord
        #expect(word.stage == .production)
        #expect(word.interval == 10) // 40 * 0.25, clamped to 8...14
        #expect(word.repetitions == 4)
        #expect(abs(word.easeFactor - 2.35) < 0.0001)
        #expect(word.nextReviewDate == due(in: SM2.lapseReviewDelay))
        #expect(!result.movedToProduction)
        #expect(!result.movedToMastered)
        #expect(result.outcome.summary == "stage mastered->production")
        #expect(SM2.isLapseRecoveryCandidate(word))
    }

    @Test func lapseRecoveryCorrectRestoresMasteryWithoutCountingAsNew() {
        let lapsed = schedule(
            Fixtures.userWord(stage: .mastered, interval: 40, repetitions: 5, easeFactor: 2.5),
            correct: false
        ).userWord

        let result = schedule(lapsed, intent: .lapseRecovery, correct: true)
        #expect(result.userWord.stage == .mastered)
        #expect(result.userWord.interval == 31) // 10 * 2.35 * 1.3 = 30.55
        #expect(!result.movedToMastered)
        #expect(result.outcome.summary == "lapseRecovered You know this | See it again in 4 weeks")
    }

    @Test func lapseRecoveryRestoresAtLeastTheMasteryThreshold() {
        let result = schedule(
            Fixtures.userWord(stage: .production, interval: 8, repetitions: 2, easeFactor: 1.3),
            intent: .lapseRecovery,
            correct: true
        )
        #expect(result.userWord.interval == SM2.masteryThreshold)
        #expect(result.userWord.stage == .mastered)
    }

    @Test func familiarityConfirmationCorrectAcceleratesMastery() {
        let result = schedule(
            Fixtures.userWord(stage: .production, interval: 1, repetitions: 1, easeFactor: 2.5),
            intent: .familiarityConfirmation,
            correct: true
        )
        #expect(result.userWord.stage == .mastered)
        #expect(result.userWord.interval == SM2.acceleratedMasteryInterval)
        #expect(result.userWord.repetitions == 3)
        #expect(result.userWord.nextReviewDate == due(in: SM2.acceleratedMasteryInterval))
        #expect(result.movedToMastered)
        #expect(result.outcome.summary == "stage production->mastered")
    }

    @Test func familiarityConfirmationMissFallsBackToStandardScheduling() {
        let result = schedule(
            Fixtures.userWord(stage: .production, interval: 1, repetitions: 1),
            intent: .familiarityConfirmation,
            correct: false
        )
        #expect(result.userWord.stage == .production)
        #expect(result.userWord.interval == 1)
        #expect(result.userWord.repetitions == 0)
    }

    @Test func masteredCorrectReviewReportsNextInterval() {
        let result = schedule(
            Fixtures.userWord(stage: .mastered, interval: 30, repetitions: 3, easeFactor: 2.5),
            correct: true
        )
        #expect(result.userWord.interval == 86) // 30 * 2.5 * 1.15 = 86.25
        #expect(!result.movedToMastered)
        #expect(result.outcome.summary == "reviewScheduled Sticking with you | See it again in 3 months")
    }

    // MARK: - Test mode

    @Test("Test-mode correct answers master the word", arguments: [WordStage.new, .recognition, .production])
    func testModeCorrectMasters(stage: WordStage) {
        let result = schedule(Fixtures.userWord(stage: stage), correct: true, testMode: true)
        let word = result.userWord
        #expect(word.stage == .mastered)
        #expect(word.interval == SM2.masteryThreshold)
        #expect(word.repetitions == 1)
        #expect(word.easeFactor == 2.5)
        #expect(word.nextReviewDate == due(in: SM2.masteryThreshold))
        #expect(word.learnedDate != nil)
        #expect(result.introduced == (stage == .new))
        #expect(result.movedToMastered)
        #expect(!result.graduated)
        #expect(!result.needsFamiliarityConfirmation)
        #expect(result.outcome.summary == "stage \(stage.rawValue)->mastered")
    }

    @Test func testModeMissOnNewWordKeepsStage() {
        let original = Fixtures.userWord(stage: .new, nextReviewDate: Fixtures.day(-1))
        let result = schedule(original, correct: false, testMode: true)
        #expect(result.userWord.stage == .new)
        #expect(result.userWord.nextReviewDate == original.nextReviewDate)
        #expect(result.userWord.learnedDate == nil)
        #expect(result.userWord.lastWrongDate == now)
        #expect(!result.introduced)
        #expect(result.outcome.summary == "none")
    }

    @Test func testModeMissOnLearningWordReschedulesTomorrow() {
        let result = schedule(Fixtures.userWord(stage: .recognition), .recognition, correct: false, testMode: true)
        #expect(result.userWord.stage == .recognition)
        #expect(result.userWord.nextReviewDate == due(in: 1))
    }

    // MARK: - Feedback

    @Test("Review feedback wording", arguments: [
        (1, "Nice start", "1 day"),
        (2, "Getting familiar", "2 days"),
        (6, "Getting familiar", "6 days"),
        (7, "Coming along", "7 days"),
        (13, "Coming along", "13 days"),
        (14, "Coming along", "2 weeks"),
        (21, "You know this", "3 weeks"),
        (59, "You know this", "8 weeks"),
        (60, "Sticking with you", "2 months"),
        (364, "Second nature", "12 months"),
        (365, "Second nature", "1 year"),
        (800, "Second nature", "2 years"),
    ])
    func feedback(interval: Int, title: String, duration: String) {
        let feedback = ReviewScheduler.feedback(forInterval: interval)
        #expect(feedback.title == title)
        #expect(feedback.detail == "See it again in \(duration)")
    }
}
