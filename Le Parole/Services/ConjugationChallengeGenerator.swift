import Foundation

/// A generated fill-in-the-blank conjugation exercise.
nonisolated struct ConjugationChallenge: Sendable, Equatable {
    let sentence: String
    let answer: String
    let explanation: String
    let tense: String
    let pronoun: String
    let englishTranslation: String
}

/// Picks what to practise for a verb and asks the configured provider for a
/// challenge: Gemini when an API key is set, otherwise the on-device model.
enum ConjugationChallengeGenerator {
    private nonisolated static let timeout: Duration = .seconds(12)

    static let pronouns = ["io", "tu", "lui/lei", "noi", "voi", "loro"]

    /// Verbs that rarely describe an action in progress, so no presente progressivo.
    static let stativeVerbs: Set<String> = [
        "piacere", "sembrare", "sapere", "conoscere", "volere", "potere", "dovere", "credere",
        "pensare", "amare", "odiare", "preferire", "capire", "ricordare", "dimenticare", "avere",
        "essere", "bastare", "mancare", "servire", "parere", "importare", "interessare", "costare",
        "significare", "sperare",
    ]

    /// Weather verbs: third person singular only, and no imperative.
    static let impersonalVerbs: Set<String> = [
        "piovere", "nevicare", "grandinare", "tuonare", "lampeggiare", "albeggiare", "imbrunire",
        "piovigginare",
    ]

    static func tenses(forLevel level: Int) -> [String] {
        var tenses = ["presente"]
        if level >= 2 { tenses += ["passato prossimo", "imperfetto", "presente progressivo"] }
        if level >= 3 { tenses += ["futuro semplice", "imperativo"] }
        if level >= 4 { tenses += ["condizionale presente", "condizionale passato"] }
        if level >= 5 { tenses += ["congiuntivo presente", "congiuntivo imperfetto"] }
        return tenses
    }

    /// Chooses a random never-practised tense/pronoun combination, or else the
    /// one with the lowest score.
    static func pickTarget(verb: String, level: Int, stats: [ConjugationStat]) -> (tense: String, pronoun: String) {
        let verbLower = verb.lowercased()
        let isImpersonal = impersonalVerbs.contains(verbLower)
        var tenses = tenses(forLevel: level)
        if stativeVerbs.contains(verbLower) {
            tenses.removeAll { $0 == "presente progressivo" }
        }
        // Piacere is practised through its normal dative construction
        // (mi/ti/gli piace), which has no useful direct imperative.
        if isImpersonal || verbLower == "piacere" {
            tenses.removeAll { $0 == "imperativo" }
        }

        let combos = tenses.flatMap { tense -> [(tense: String, pronoun: String)] in
            let persons = isImpersonal ? ["lui/lei"] : tense == "imperativo" ? pronouns.filter { $0 != "io" } : pronouns
            return persons.map { (tense, $0) }
        }.shuffled()

        var best = combos[0]
        var lowestScore = 2.0
        for combo in combos {
            guard let stat = stats.first(where: { $0.tense == combo.tense && $0.pronoun == combo.pronoun }),
                  stat.attempts > 0 else { return combo }
            if stat.score < lowestScore {
                lowestScore = stat.score
                best = combo
            }
        }
        return best
    }

    /// Returns nil when generation fails or takes longer than the timeout.
    static func generate(
        verb: String,
        englishMeaning: String,
        level: Int,
        stats: [ConjugationStat],
        apiKey: String
    ) async -> ConjugationChallenge? {
        let target = pickTarget(verb: verb, level: level, stats: stats)

        if !apiKey.isEmpty {
            let request = GeminiService.BatchChallengeRequest(
                id: UUID().uuidString,
                verb: verb,
                englishMeaning: englishMeaning,
                tense: target.tense,
                pronoun: target.pronoun
            )
            return await withTimeout {
                await GeminiService.generateBatchedConjugationChallenges(requests: [request], apiKey: apiKey)?[request.id]
            }
        }
        return await withTimeout {
            await AppleIntelligenceService.generateConjugationChallenge(
                for: verb,
                englishMeaning: englishMeaning,
                tense: target.tense,
                pronoun: target.pronoun
            )
        }
    }

    /// Runs `operation`, cancelling it if it hasn't finished before the timeout.
    private nonisolated static func withTimeout<Value: Sendable>(
        _ operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        await withTaskGroup(of: Value?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
