import Foundation
import GRDB

struct StudyCard: Identifiable, Sendable {
    let id = UUID()
    var userWord: UserWord
    var cardType: CardType

    enum CardType: Sendable {
        case recognition  // show Italian → type English
        case production   // show English → type Italian
        case conjugation  // dynamic fill-in-the-blank for verbs
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

enum ConjugationFetchStatus: Sendable {
    case loading
    case success(sentence: String, answer: String, explanation: String, tense: String, pronoun: String, englishTranslation: String)
    case failed
}

@Observable
class StudySessionViewModel {
    var cards: [StudyCard] = []
    var conjugationCache: [UUID: ConjugationFetchStatus] = [:]
    var currentIndex: Int = 0
    var stats = SessionStats()
    var isTestMode = false
    var geminiError: String? = nil

    var isComplete: Bool { currentIndex >= cards.count }
    var currentCard: StudyCard? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    func initialize(dailyNewLimit: Int, isTestMode: Bool = false) async {
        self.isTestMode = isTestMode
        let allUserWords = (try? DatabaseService.shared.fetchUserWords()) ?? []
        let extraConjugationCards = (try? await DatabaseService.shared.db.read { db in
            try UserSettings.fetchOne(db)?.extraConjugationCards
        }) ?? 2

        if isTestMode {
            buildTestQueue(from: allUserWords, limit: dailyNewLimit)
        } else {
            buildQueue(from: allUserWords, dailyNewLimit: dailyNewLimit, extraConjugationCards: extraConjugationCards)
        }
        
        await prefetchUpcomingCards()
    }

    private func buildTestQueue(from allUserWords: [UserWord], limit: Int) {
        let now = Date.now
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now

        let eligibleWords = allUserWords.filter { uw in
            uw.stage != .mastered &&
            uw.stage != .skipped &&
            (uw.lastReviewDate == nil || uw.lastReviewDate! < sixDaysAgo) &&
            !((uw.stage == .recognition || uw.stage == .production) && uw.nextReviewDate <= now)
        }

        let sortedWords = sortUserWords(eligibleWords)

        let sample = sortedWords.prefix(limit)
        cards = sample.map { StudyCard(userWord: $0, cardType: .production) }
    }

    private func buildQueue(from allUserWords: [UserWord], dailyNewLimit: Int, extraConjugationCards: Int) {
        let now = Date.now
        let today = Calendar.current.startOfDay(for: now)

        let alreadyLearnedToday = allUserWords.filter {
            guard let d = $0.learnedDate else { return false }
            return Calendar.current.startOfDay(for: d) == today
        }.count
        let remainingNewSlots = max(0, dailyNewLimit - alreadyLearnedToday)

        let recognitionStuck = allUserWords.filter {
            $0.stage == .recognition && $0.nextReviewDate > now
        }
        
        let stuckToDrill = Array(recognitionStuck.shuffled().prefix(3)) // Just drill up to 3 stuck cards without blocking new words
        let actualNewSlots = remainingNewSlots

        let newWordsPool = allUserWords.filter { $0.stage == .new }
        // New vocabulary is introduced from the single, cleaned frequency
        // ordering. CEFR remains a tie-breaker rather than a gate, so useful
        // high-frequency words do not wait behind an arbitrary level backlog.
        let newWords = sortNewWordsForUsefulness(newWordsPool).prefix(actualNewSlots)

        let recognitionDue = allUserWords.filter {
            $0.stage == .recognition && $0.nextReviewDate <= now
        }

        let productionDue = allUserWords.filter {
            ($0.stage == .production || $0.stage == .mastered) && $0.nextReviewDate <= now
        }

        var standardProduction: [UserWord] = []
        var conjugationDue: [UserWord] = []

        let aiAvailable = AppleIntelligenceService.isAvailable
        for uw in productionDue {
            let isVerb = uw.word.english.lowercased().hasPrefix("to ")
            let isMastered = uw.stage == .mastered
            let isProductionWithInterval = uw.stage == .production && uw.interval > 0
            
            if aiAvailable && isVerb && (isMastered || isProductionWithInterval) {
                conjugationDue.append(uw)
            } else {
                standardProduction.append(uw)
            }
        }

        // Production words not yet SM2-due, randomly injected to reinforce retention.
        let srPool = allUserWords.filter {
            $0.stage == .production && $0.nextReviewDate > now
        }
        let srSample = Array(srPool.shuffled().prefix(3))
        
        var standardSrSample: [UserWord] = []
        var conjugationSrSample: [UserWord] = []
        for uw in srSample {
            if aiAvailable && uw.word.english.lowercased().hasPrefix("to ") {
                conjugationSrSample.append(uw)
            } else {
                standardSrSample.append(uw)
            }
        }

        // Guarantee conjugation practice by explicitly pulling a couple known verbs
        if aiAvailable && extraConjugationCards > 0 {
            let knownVerbsNotDue = allUserWords.filter { uw in
                (uw.stage == .production || uw.stage == .mastered) &&
                uw.nextReviewDate > now &&
                uw.word.english.lowercased().hasPrefix("to ") &&
                uw.interval > 0 &&
                !conjugationSrSample.contains(where: { $0.id == uw.id })
            }
            let conjugationExtras = Array(knownVerbsNotDue.shuffled().prefix(extraConjugationCards))
            conjugationSrSample.append(contentsOf: conjugationExtras)
        }

        var queue: [StudyCard] = []
        queue += newWords.map           { StudyCard(userWord: $0, cardType: .recognition) }
        queue += stuckToDrill.map       { StudyCard(userWord: $0, cardType: .recognition) }
        queue += recognitionDue.map     { StudyCard(userWord: $0, cardType: .recognition) }
        queue += standardProduction.map { StudyCard(userWord: $0, cardType: .production) }
        queue += conjugationDue.map     { StudyCard(userWord: $0, cardType: .conjugation) }
        queue += standardSrSample.map   { StudyCard(userWord: $0, cardType: .production) }
        queue += conjugationSrSample.map{ StudyCard(userWord: $0, cardType: .conjugation) }
        // Shuffle, but keep the first 3 slots free of conjugation cards so
        // Apple Intelligence has time to generate them before they're reached.
        let nonConj = queue.filter { $0.cardType != .conjugation }.shuffled()
        let conj    = queue.filter { $0.cardType == .conjugation }.shuffled()
        let buffer  = min(3, nonConj.count)
        cards = Array(nonConj.prefix(buffer))
              + (Array(nonConj.dropFirst(buffer)) + conj).shuffled()
    }

    private func sortUserWords(_ words: [UserWord]) -> [UserWord] {
        let scored = words.map { uw -> (UserWord, Double) in
            (uw, Self.cognateScore(uw.word.italian, uw.word.english))
        }
        return scored.sorted {
            let (w0, score0) = $0
            let (w1, score1) = $1
            
            // User-created words always surface before pre-populated words.
            // Custom categories (not in levelOrder) sort last among user-created.
            if w0.word.isUserCreated != w1.word.isUserCreated {
                return w0.word.isUserCreated
            }
            let l0 = Self.levelOrder[w0.word.level] ?? 99
            let l1 = Self.levelOrder[w1.word.level] ?? 99
            if l0 != l1 { return l0 < l1 }
            if w0.word.frequencyRank != w1.word.frequencyRank {
                return w0.word.frequencyRank < w1.word.frequencyRank
            }
            return score0 > score1
        }.map { $0.0 }
    }

    /// Orders only not-yet-introduced cards. Review and test selection keep the
    /// established ordering, while new built-in vocabulary follows the global
    /// Italian frequency rank. This rank is unique for every bundled word.
    private func sortNewWordsForUsefulness(_ words: [UserWord]) -> [UserWord] {
        let scored = words.map { userWord -> (UserWord, Double) in
            (userWord, Self.cognateScore(userWord.word.italian, userWord.word.english))
        }
        return scored.sorted {
            let (w0, score0) = $0
            let (w1, score1) = $1

            // Your own additions remain the quickest route into a study
            // session. Their frequencyRank is intentionally zero, so they must
            // be handled before the bundled ranking is compared.
            if w0.word.isUserCreated != w1.word.isUserCreated {
                return w0.word.isUserCreated
            }

            if w0.word.frequencyRank != w1.word.frequencyRank {
                return w0.word.frequencyRank < w1.word.frequencyRank
            }

            // Frequency ranks are unique for bundled words. These fallbacks
            // make user-created entries deterministic without treating CEFR as
            // a hard prerequisite for useful vocabulary.
            let l0 = Self.levelOrder[w0.word.level] ?? 99
            let l1 = Self.levelOrder[w1.word.level] ?? 99
            if l0 != l1 { return l0 < l1 }
            return score0 > score1
        }.map { $0.0 }
    }

    func isValidItalianSynonym(input: String) async -> Bool {
        guard let current = currentCard else { return false }
        let targetEnglish = current.userWord.word.english
        let targetAlternatives = current.userWord.word.alternatives
        
        let db = DatabaseService.shared.db
        let isSynonym = try? await db.read { db in
            let allWords = try Word.fetchAll(db)
            let matchingWords = allWords.filter { $0.isCorrectItalian(input) }
            for w in matchingWords {
                if w.isCorrectEnglish(targetEnglish) { return true }
                for alt in targetAlternatives {
                    if w.isCorrectEnglish(alt) { return true }
                }
                if current.userWord.word.isCorrectEnglish(w.english) { return true }
            }
            return false
        }
        return isSynonym ?? false
    }

    func recordResult(correct: Bool, context: MistakeContext? = nil) {
        processResult(correct: correct, context: context)
    }

    func advance() {
        currentIndex += 1
        Task { await prefetchUpcomingCards() }
    }
    
    private var prefetchTask: Task<Void, Never>?
    
    private func prefetchUpcomingCards() async {
        if prefetchTask != nil { return }
        
        prefetchTask = Task { @MainActor in
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
                        if missingCards.count < 8 {
                            missingCards.append(self.cards[i])
                        }
                    }
                }
            }
            
            if cachedAhead >= 3 {
                self.prefetchTask = nil
                return
            }
            
            guard !missingCards.isEmpty else {
                self.prefetchTask = nil
                return
            }
            
            let apiKey = (try? DatabaseService.shared.fetchSettings()?.geminiApiKey) ?? ""
            var batchedRequests: [GeminiService.BatchChallengeRequest] = []
            
            let level = (try? await DatabaseService.shared.db.read { db in
                try UserSettings.fetchOne(db)?.conjugationLevel
            }) ?? 1
            
            var baseTenses = ["presente"]
            if level >= 2 { baseTenses += ["passato prossimo", "imperfetto", "presente progressivo"] }
            if level >= 3 { baseTenses += ["futuro semplice", "imperativo"] }
            if level >= 4 { baseTenses += ["condizionale presente", "condizionale passato"] }
            if level >= 5 { baseTenses += ["congiuntivo presente", "congiuntivo imperfetto"] }
            
            let pronouns = ["io", "tu", "lui/lei", "noi", "voi", "loro"]
            let stativeVerbs = ["piacere", "sembrare", "sapere", "conoscere", "volere", "potere", "dovere", "credere", "pensare", "amare", "odiare", "preferire", "capire", "ricordare", "dimenticare", "avere", "essere", "bastare", "mancare", "servire", "parere", "importare", "interessare", "costare", "significare", "sperare"]
            let impersonalVerbs = ["piovere", "nevicare", "grandinare", "tuonare", "lampeggiare", "albeggiare", "imbrunire", "piovigginare"]
            
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
                
                let stats = (try? DatabaseService.shared.fetchConjugationStats(for: verb)) ?? []
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
            
            self.prefetchTask = nil
        }
    }

    private func processResult(correct: Bool, context: MistakeContext? = nil) {
        guard currentIndex < cards.count else { return }
        let cardType = cards[currentIndex].cardType
        let stageBeforeAnswer = cards[currentIndex].userWord.stage
        let wasIntroducedBeforeAnswer = cards[currentIndex].userWord.learnedDate != nil

        stats.total += 1
        if correct { stats.correct += 1 }

        cards[currentIndex].userWord.totalAttempts += 1
        if correct { cards[currentIndex].userWord.totalCorrect += 1 }
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
                } else {
                    if cards[currentIndex].userWord.stage == .new {
                        cards[currentIndex].userWord.learnedDate = .now
                        cards[currentIndex].userWord.stage = .recognition
                    }
                    cards[currentIndex].userWord.nextReviewDate = SM2.nextReviewDate(interval: 1)
                }

            case .production, .conjugation:
                let result = SM2.evaluate(userWord: cards[currentIndex].userWord, correct: correct)
                applyResult(result, to: &cards[currentIndex].userWord)
                if correct && result.interval >= SM2.masteryThreshold {
                    cards[currentIndex].userWord.stage = .mastered
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
        
        // Record conjugation stats
        var conjVerb: String?
        var conjTense: String?
        var conjPronoun: String?
        
        if cardType == .conjugation, case .success(_, _, _, let tense, let pronoun, _) = conjugationCache[cards[currentIndex].id] {
            conjVerb = cards[currentIndex].userWord.word.italian
            conjTense = tense
            conjPronoun = pronoun
        }

        Task.detached {
            try? await DatabaseService.shared.db.write { db in
                try uwToSave.update(db)
            }
            await DatabaseService.shared.recordReview(
                correct: correct,
                introduced: introduced,
                movedToProduction: movedToProduction,
                movedToMastered: movedToMastered
            )
            if let verb = conjVerb, let tense = conjTense, let pronoun = conjPronoun {
                await DatabaseService.shared.recordConjugationResult(verb: verb, tense: tense, pronoun: pronoun, correct: correct)
            }
        }
    }

    private func applyResult(_ result: SM2Result, to userWord: inout UserWord) {
        userWord.interval      = result.interval
        userWord.easeFactor    = result.easeFactor
        userWord.repetitions   = result.repetitions
        userWord.nextReviewDate = SM2.nextReviewDate(interval: result.interval)
    }

    // MARK: - Progressive ordering helpers

    private static let levelOrder: [String: Int] = ["A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5]

    private static func cognateScore(_ italian: String, _ english: String) -> Double {
        let it = italian.lowercased()
        var en = english.lowercased()
        if en.hasPrefix("to ") { en = String(en.dropFirst(3)) }
        en = en.components(separatedBy: " ").first ?? en
        return bigramDice(it, en)
    }

    private static func bigramDice(_ a: String, _ b: String) -> Double {
        func bigrams(_ s: String) -> [String] {
            let c = Array(s)
            guard c.count >= 2 else { return [] }
            return (0 ..< c.count - 1).map { String([c[$0], c[$0 + 1]]) }
        }
        let ba = bigrams(a), bb = bigrams(b)
        guard !ba.isEmpty, !bb.isEmpty else { return 0 }
        var ca = [String: Int](), cb = [String: Int]()
        ba.forEach { ca[$0, default: 0] += 1 }
        bb.forEach { cb[$0, default: 0] += 1 }
        let shared = ca.reduce(0) { $0 + min($1.value, cb[$1.key] ?? 0) }
        return 2.0 * Double(shared) / Double(ba.count + bb.count)
    }
}
