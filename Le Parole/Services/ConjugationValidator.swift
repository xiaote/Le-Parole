import Foundation
import NaturalLanguage

/// Cleans up and validates the on-device model's XML flashcard output.
///
/// Create one validator per generation and call `challenge(from:)` for each
/// attempt: it owns an `NLTagger` and `NLLanguageRecognizer`, which are not
/// thread-safe, so an instance must not be shared across concurrent tasks.
nonisolated struct ConjugationValidator {
    let verb: String
    let tense: String
    let pronoun: String

    private let verbLower: String
    /// The non-reflexive infinitive ("svegliarsi" → "svegliare"), which is what
    /// stems and NLP lemmas are based on.
    private let baseVerb: String
    private let tenseLower: String
    private let person: Person?
    private let tagger = NLTagger(tagSchemes: [.lemma])
    private let recognizer = NLLanguageRecognizer()

    init(verb: String, tense: String, pronoun: String) {
        self.verb = verb
        self.tense = tense
        self.pronoun = pronoun
        verbLower = verb.lowercased()
        baseVerb = verbLower.hasSuffix("rsi") ? String(verbLower.dropLast(3)) + "re" : verbLower
        tenseLower = tense.lowercased()
        // Piacere agrees with the thing liked, not the requested (dative)
        // pronoun, so the per-person ending and auxiliary checks don't apply.
        person = verbLower == "piacere" ? nil : Self.persons[pronoun.lowercased().trimmingCharacters(in: .whitespaces)]
    }

    /// Returns the cleaned-up challenge, or nil when the output should be rejected.
    func challenge(from content: String) -> ConjugationChallenge? {
        guard var sentence = Self.tagContent("sentence", in: content),
              let rawAnswer = Self.tagContent("answer", in: content),
              let explanation = Self.tagContent("explanation", in: content) else { return nil }

        // Reject if the model echoed our template placeholder or English instructions.
        let sentenceLower = sentence.lowercased()
        if Self.placeholderMarkers.contains(where: { sentenceLower.contains($0) }) { return nil }

        // Reject if the model accidentally wrote the sentence in English.
        recognizer.reset()
        recognizer.processString(sentence)
        if recognizer.dominantLanguage == .english { return nil }

        let answer = rawAnswer.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let answerTokens = answer.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let escapedAnswer = NSRegularExpression.escapedPattern(for: answer)
        let blankWithVerb = "_____ (\(verb))"

        // If the model left the answer right next to the blank, remove it.
        sentence = Self.replacing("\\b\(escapedAnswer)\\s*_{5}", in: sentence, with: "_____")
        sentence = Self.replacing("_{5}\\s*\(escapedAnswer)\\b", in: sentence, with: "_____")
        // If the model split a compound answer and left the auxiliary before the blank.
        if answerTokens.count > 1 {
            let firstWord = NSRegularExpression.escapedPattern(for: answerTokens[0])
            sentence = Self.replacing("\\b\(firstWord)\\s*_{5}", in: sentence, with: "_____")
        }

        // If the model forgot the blank, blank out the first occurrence of the answer.
        if !sentence.contains("_____"),
           let regex = try? NSRegularExpression(pattern: "\\b\(escapedAnswer)\\b", options: .caseInsensitive),
           let match = regex.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)),
           let range = Range(match.range, in: sentence) {
            sentence.replaceSubrange(range, with: blankWithVerb)
        }
        guard sentence.contains("_____") else { return nil }

        // Normalize "_____ (anything)" to "_____ (verb)"; this also fixes a
        // different infinitive in the hint, e.g. "(vivere)" when the verb is "essere".
        sentence = Self.blankRegex.stringByReplacingMatches(
            in: sentence,
            range: NSRange(sentence.startIndex..., in: sentence),
            withTemplate: NSRegularExpression.escapedTemplate(for: blankWithVerb)
        )

        guard isConjugated(answer),
              hasExpectedAuxiliary(answerTokens),
              hasExpectedEnding(answer),
              hasReflexivePronoun(answer, tokens: answerTokens),
              isFormOfVerb(answer, tokens: answerTokens) else { return nil }

        return ConjugationChallenge(
            sentence: sentence,
            answer: answer,
            explanation: explanation,
            tense: tense,
            pronoun: pronoun,
            englishTranslation: ""
        )
    }

    // MARK: - Checks

    /// The infinitive itself means the model failed to conjugate. Compare whole
    /// tokens: a substring check would wrongly reject valid forms like "faremo" (fare).
    private func isConjugated(_ answer: String) -> Bool {
        let cleanVerb = verb.trimmingCharacters(in: .whitespaces).lowercased()
        let words = answer.split { $0.isWhitespace || $0 == "'" || $0 == "’" }
        return answer != cleanVerb && !words.contains { $0 == cleanVerb }
    }

    /// Compound tenses need two words, with the auxiliary for the requested person.
    private func hasExpectedAuxiliary(_ tokens: [String]) -> Bool {
        let expected: [String]
        switch tenseLower {
        case "presente progressivo":
            expected = person.map { [$0.stare] } ?? []
        case "passato prossimo":
            expected = person.map { usesEssere ? $0.passatoAux : [$0.passatoAux[0]] } ?? []
        case "condizionale passato":
            expected = person.map { usesEssere ? $0.condizionaleAux : [$0.condizionaleAux[0]] } ?? []
        default:
            return true
        }
        guard tokens.count >= 2 else { return false }
        return expected.isEmpty || tokens.contains { expected.contains($0) }
    }

    /// Endings per person reject answers where the model switched pronoun.
    private func hasExpectedEnding(_ answer: String) -> Bool {
        let suffixes: [String]
        switch tenseLower {
        case "imperfetto": suffixes = person?.imperfetto ?? []
        case "condizionale presente": suffixes = person?.condizionale ?? []
        case "futuro semplice": suffixes = person?.futuro ?? []
        case "imperativo": suffixes = person?.imperativo ?? []
        default: suffixes = []
        }
        return suffixes.isEmpty || suffixes.contains { answer.hasSuffix($0) }
    }

    private func hasReflexivePronoun(_ answer: String, tokens: [String]) -> Bool {
        guard verbLower.hasSuffix("rsi") else { return true }
        return Self.reflexivePronouns.contains { pronoun in
            // Imperatives attach the pronoun to the end (e.g. "fidanzatevi").
            tokens.contains(pronoun) || (tokens.count == 1 && answer.hasSuffix(pronoun))
        }
    }

    /// Detects wrong-verb hallucinations with a stem check, falling back to the
    /// NLP lemma (which has its own bugs, e.g. 'ebbi' → 'ebbio'). Very short
    /// stems can't be checked reliably, so they pass.
    private func isFormOfVerb(_ answer: String, tokens: [String]) -> Bool {
        if let ending = ["are", "ere", "ire"].first(where: { baseVerb.hasSuffix($0) }) {
            let stem = baseVerb.dropLast(ending.count)
            if stem.count < 3 { return true }
            let stemPrefix = String(stem.prefix(3))
            if tokens.contains(where: { $0.hasPrefix(stemPrefix) }) { return true }
        }

        tagger.string = answer
        let range = answer.startIndex..<answer.endIndex
        tagger.setLanguage(.italian, range: range)
        var lemmaMatched = false
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma) { tag, _ in
            if let lemma = tag?.rawValue.lowercased(), lemma == baseVerb || lemma == verbLower {
                lemmaMatched = true
            }
            return !lemmaMatched
        }
        return lemmaMatched
    }

    private var usesEssere: Bool {
        verbLower.hasSuffix("rsi") || Self.essereVerbs.contains(verbLower)
    }

    // MARK: - Tables

    /// Per-person forms. The first auxiliary is the avere form; the rest are essere forms.
    private struct Person: Sendable {
        let stare: String
        let passatoAux: [String]
        let condizionaleAux: [String]
        let imperfetto: [String]
        let condizionale: [String]
        let futuro: [String]
        let imperativo: [String]
    }

    private static let persons: [String: Person] = {
        let thirdSingular = Person(
            stare: "sta", passatoAux: ["ha", "è", "e'"], condizionaleAux: ["avrebbe", "sarebbe"],
            imperfetto: ["va", "era"], condizionale: ["ebbe"], futuro: ["rà", "ra'"], imperativo: ["i", "a"]
        )
        return [
            "io": Person(
                stare: "sto", passatoAux: ["ho", "sono"], condizionaleAux: ["avrei", "sarei"],
                imperfetto: ["vo", "ero"], condizionale: ["ei"], futuro: ["rò", "ro'"], imperativo: []
            ),
            "tu": Person(
                stare: "stai", passatoAux: ["hai", "sei"], condizionaleAux: ["avresti", "saresti"],
                imperfetto: ["vi", "eri"], condizionale: ["esti"], futuro: ["rai"],
                imperativo: ["a", "i", "ai", "di'", "fa'", "sta'", "va'"]
            ),
            "lui/lei": thirdSingular,
            "lui": thirdSingular,
            "lei": thirdSingular,
            "noi": Person(
                stare: "stiamo", passatoAux: ["abbiamo", "siamo"], condizionaleAux: ["avremmo", "saremmo"],
                imperfetto: ["vamo"], condizionale: ["emmo"], futuro: ["remo"], imperativo: ["iamo"]
            ),
            "voi": Person(
                stare: "state", passatoAux: ["avete", "siete"], condizionaleAux: ["avreste", "sareste"],
                imperfetto: ["vate"], condizionale: ["este"], futuro: ["rete"], imperativo: ["te"]
            ),
            "loro": Person(
                stare: "stanno", passatoAux: ["hanno", "sono"], condizionaleAux: ["avrebbero", "sarebbero"],
                imperfetto: ["vano", "erano"], condizionale: ["ebbero"], futuro: ["ranno"], imperativo: ["no"]
            ),
        ]
    }()

    private static let essereVerbs: Set<String> = [
        "andare", "venire", "partire", "tornare", "arrivare", "uscire", "entrare", "stare", "essere",
        "rimanere", "nascere", "morire", "diventare", "cadere", "costare", "succedere", "scendere",
        "salire", "piacere", "restare", "sparire", "crescere", "scappare", "durare", "bastare",
        "mancare", "sembrare", "servire", "dispiacere", "interessare", "sfuggire", "capitare",
        "occorrere", "parere", "vivere", "correre", "volare", "piovere", "nevicare",
    ]

    private static let reflexivePronouns = ["mi", "ti", "si", "ci", "vi"]

    private static let placeholderMarkers = [
        "scrivere_qui", "write_sentence", "your italian", "blank must", "replace this",
    ]

    // NSRegularExpression is thread-safe, so sharing compiled patterns is fine.
    private static let blankRegex = try! NSRegularExpression(pattern: "_{5}\\s*(?:\\([^)]*\\))?")

    // MARK: - Helpers

    private static func tagContent(_ tag: String, in content: String) -> String? {
        guard let start = content.range(of: "<\(tag)>", options: .caseInsensitive),
              let end = content.range(of: "</\(tag)>", options: .caseInsensitive, range: start.upperBound..<content.endIndex)
        else { return nil }
        return content[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
