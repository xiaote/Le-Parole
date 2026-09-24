import Foundation
import Observation
import GRDB

nonisolated struct StudyCard: Identifiable, Sendable {
    let id = UUID()
    var userWord: UserWord
    var cardType: CardType
    var schedulingIntent: SchedulingIntent = .standard

    enum CardType: Sendable {
        case recognition  // show Italian → type English
        case production   // show English → type Italian
        case conjugation  // dynamic fill-in-the-blank for verbs
    }

    enum SchedulingIntent: Sendable {
        case standard
        case familiarityConfirmation
        case lapseRecovery
    }

    var prompt: String {
        switch cardType {
        case .recognition: userWord.word.italian
        case .production:  userWord.word.english
        case .conjugation: "" // see CardPresentation
        }
    }

    var correctAnswer: String {
        switch cardType {
        case .recognition: userWord.word.english
        case .production:  userWord.word.italian
        case .conjugation: "" // see CardPresentation
        }
    }

    func isCorrect(_ input: String) -> Bool {
        switch cardType {
        case .recognition: userWord.word.isCorrectEnglish(input)
        case .production:  userWord.word.isCorrectItalian(input)
        case .conjugation: false // see CardPresentation
        }
    }
}

struct MistakeContext: Sendable {
    var question: String?
    var answer: String?
    var explanation: String?
}

struct MistakeItem: Identifiable, Sendable {
    var id: String { "\(userWord.id ?? -1)_\(cardType)" }
    let userWord: UserWord
    let cardType: StudyCard.CardType
    var context: MistakeContext?
}

struct SessionStats: Sendable {
    var correct: Int = 0
    var total: Int = 0
    var graduated: Int = 0  // recognition → production promotions
    var wrongWords: [MistakeItem] = []

    var accuracy: Double {
        total == 0 ? 0 : Double(correct) / Double(total)
    }
}

enum ConjugationFetchStatus: Sendable {
    case loading
    case success(ConjugationChallenge)
    case failed
}

private struct SessionInitialization: Sendable {
    let dueWords: [UserWord]
    let newWords: [UserWord]
    let testWordIDs: [Int64]
    let initialTestWords: [UserWord]
}

@Observable
class StudySessionViewModel {
    private nonisolated static let testPageSize = 200
    private nonisolated static let testPagePrefetchThreshold = 40

    // The queue and the conjugation cache change in the background (scheduling
    // updates, familiarity insertions, prefetch results and downgrades of
    // upcoming cards). Views must not observe them, or every such change would
    // re-render the card on screen mid-animation; they observe `presentation`,
    // `isComplete` and `queueLength` instead.
    @ObservationIgnored var cards: [StudyCard] = [] {
        didSet {
            if cards.count != queueLength { queueLength = cards.count }
        }
    }
    @ObservationIgnored var conjugationCache: [UUID: ConjugationFetchStatus] = [:]
    private(set) var queueLength = 0
    /// The card on screen. Replaced only when the learner moves to another card.
    private(set) var presentation: CardPresentation?
    private(set) var isComplete = false
    var currentIndex: Int = 0
    var stats = SessionStats()
    var isTestMode = false
    private(set) var autoPlayPronunciation = true
    private(set) var conjugationLevel = 1
    private(set) var geminiApiKey = ""
    @ObservationIgnored private var synonymCandidatesByInput: [String: [Word]] = [:]
    private var testWordIDs: [Int64] = []
    @ObservationIgnored private var nextTestPageIndex = 0
    @ObservationIgnored private var testPageTask: Task<Void, Never>?
    private(set) var isLoadingMoreCards = false

    var totalCardCount: Int { isTestMode ? testWordIDs.count : queueLength }
    var currentCard: StudyCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    func initialize(dailyNewLimit: Int, isTestMode: Bool = false, isExtraSession: Bool = false) async {
        self.isTestMode = isTestMode
        // Runs alongside the queue query so the first card doesn't pay for it.
        let speechPreparation = Task {
            await SpeechService.shared.prepare(languageCodes: ["it-IT", "en-US"])
        }
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now

        let settings = SettingsStore.shared
        let newWordPacing = settings.dailyNewWordGoal

        let snapshot = try? await DatabaseService.shared.db.read { db -> SessionInitialization in
            if isTestMode {
                var ids = try Int64.fetchAll(db, sql: """
                    SELECT uw.id
                    FROM userWords uw
                    JOIN words w ON uw.wordId = w.wordId
                    WHERE uw.stage NOT IN ('mastered', 'skipped')
                      AND (uw.lastReviewDate IS NULL OR uw.lastReviewDate < ?)
                      AND NOT (uw.stage IN ('recognition', 'production') AND uw.nextReviewDate <= ?)
                    ORDER BY w.isUserCreated DESC,
                             \(Word.cefrOrderSQL),
                             w.frequencyRank,
                             uw.id
                    """, arguments: [sixDaysAgo.timeIntervalSince1970, now.timeIntervalSince1970])
                if dailyNewLimit != Int.max, ids.count > dailyNewLimit {
                    ids = Array(ids.prefix(dailyNewLimit))
                }
                let initialIDs = Array(ids.prefix(Self.testPageSize))
                return SessionInitialization(
                    dueWords: [],
                    newWords: [],
                    testWordIDs: ids,
                    initialTestWords: try Self.fetchUserWords(db, ids: initialIDs)
                )
            }

            let alreadyLearnedToday = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM userWords WHERE learnedDate >= ?",
                arguments: [today.timeIntervalSince1970]
            ) ?? 0
            let remainingNewSlots = isExtraSession ? 0 : max(0, dailyNewLimit - alreadyLearnedToday)
            var dueWords = try UserWord.fetchAll(db, sql: """
                \(DatabaseService.userWordSelectSQL)
                WHERE uw.stage IN ('recognition', 'production', 'mastered')
                  AND uw.nextReviewDate <= ?
                """, arguments: [now.timeIntervalSince1970])
            var newWords: [UserWord] = []
            if remainingNewSlots > 0 {
                newWords = try DatabaseService.fetchNewWords(db, limit: remainingNewSlots)
            }

            if isExtraSession || (dueWords.isEmpty && newWords.isEmpty) {
                let targetBatchSize = max(newWordPacing, 20)
                let recognitionBacklog = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'recognition'"
                ) ?? 0

                if recognitionBacklog < Int(Double(newWordPacing) * 1.5) {
                    let neededNewSlots = min(targetBatchSize, newWordPacing)
                    newWords = try DatabaseService.fetchNewWords(db, limit: neededNewSlots)
                }

                let neededReviewSlots = max(0, targetBatchSize - newWords.count)
                if neededReviewSlots > 0 {
                    let reviewWords = try UserWord.fetchAll(db, sql: """
                        \(DatabaseService.userWordSelectSQL)
                        WHERE uw.stage IN ('recognition', 'production', 'mastered')
                        ORDER BY
                            CASE WHEN uw.nextReviewDate <= ? THEN 0 ELSE 1 END,
                            CASE WHEN uw.lastWrongDate IS NOT NULL AND (uw.lastReviewDate IS NULL OR uw.lastWrongDate >= uw.lastReviewDate) THEN 0 ELSE 1 END,
                            CASE WHEN uw.stage = 'recognition' THEN 0 ELSE 1 END,
                            CASE WHEN uw.stage = 'production' THEN 0 ELSE 1 END,
                            uw.nextReviewDate ASC,
                            w.frequencyRank ASC
                        LIMIT ?
                        """, arguments: [now.timeIntervalSince1970, neededReviewSlots])

                    let existingIDs = Set(dueWords.compactMap(\.id))
                    for word in reviewWords {
                        if let id = word.id, !existingIDs.contains(id) {
                            dueWords.append(word)
                        }
                    }
                }
            }

            return SessionInitialization(
                dueWords: dueWords,
                newWords: newWords,
                testWordIDs: [],
                initialTestWords: []
            )
        }
        autoPlayPronunciation = settings.autoPlayPronunciation
        await speechPreparation.value
        conjugationLevel = settings.conjugationLevel
        geminiApiKey = KeychainStore.get(KeychainStore.geminiApiKey) ?? ""

        if isTestMode {
            configureTestQueue(
                ids: snapshot?.testWordIDs ?? [],
                initialWords: snapshot?.initialTestWords ?? []
            )
        } else {
            buildQueue(
                dueWords: snapshot?.dueWords ?? [],
                newWords: snapshot?.newWords ?? []
            )
        }
        
        prepareCurrentCardForImmediateDisplay()
        presentCurrentCard()
        prefetchUpcomingCards()
    }

    /// Publishes the card at `currentIndex` (and completion) to the view.
    private func presentCurrentCard() {
        let complete = currentIndex >= totalCardCount
        if complete != isComplete { isComplete = complete }
        guard let card = currentCard else {
            presentation = nil
            return
        }
        guard presentation?.card.id != card.id else { return }
        var challenge: ConjugationChallenge?
        if case .success(let ready) = conjugationCache[card.id] { challenge = ready }
        presentation = CardPresentation(card: card, challenge: challenge)
    }

    private nonisolated static func fetchUserWords(_ db: Database, ids: [Int64]) throws -> [UserWord] {
        guard !ids.isEmpty else { return [] }
        let words = try UserWord.fetchAll(
            db,
            sql: "\(DatabaseService.userWordSelectSQL) WHERE uw.id IN (\(databaseQuestionMarks(count: ids.count)))",
            arguments: StatementArguments(ids)
        )
        let wordsByID = Dictionary(uniqueKeysWithValues: words.compactMap { word in
            word.id.map { ($0, word) }
        })
        return ids.compactMap { wordsByID[$0] }
    }

    private func configureTestQueue(ids: [Int64], initialWords: [UserWord]) {
        testWordIDs = ids
        cards = initialWords.map { StudyCard(userWord: $0, cardType: .production) }
        nextTestPageIndex = min(Self.testPageSize, ids.count)
    }

    private func buildQueue(dueWords: [UserWord], newWords: [UserWord]) {
        cards = StudyQueueBuilder.buildQueue(
            dueWords: dueWords,
            newWords: newWords,
            conjugationAvailable: AppleIntelligenceService.isAvailable || !geminiApiKey.isEmpty
        )
    }

    func isValidItalianSynonym(input: String) async -> Bool {
        guard let current = currentCard else { return false }
        let targetEnglish = current.userWord.word.english
        let targetAlternatives = current.userWord.word.alternatives

        let lookupCandidates = Word.italianLookupCandidates(input)
        guard let lookupKey = lookupCandidates.first else { return false }

        let matchingWords: [Word]
        if let cached = synonymCandidatesByInput[lookupKey] {
            matchingWords = cached
        } else {
            let placeholders = Array(repeating: "?", count: lookupCandidates.count).joined(separator: ",")
            matchingWords = (try? await DatabaseService.shared.db.read { db in
                try Word.fetchAll(
                    db,
                    sql: "SELECT * FROM words WHERE italian IN (\(placeholders))",
                    arguments: StatementArguments(lookupCandidates)
                )
            }) ?? []
            if !matchingWords.isEmpty {
                synonymCandidatesByInput[lookupKey] = matchingWords
            }
        }

        for word in matchingWords where word.isCorrectItalian(input) {
            if word.isCorrectEnglish(targetEnglish) { return true }
            for alternative in targetAlternatives {
                if word.isCorrectEnglish(alternative) { return true }
            }
            if current.userWord.word.isCorrectEnglish(word.english) { return true }
        }
        return false
    }

    func advance() {
        currentIndex += 1
        prepareCurrentCardForImmediateDisplay()
        if isTestMode {
            if currentIndex >= cards.count && currentIndex < totalCardCount {
                isLoadingMoreCards = true
            }
            prefetchTestPageIfNeeded()
        }
        presentCurrentCard()
        prefetchUpcomingCards()
    }

    func endSession() {
        cancelSessionWork()
        if isTestMode {
            testWordIDs = Array(testWordIDs.prefix(currentIndex))
            nextTestPageIndex = min(nextTestPageIndex, currentIndex)
        } else {
            cards = Array(cards.prefix(currentIndex))
        }
        presentCurrentCard()
    }

    func cancelSessionWork() {
        testPageTask?.cancel()
        testPageTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        isLoadingMoreCards = false
    }

    private func prefetchTestPageIfNeeded() {
        guard isTestMode,
              testPageTask == nil,
              nextTestPageIndex < testWordIDs.count,
              cards.count - currentIndex <= Self.testPagePrefetchThreshold else { return }

        let pageStart = nextTestPageIndex
        let pageEnd = min(pageStart + Self.testPageSize, testWordIDs.count)
        let pageIDs = Array(testWordIDs[pageStart..<pageEnd])
        testPageTask = Task { @MainActor [weak self] in
            let words: [UserWord]
            do {
                words = try await DatabaseService.shared.db.read { db in
                    try Self.fetchUserWords(db, ids: pageIDs)
                }
            } catch {
                guard let self else { return }
                self.isLoadingMoreCards = false
                self.testPageTask = nil
                return
            }
            guard !Task.isCancelled, let self else { return }

            self.cards.append(contentsOf: words.map { StudyCard(userWord: $0, cardType: .production) })
            self.nextTestPageIndex = pageEnd
            self.isLoadingMoreCards = false
            self.testPageTask = nil
            self.presentCurrentCard()

            // A short final page may still leave the buffer below the threshold.
            self.prefetchTestPageIfNeeded()
        }
    }
    
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    private func downgradeConjugationCard(id: UUID) {
        conjugationCache[id] = .failed
        if let index = cards.firstIndex(where: { $0.id == id }) {
            cards[index].cardType = .production
        }
    }

    /// A study card should never block the session while generated content is
    /// pending. Use a prefetched challenge when ready; otherwise retain the
    /// same word and fall back to the ordinary production interaction.
    private func prepareCurrentCardForImmediateDisplay() {
        guard currentIndex < cards.count,
              cards[currentIndex].cardType == .conjugation else { return }
        if case .success = conjugationCache[cards[currentIndex].id] { return }
        downgradeConjugationCard(id: cards[currentIndex].id)
    }

    /// The first conjugation card among the current and next card that still
    /// needs a challenge, unless one there is already ready. At most one
    /// conjugation card is generated at a time.
    private func nextConjugationCardToGenerate() -> StudyCard? {
        guard currentIndex < cards.count else { return nil }
        for card in cards[currentIndex..<min(currentIndex + 2, cards.count)] where card.cardType == .conjugation {
            switch conjugationCache[card.id] {
            case nil:
                return card
            case .success:
                return nil
            case .loading:
                // A loading state without the owning prefetch task is stale.
                // Fail safely rather than treating it as ready.
                downgradeConjugationCard(id: card.id)
            case .failed:
                break
            }
        }
        return nil
    }

    private func prefetchUpcomingCards() {
        guard prefetchTask == nil, let card = nextConjugationCardToGenerate() else { return }

        let cardID = card.id
        let word = card.userWord.word
        let level = conjugationLevel
        let apiKey = geminiApiKey
        conjugationCache[cardID] = .loading

        prefetchTask = Task { @MainActor [weak self] in
            let stats = (try? await DatabaseService.shared.db.read { db in
                try ConjugationStat.fetchAll(
                    db,
                    sql: "SELECT * FROM conjugationStats WHERE verb = ?",
                    arguments: [word.italian]
                )
            }) ?? []
            let challenge = Task.isCancelled ? nil : await ConjugationChallengeGenerator.generate(
                verb: word.italian,
                englishMeaning: word.english,
                level: level,
                stats: stats,
                apiKey: apiKey
            )
            guard let self else { return }
            guard !Task.isCancelled else {
                // cancelSessionWork already cleared prefetchTask.
                if case .loading = self.conjugationCache[cardID] {
                    self.downgradeConjugationCard(id: cardID)
                }
                return
            }
            self.prefetchTask = nil

            if case .loading = self.conjugationCache[cardID] {
                if let challenge {
                    self.conjugationCache[cardID] = .success(challenge)
                } else {
                    self.downgradeConjugationCard(id: cardID)
                }
            }

            if GeminiService.isRateLimited {
                for index in self.cards.indices
                where self.cards[index].cardType == .conjugation && self.conjugationCache[self.cards[index].id] == nil {
                    self.conjugationCache[self.cards[index].id] = .failed
                    self.cards[index].cardType = .production
                }
            }

            // The learner may have advanced while this was generating.
            self.prefetchUpcomingCards()
        }
    }

    func recordResult(correct: Bool, context: MistakeContext? = nil) -> ReviewOutcome {
        guard currentIndex < cards.count else { return .none }
        let card = cards[currentIndex]
        let result = ReviewScheduler.schedule(
            card.userWord,
            cardType: card.cardType,
            intent: card.schedulingIntent,
            correct: correct,
            isTestMode: isTestMode
        )
        cards[currentIndex].userWord = result.userWord

        stats.total += 1
        if correct { stats.correct += 1 }
        if result.graduated { stats.graduated += 1 }
        if !correct, !stats.wrongWords.contains(where: { $0.userWord.id == result.userWord.id }) {
            stats.wrongWords.append(MistakeItem(userWord: result.userWord, cardType: card.cardType, context: context))
        }
        if result.needsFamiliarityConfirmation {
            scheduleFamiliarityConfirmation(for: result.userWord)
        }

        var conjugationReview: ConjugationReviewRecord?
        if card.cardType == .conjugation, case .success(let challenge) = conjugationCache[card.id] {
            conjugationReview = ConjugationReviewRecord(
                verb: result.userWord.word.italian,
                tense: challenge.tense,
                pronoun: challenge.pronoun
            )
        }

        DatabaseService.shared.persistReview(
            userWord: result.userWord,
            correct: correct,
            introduced: result.introduced,
            movedToProduction: result.movedToProduction,
            movedToMastered: result.movedToMastered,
            conjugation: conjugationReview
        )
        return result.outcome
    }

    /// A first-sight recognition success may be a word the learner already
    /// knows. Confirm production after a few unrelated cards; two successful
    /// directions are enough to avoid days of low-value introductory reviews.
    private func scheduleFamiliarityConfirmation(for userWord: UserWord) {
        let confirmation = StudyCard(
            userWord: userWord,
            cardType: .production,
            schedulingIntent: .familiarityConfirmation
        )
        let insertionIndex = min(currentIndex + 6, cards.count)
        cards.insert(confirmation, at: insertionIndex)
    }
}
