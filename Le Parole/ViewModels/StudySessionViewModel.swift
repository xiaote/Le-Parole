import Foundation
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
    let id = UUID()
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

enum ConjugationFetchStatus: Sendable {
    case loading
    case success(sentence: String, answer: String, explanation: String, tense: String, pronoun: String, englishTranslation: String)
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
    var geminiError: String? = nil
    private(set) var autoPlayPronunciation = true
    private(set) var conjugationLevel = 1
    private(set) var geminiApiKey = ""
    private var synonymCandidatesByInput: [String: [Word]] = [:]
    private var testWordIDs: [Int64] = []
    private var nextTestPageIndex = 0
    private var testPageTask: Task<Void, Never>?
    private(set) var isLoadingMoreCards = false

    var totalCardCount: Int { isTestMode ? testWordIDs.count : cards.count }
    var isComplete: Bool { currentIndex >= totalCardCount }
    var currentCard: StudyCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    func initialize(dailyNewLimit: Int, isTestMode: Bool = false) async {
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
            let remainingNewSlots = max(0, dailyNewLimit - alreadyLearnedToday)
            let dueWords = try UserWord.fetchAll(db, sql: """
                \(DatabaseService.userWordSelectSQL)
                WHERE uw.stage IN ('recognition', 'production', 'mastered')
                  AND uw.nextReviewDate <= ?
                """, arguments: [now.timeIntervalSince1970])
            let newWords = try UserWord.fetchAll(db, sql: """
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
        geminiApiKey = snapshot?.settings?.geminiApiKey ?? ""

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

        let aiAvailable = AppleIntelligenceService.isAvailable
        let makeDueCard: (UserWord) -> StudyCard = { userWord in
            let isVerb = userWord.word.english.lowercased().hasPrefix("to ")
            let type: StudyCard.CardType = aiAvailable && isVerb ? .conjugation : .production
            return StudyCard(userWord: userWord, cardType: type)
        }

        let attentionCards = attentionWords.map { userWord in
            userWord.stage == .recognition
                ? StudyCard(userWord: userWord, cardType: .recognition)
                : makeDueCard(userWord)
        }
        let dueLearningCards = learningWords.map(makeDueCard)
        let learningCards = alternating(newCards, dueLearningCards)
        let maintenanceCards = maintenanceWords.map(makeDueCard)

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

    func recordResult(correct: Bool, context: MistakeContext? = nil) {
        processResult(correct: correct, context: context)
    }

    func advance() {
        currentIndex += 1
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
    
    private var prefetchTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    
    private func prefetchUpcomingCards() {
        guard prefetchTask == nil else { return }
        
        prefetchTask = Task { @MainActor in
            defer { self.prefetchTask = nil }
            var cachedAhead = 0
            var missingCards: [StudyCard] = []
            
            for i in self.currentIndex..<self.cards.count {
                if self.cards[i].cardType == .conjugation {
                    let cacheState = self.conjugationCache[self.cards[i].id]
                    if let state = cacheState {
                        if case .failed = state {
                            // skip failed
                        } else {
                            cachedAhead += 1
                        }
                    } else {
                        missingCards.append(self.cards[i])
                    }
                    if cachedAhead + missingCards.count >= 3 {
                        break
                    }
                }
            }
            
            let neededCards = max(0, 3 - cachedAhead)
            missingCards = Array(missingCards.prefix(neededCards))
            guard !missingCards.isEmpty else { return }

            let apiKey = self.geminiApiKey
            var batchedRequests: [GeminiService.BatchChallengeRequest] = []
            let level = self.conjugationLevel
            
            var baseTenses = ["presente"]
            if level >= 2 { baseTenses += ["passato prossimo", "imperfetto", "presente progressivo"] }
            if level >= 3 { baseTenses += ["futuro semplice", "imperativo"] }
            if level >= 4 { baseTenses += ["condizionale presente", "condizionale passato"] }
            if level >= 5 { baseTenses += ["congiuntivo presente", "congiuntivo imperfetto"] }
            
            let pronouns = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
            let stativeVerbs: Set<String> = ["piacere", "sembrare", "sapere", "conoscere", "volere", "potere", "dovere", "credere", "pensare", "amare", "odiare", "preferire", "capire", "ricordare", "dimenticare", "avere", "essere", "bastare", "mancare", "servire", "parere", "importare", "interessare", "costare", "significare", "sperare"]
            let impersonalVerbs: Set<String> = ["piovere", "nevicare", "grandinare", "tuonare", "lampeggiare", "albeggiare", "imbrunire", "piovigginare"]

            let verbs = Array(Set(missingCards.map { $0.userWord.word.italian }))
            let statsByVerb: [String: [ConjugationStat]]
            if verbs.isEmpty {
                statsByVerb = [:]
            } else {
                let placeholders = Array(repeating: "?", count: verbs.count).joined(separator: ",")
                let stats = (try? await DatabaseService.shared.db.read { db in
                    try ConjugationStat.fetchAll(
                        db,
                        sql: "SELECT * FROM conjugationStats WHERE verb IN (\(placeholders))",
                        arguments: StatementArguments(verbs)
                    )
                }) ?? []
                guard !Task.isCancelled else { return }
                statsByVerb = Dictionary(grouping: stats, by: \.verb)
            }
            
            for card in missingCards {
                self.conjugationCache[card.id] = .loading
                let verb = card.userWord.word.italian
                let isStative = stativeVerbs.contains(verb.lowercased())
                let isImpersonal = impersonalVerbs.contains(verb.lowercased())
                // Piacere is practised through its normal dative construction
                // (mi/ti/gli piace), which has no useful direct imperative.
                let isDativeConstruction = verb.caseInsensitiveCompare("piacere") == .orderedSame
                
                var cardTenses = baseTenses
                if isStative {
                    cardTenses.removeAll { $0 == "presente progressivo" }
                }
                if isImpersonal {
                    cardTenses.removeAll { $0 == "imperativo" }
                }
                if isDativeConstruction {
                    cardTenses.removeAll { $0 == "imperativo" }
                }
                
                let stats = statsByVerb[verb] ?? []
                var bestCombo: (tense: String, pronoun: String)?
                var lowestScore: Double = 2.0
                
                var allCombos = cardTenses.flatMap { t -> [(String, String)] in
                    var ps = t == "imperativo" ? pronouns.filter { $0 != "io" } : pronouns
                    if isImpersonal {
                        ps = ["lui/lei"]
                    }
                    return ps.map { p in (t, p) }
                }
                allCombos.shuffle()
                
                for (t, p) in allCombos {
                    let stat = stats.first(where: { $0.tense == t && $0.pronoun == p })
                    if stat == nil || stat!.attempts == 0 {
                        bestCombo = (t, p)
                        break
                    } else if stat!.score < lowestScore {
                        lowestScore = stat!.score
                        bestCombo = (t, p)
                    }
                }
                
                let targetCombo = bestCombo ?? allCombos.randomElement()!
                
                batchedRequests.append(GeminiService.BatchChallengeRequest(
                    id: card.id.uuidString,
                    verb: verb,
                    englishMeaning: card.userWord.word.english,
                    tense: targetCombo.tense,
                    pronoun: targetCombo.pronoun
                ))
            }
            
            if !apiKey.isEmpty {
                if let results = await GeminiService.generateBatchedConjugationChallenges(requests: batchedRequests, apiKey: apiKey) {
                    guard !Task.isCancelled else { return }
                    for result in results {
                        guard let cardId = UUID(uuidString: result.id) else { continue }
                        if self.cards.contains(where: { $0.id == cardId }) {
                            self.conjugationCache[cardId] = .success(sentence: result.sentence, answer: result.answer, explanation: result.explanation ?? "", tense: result.tense ?? "", pronoun: result.pronoun ?? "", englishTranslation: result.englishTranslation ?? "")
                        }
                        batchedRequests.removeAll { $0.id == result.id }
                    }
                }
                if let errorStr = GeminiService.lastErrorMessage {
                    self.geminiError = errorStr
                    GeminiService.lastErrorMessage = nil
                }
            }
            
            for req in batchedRequests {
                guard let cardId = UUID(uuidString: req.id) else { continue }
                let result: (sentence: String, answer: String, explanation: String, tense: String, pronoun: String, englishTranslation: String)?
                
                if !apiKey.isEmpty {
                    result = nil
                } else {
                    result = await AppleIntelligenceService.generateConjugationChallenge(
                        for: req.verb,
                        englishMeaning: req.englishMeaning,
                        tense: req.tense,
                        pronoun: req.pronoun
                    )
                }
                guard !Task.isCancelled else { return }
                
                if let res = result {
                    if self.cards.contains(where: { $0.id == cardId }) {
                        self.conjugationCache[cardId] = .success(sentence: res.sentence, answer: res.answer, explanation: res.explanation, tense: res.tense, pronoun: res.pronoun, englishTranslation: res.englishTranslation)
                    }
                } else {
                    self.conjugationCache[cardId] = .failed
                    if let indexToDowngrade = self.cards.firstIndex(where: { $0.id == cardId }) {
                        self.cards[indexToDowngrade].cardType = .production
                    }
                }
            }
            
            if GeminiService.isRateLimited {
                for i in (0..<self.cards.count).reversed() {
                    let card = self.cards[i]
                    if card.cardType == .conjugation {
                        if self.conjugationCache[card.id] == nil {
                            self.conjugationCache[card.id] = .failed
                            self.cards[i].cardType = .production
                        }
                    }
                }
            }
            
        }
    }

    private func processResult(correct: Bool, context: MistakeContext? = nil) {
        guard currentIndex < cards.count else { return }
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
                let result = schedulingIntent == .familiarityConfirmation && correct
                    ? SM2.acceleratedMastery(for: cards[currentIndex].userWord)
                    : SM2.evaluate(userWord: cards[currentIndex].userWord, correct: correct)
                applyResult(result, to: &cards[currentIndex].userWord)
                if correct && result.interval >= SM2.masteryThreshold {
                    cards[currentIndex].userWord.stage = .mastered
                } else if !correct && stageBeforeAnswer == .mastered {
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
        let movedToMastered = stageBeforeAnswer != .mastered && uwToSave.stage == .mastered
        
        let conjugationReview: ConjugationReviewRecord?
        if cardType == .conjugation, case .success(_, _, _, let tense, let pronoun, _) = conjugationCache[cards[currentIndex].id] {
            conjugationReview = ConjugationReviewRecord(
                verb: cards[currentIndex].userWord.word.italian,
                tense: tense,
                pronoun: pronoun
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
                movedToMastered: movedToMastered,
                conjugation: conjugationReview
            )
        }
        persistenceTask = persistence
        Task { @MainActor [weak self] in
            await persistence.value
            guard let self, self.persistenceGeneration == generation else { return }
            self.persistenceTask = nil
        }
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

    var currentReviewScheduleFeedback: ReviewScheduleFeedback? {
        guard let userWord = currentCard?.userWord, userWord.stage == .mastered else { return nil }
        let interval = userWord.interval
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
