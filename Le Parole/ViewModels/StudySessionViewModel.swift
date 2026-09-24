import Foundation
import Observation
import GRDB

struct StudyCard: Identifiable, Sendable {
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
        case .conjugation: "" // handled dynamically in view
        }
    }

    var correctAnswer: String {
        switch cardType {
        case .recognition: userWord.word.english
        case .production:  userWord.word.italian
        case .conjugation: "" // handled dynamically in view
        }
    }

    func isCorrect(_ input: String) -> Bool {
        switch cardType {
        case .recognition: userWord.word.isCorrectEnglish(input)
        case .production:  userWord.word.isCorrectItalian(input)
        case .conjugation: false // handled dynamically in view
        }
    }
}

struct MistakeContext: Sendable {
    var question: String?
    var answer: String?
    var explanation: String?
}

struct MistakeItem: Identifiable, Sendable {
    var id: String { "\(userWord.id)_\(cardType)" }
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

struct ReviewScheduleFeedback: Sendable {
    let title: String
    let detail: String
}

enum ReviewOutcome: Sendable {
    case stageChanged(from: WordStage, to: WordStage)
    case lapseRecovered(ReviewScheduleFeedback)
    case reviewScheduled(ReviewScheduleFeedback)
    case none
}

enum ConjugationFetchStatus: Sendable {
    case loading
    case success(ConjugationChallenge)
    case failed
}

private struct SessionInitialization: Sendable {
    let settings: UserSettings?
    let dueWords: [UserWord]
    let newWords: [UserWord]
    let testWordIDs: [Int64]
    let initialTestWords: [UserWord]
}

@Observable
class StudySessionViewModel {
    private nonisolated static let testPageSize = 200
    private nonisolated static let testPagePrefetchThreshold = 40

    var cards: [StudyCard] = []
    var conjugationCache: [UUID: ConjugationFetchStatus] = [:]
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

    var totalCardCount: Int { isTestMode ? testWordIDs.count : cards.count }
    var isComplete: Bool { currentIndex >= totalCardCount }
    var currentCard: StudyCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    func initialize(dailyNewLimit: Int, isTestMode: Bool = false, isExtraSession: Bool = false) async {
        self.isTestMode = isTestMode
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now

        let snapshot = try? await DatabaseService.shared.db.read { db -> SessionInitialization in
            let settings = try UserSettings.fetchOne(db)

            if isTestMode {
                var ids = try Int64.fetchAll(db, sql: """
                    SELECT uw.id
                    FROM userWords uw
                    JOIN words w ON uw.wordId = w.wordId
                    WHERE uw.stage NOT IN ('mastered', 'skipped')
                      AND (uw.lastReviewDate IS NULL OR uw.lastReviewDate < ?)
                      AND NOT (uw.stage IN ('recognition', 'production') AND uw.nextReviewDate <= ?)
                    ORDER BY w.isUserCreated DESC,
                             CASE w.level
                                 WHEN 'A1' THEN 0 WHEN 'A2' THEN 1 WHEN 'B1' THEN 2
                                 WHEN 'B2' THEN 3 WHEN 'C1' THEN 4 WHEN 'C2' THEN 5
                                 ELSE 99
                             END,
                             w.frequencyRank,
                             uw.id
                    """, arguments: [sixDaysAgo.timeIntervalSince1970, now.timeIntervalSince1970])
                if dailyNewLimit != Int.max, ids.count > dailyNewLimit {
                    ids = Array(ids.prefix(dailyNewLimit))
                }
                let initialIDs = Array(ids.prefix(Self.testPageSize))
                return SessionInitialization(
                    settings: settings,
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
                newWords = try UserWord.fetchAll(db, sql: """
                    \(DatabaseService.userWordSelectSQL)
                    WHERE uw.stage = 'new'
                    ORDER BY w.isUserCreated DESC,
                             CASE WHEN w.isUserCreated THEN
                                 CASE w.level
                                     WHEN 'A1' THEN 0 WHEN 'A2' THEN 1 WHEN 'B1' THEN 2
                                     WHEN 'B2' THEN 3 WHEN 'C1' THEN 4 WHEN 'C2' THEN 5
                                     ELSE 99
                                 END
                             ELSE 0 END,
                             w.frequencyRank,
                             w.wordId
                    LIMIT ?
                    """, arguments: [remainingNewSlots])
            }

            if isExtraSession || (dueWords.isEmpty && newWords.isEmpty) {
                let targetBatchSize = max(settings?.dailyNewWordGoal ?? 20, 20)
                let recognitionBacklog = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM userWords WHERE stage = 'recognition'"
                ) ?? 0
                let newWordPacing = settings?.dailyNewWordGoal ?? 20

                if recognitionBacklog < Int(Double(newWordPacing) * 1.5) {
                    let neededNewSlots = min(targetBatchSize, newWordPacing)
                    newWords = try UserWord.fetchAll(db, sql: """
                        \(DatabaseService.userWordSelectSQL)
                        WHERE uw.stage = 'new'
                        ORDER BY w.isUserCreated DESC,
                                 CASE WHEN w.isUserCreated THEN
                                     CASE w.level
                                         WHEN 'A1' THEN 0 WHEN 'A2' THEN 1 WHEN 'B1' THEN 2
                                         WHEN 'B2' THEN 3 WHEN 'C1' THEN 4 WHEN 'C2' THEN 5
                                         ELSE 99
                                     END
                                 ELSE 0 END,
                                 w.frequencyRank,
                                 w.wordId
                        LIMIT ?
                        """, arguments: [neededNewSlots])
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
                settings: settings,
                dueWords: dueWords,
                newWords: newWords,
                testWordIDs: [],
                initialTestWords: []
            )
        }
        autoPlayPronunciation = snapshot?.settings?.autoPlayPronunciation ?? true
        conjugationLevel = snapshot?.settings?.conjugationLevel ?? 1
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
        prefetchUpcomingCards()
    }

    private nonisolated static func fetchUserWords(_ db: Database, ids: [Int64]) throws -> [UserWord] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let words = try UserWord.fetchAll(
            db,
            sql: "\(DatabaseService.userWordSelectSQL) WHERE uw.id IN (\(placeholders))",
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
        let now = Date.now
        let newCards = newWords.map { StudyCard(userWord: $0, cardType: .recognition) }

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

        let aiAvailable = AppleIntelligenceService.isAvailable || !geminiApiKey.isEmpty
        let makeDueCard: (UserWord, StudyCard.SchedulingIntent) -> StudyCard = { userWord, schedulingIntent in
            let isVerb = userWord.word.english.lowercased().hasPrefix("to ")
            let type: StudyCard.CardType = aiAvailable && isVerb ? .conjugation : .production
            return StudyCard(userWord: userWord, cardType: type, schedulingIntent: schedulingIntent)
        }

        let attentionCards = attentionWords.map { userWord in
            if userWord.stage == .recognition {
                return StudyCard(userWord: userWord, cardType: .recognition)
            }
            let schedulingIntent: StudyCard.SchedulingIntent =
                hasUnresolvedMistake(userWord) && SM2.isLapseRecoveryCandidate(userWord)
                ? .lapseRecovery
                : .standard
            return makeDueCard(userWord, schedulingIntent)
        }
        let dueLearningCards = learningWords.map { makeDueCard($0, .standard) }
        let learningCards = alternating(newCards, dueLearningCards)
        let maintenanceCards = maintenanceWords.map { makeDueCard($0, .standard) }

        let queue = rotateQueue(
            attention: attentionCards,
            learning: learningCards,
            maintenance: maintenanceCards
        )
        cards = delayingInitialConjugations(in: queue)
    }

    /// A mistake remains unresolved until the word is subsequently answered
    /// correctly. This uses the existing timestamps, so queue prioritization
    /// does not need another persistence field.
    private func hasUnresolvedMistake(_ userWord: UserWord) -> Bool {
        guard let lastWrong = userWord.lastWrongDate else { return false }
        guard let lastReview = userWord.lastReviewDate else { return true }
        return lastWrong >= lastReview
    }

    private func isHigherPriority(_ lhs: UserWord, than rhs: UserWord, now: Date) -> Bool {
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

    private func alternating(_ first: [StudyCard], _ second: [StudyCard]) -> [StudyCard] {
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
    private func rotateQueue(
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
    private func delayingInitialConjugations(in queue: [StudyCard]) -> [StudyCard] {
        let initialCards = Array(queue.lazy.filter {
            $0.cardType != .conjugation && $0.userWord.stage != .mastered
        }.prefix(3))
        guard !initialCards.isEmpty else { return queue }
        let initialIDs = Set(initialCards.map(\.id))
        return initialCards + queue.filter { !initialIDs.contains($0.id) }
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

    func recordResult(correct: Bool, context: MistakeContext? = nil) -> ReviewOutcome {
        processResult(correct: correct, context: context)
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

            // A short final page may still leave the buffer below the threshold.
            self.prefetchTestPageIfNeeded()
        }
    }
    
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceGeneration = 0

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

    private func processResult(correct: Bool, context: MistakeContext? = nil) -> ReviewOutcome {
        guard currentIndex < cards.count else { return .none }
        let cardType = cards[currentIndex].cardType
        let schedulingIntent = cards[currentIndex].schedulingIntent
        let stageBeforeAnswer = cards[currentIndex].userWord.stage
        let wasIntroducedBeforeAnswer = cards[currentIndex].userWord.learnedDate != nil

        stats.total += 1
        if correct { stats.correct += 1 }

        cards[currentIndex].userWord.totalAttempts += 1
        if correct {
            cards[currentIndex].userWord.totalCorrect += 1
        }
        cards[currentIndex].userWord.lastReviewDate = .now

        if !correct {
            cards[currentIndex].userWord.lastWrongDate = .now
            let uwCopy = cards[currentIndex].userWord
            if !stats.wrongWords.contains(where: { $0.userWord.id == uwCopy.id }) {
                stats.wrongWords.append(MistakeItem(userWord: uwCopy, cardType: cardType, context: context))
            }
        }

        if isTestMode {
            if correct {
                cards[currentIndex].userWord.stage = .mastered
                cards[currentIndex].userWord.learnedDate = cards[currentIndex].userWord.learnedDate ?? .now
                cards[currentIndex].userWord.interval = SM2.masteryThreshold
                cards[currentIndex].userWord.repetitions = 1
                cards[currentIndex].userWord.easeFactor = 2.5
                cards[currentIndex].userWord.nextReviewDate = SM2.nextReviewDate(interval: SM2.masteryThreshold)
            } else {
                if cards[currentIndex].userWord.stage != .new {
                    cards[currentIndex].userWord.nextReviewDate = SM2.nextReviewDate(interval: 1)
                }
            }
        } else {
            switch cardType {
            case .recognition:
                if correct {
                    if cards[currentIndex].userWord.learnedDate == nil {
                        cards[currentIndex].userWord.learnedDate = .now
                    }
                    cards[currentIndex].userWord.stage = .production
                    let result = SM2.evaluate(userWord: cards[currentIndex].userWord, correct: true)
                    applyResult(result, to: &cards[currentIndex].userWord)
                    stats.graduated += 1
                    if stageBeforeAnswer == .new {
                        scheduleFamiliarityConfirmation(for: cards[currentIndex].userWord)
                    }
                } else {
                    if cards[currentIndex].userWord.stage == .new {
                        cards[currentIndex].userWord.learnedDate = .now
                        cards[currentIndex].userWord.stage = .recognition
                    }
                    cards[currentIndex].userWord.nextReviewDate = SM2.nextReviewDate(interval: 1)
                }

            case .production, .conjugation:
                let isMasteredLapse = !correct && stageBeforeAnswer == .mastered
                let result: SM2Result
                if schedulingIntent == .familiarityConfirmation && correct {
                    result = SM2.acceleratedMastery(for: cards[currentIndex].userWord)
                } else if schedulingIntent == .lapseRecovery && correct {
                    result = SM2.completeLapseRecovery(for: cards[currentIndex].userWord)
                } else if isMasteredLapse {
                    result = SM2.beginLapseRecovery(for: cards[currentIndex].userWord)
                } else {
                    result = SM2.evaluate(userWord: cards[currentIndex].userWord, correct: correct)
                }
                applyResult(result, to: &cards[currentIndex].userWord)
                if isMasteredLapse {
                    cards[currentIndex].userWord.nextReviewDate = SM2.nextReviewDate(interval: SM2.lapseReviewDelay)
                }
                if correct && result.interval >= SM2.masteryThreshold {
                    cards[currentIndex].userWord.stage = .mastered
                } else if isMasteredLapse {
                    cards[currentIndex].userWord.stage = .production
                }
            }
        }

        let uwToSave = cards[currentIndex].userWord
        let introduced = !wasIntroducedBeforeAnswer && uwToSave.learnedDate != nil
        let movedToProduction =
            stageBeforeAnswer != .production &&
            stageBeforeAnswer != .mastered &&
            uwToSave.stage == .production
        let didTransitionToMastered = stageBeforeAnswer != .mastered && uwToSave.stage == .mastered
        let countsAsNewMastery: Bool
        if case .lapseRecovery = schedulingIntent {
            countsAsNewMastery = false
        } else {
            countsAsNewMastery = didTransitionToMastered
        }

        let outcome: ReviewOutcome
        if schedulingIntent == .lapseRecovery, correct, didTransitionToMastered {
            outcome = .lapseRecovered(reviewScheduleFeedback(for: uwToSave.interval))
        } else if stageBeforeAnswer != uwToSave.stage {
            outcome = .stageChanged(from: stageBeforeAnswer, to: uwToSave.stage)
        } else if correct, stageBeforeAnswer == .mastered, uwToSave.stage == .mastered {
            outcome = .reviewScheduled(reviewScheduleFeedback(for: uwToSave.interval))
        } else {
            outcome = .none
        }
        
        let conjugationReview: ConjugationReviewRecord?
        if cardType == .conjugation, case .success(let challenge) = conjugationCache[cards[currentIndex].id] {
            conjugationReview = ConjugationReviewRecord(
                verb: cards[currentIndex].userWord.word.italian,
                tense: challenge.tense,
                pronoun: challenge.pronoun
            )
        } else {
            conjugationReview = nil
        }

        let precedingPersistence = persistenceTask
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let persistence = Task.detached {
            await precedingPersistence?.value
            await DatabaseService.shared.persistReview(
                userWord: uwToSave,
                correct: correct,
                introduced: introduced,
                movedToProduction: movedToProduction,
                movedToMastered: countsAsNewMastery,
                conjugation: conjugationReview
            )
        }
        persistenceTask = persistence
        Task { @MainActor [weak self] in
            await persistence.value
            guard let self, self.persistenceGeneration == generation else { return }
            self.persistenceTask = nil
        }
        return outcome
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

    private func applyResult(_ result: SM2Result, to userWord: inout UserWord) {
        userWord.interval      = result.interval
        userWord.easeFactor    = result.easeFactor
        userWord.repetitions   = result.repetitions
        userWord.nextReviewDate = SM2.nextReviewDate(interval: result.interval)
    }

    private func reviewScheduleFeedback(for interval: Int) -> ReviewScheduleFeedback {
        let title: String
        switch interval {
        case ...1:
            title = "Nice start"
        case 2...6:
            title = "Getting familiar"
        case 7...20:
            title = "Coming along"
        case 21...59:
            title = "You know this"
        case 60...179:
            title = "Sticking with you"
        default:
            title = "Second nature"
        }

        let duration: String
        switch interval {
        case ..<14:
            duration = "\(interval) days"
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
