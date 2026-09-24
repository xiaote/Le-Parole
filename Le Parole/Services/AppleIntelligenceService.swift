import Foundation
import FoundationModels

struct AppleIntelligenceService {
    private static let validCEFRLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func assessCEFRLevel(for italianWord: String) async -> String? {
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            You assess the CEFR vocabulary level of Italian words.
            Respond with ONLY the level: A1, A2, B1, B2, C1, or C2. Nothing else.
            """
        )
        guard let response = try? await session.respond(to: italianWord) else { return nil }
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return validCEFRLevels.contains(text) ? text : nil
    }

    /// Generates a simple, practical Italian sentence using the target word as a contextual hint.
    static func generateHintSentence(for italianWord: String) async -> String? {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(1))
        return "Questo è un esempio per la parola '\(italianWord)' (SIMULATOR MOCK)."
        #else
        guard isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
            Generate exactly one short, simple, natural-sounding Italian sentence that uses the word provided by the user.
            The sentence should be easy to understand for a beginner/intermediate learner.
            Do not include English translations, explanations, or quotes. Just the raw Italian sentence.
            If you cannot fulfill the request because the word is inappropriate, or for any other reason, output exactly "N/A" and nothing else.
            """
        )
        
        do {
            let response = try await session.respond(to: "Word: \(italianWord)")
            let sentence = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty || isRefusal(sentence) ? nil : sentence
        } catch {
            return nil
        }
        #endif
    }

    /// The hint prompts ask the model to output "N/A" when it can't help; treat that as no hint.
    private static func isRefusal(_ text: String) -> Bool {
        let normalized = text.hasSuffix(".") ? String(text.dropLast()) : text
        return normalized.caseInsensitiveCompare("N/A") == .orderedSame
    }

    /// Generates an Italian sentence with the target word blanked out (e.g. "_____").
    static func generateFillInTheBlankHint(for italianWord: String) async -> String? {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(1))
        return "Questo è un _____ di test (SIMULATOR MOCK)."
        #else
        guard isAvailable else { return nil }
        let session = LanguageModelSession(instructions: """
            Generate a short, simple Italian sentence that uses the provided Italian word.
            Replace the exact provided word in the sentence with five underscores ("_____").
            Do not include English translations, explanations, or quotes. Just the raw Italian sentence with the blank.
            If you cannot fulfill the request because the word is inappropriate, or for any other reason, output exactly "N/A" and nothing else.
            """
        )
        do {
            let response = try await session.respond(to: "Word: \(italianWord)")
            var sentence = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRefusal(sentence) { return nil }

            // Programmatically enforce that the word is blanked out, in case the AI fails to follow the prompt
            if !sentence.contains("_____") {
                if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: italianWord))\\b", options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: sentence.utf16.count)
                    sentence = regex.stringByReplacingMatches(in: sentence, options: [], range: range, withTemplate: "_____")
                }
            }
            
            return sentence.isEmpty ? nil : sentence
        } catch {
            return nil
        }
        #endif
    }

    struct AIExample: Codable {
        let it: String
        let en: String
    }

    /// Generates 1 example sentence with an English translation for a failed word.
    static func generateExamples(for italianWord: String, englishMeaning: String? = nil, topic: String? = nil) async -> [String] {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(2))
        return [
            "Esempio uno per '\(italianWord)'. - Example one for '\(italianWord)'."
        ]
        #else
        guard isAvailable else { return [] }
        
        var prompt = "Word: \(italianWord)"
        if let englishMeaning, !englishMeaning.isEmpty {
            prompt += " (meaning: \(englishMeaning))"
        }
        if let topic, !topic.isEmpty {
            prompt += " (topic/context: \(topic))"
        }

        let session = LanguageModelSession(instructions: """
            You are an Italian language tutor.
            Generate 1 short, highly practical example sentence using the provided Italian word matching the specified meaning and context.
            
            Rules:
            1. You MUST generate a full, complete sentence.
            2. The exact provided Italian word MUST literally appear in the Italian sentence.
            3. Respect the specific meaning/context provided so words with multiple meanings are used accurately.
            4. ALWAYS use the verb 'avere' (to have) for age, hunger, thirst, ecc.
            5. Output ONLY valid JSON in the following format:
            [
              {
                "it": "Italian sentence",
                "en": "English translation"
              }
            ]
            """
        )
        do {
            let response = try await session.respond(to: prompt)
            var text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if text.hasPrefix("```json") { text = String(text.dropFirst(7)) }
            else if text.hasPrefix("```") { text = String(text.dropFirst(3)) }
            if text.hasSuffix("```") { text = String(text.dropLast(3)) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            text = text.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
            text = text.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
            
            guard let data = text.data(using: .utf8),
                  let examples = try? JSONDecoder().decode([AIExample].self, from: data) else {
                return []
            }
            
            return examples.map { "\($0.it) - \($0.en)" }
        } catch {
            return []
        }
        #endif
    }

    static func generateConjugationChallenge(for verb: String, englishMeaning: String, tense: String, pronoun: String) async -> ConjugationChallenge? {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(2))
        return ConjugationChallenge(
            sentence: "Ieri, io e Marco _____ (andare) al cinema.",
            answer: "siamo andati",
            explanation: "Rule: siamo + andati → siamo andati (essere; plural agreement).",
            tense: "passato prossimo",
            pronoun: "noi",
            englishTranslation: "Yesterday, Marco and I went to the cinema."
        )
        #else
        guard isAvailable else { return nil }

        let session = LanguageModelSession(instructions: """
            You are an Italian language tutor creating fill-in-the-blank flashcards.

            YOUR TASK: Produce one flashcard for this EXACT conjugation — do not deviate:
            - Verb (infinitive): \(verb) (English meaning: \(englishMeaning))
            - Required tense: \(tense)
            - Required pronoun: \(pronoun)

            STEPS:
            1. In the scratchpad, state the target pronoun, verb, and tense. Then write the correctly conjugated verb, checking its spelling step by step.
            2. Write one natural Italian sentence using that exact conjugated form.
            3. Replace the conjugated verb in the sentence with '_____' (5 underscores) immediately followed by the infinitive '\(verb)' in parentheses. The blank MUST always appear as: _____ (\(verb)). Never omit the infinitive.

            RULES:
            - Use EXACTLY the verb '\(verb)'.
            - Pronoun '\(pronoun)' must match the verb perfectly.
            \(ConjugationPrompt.rules)
            - The sentence MUST contain context that tells the learner to use '\(tense)': \(ConjugationPrompt.tenseContext(for: tense))

            Return ONLY this XML:
            <flashcard>
                <scratchpad>
                Conjugation: [\(pronoun) conjugated form]
                </scratchpad>
                <sentence>SCRIVERE_QUI</sentence>
                <answer>conjugated form only</answer>
                <explanation>brief explanation of how the answer is conjugated</explanation>
            </flashcard>

            FORMAT EXAMPLE (structure only — use the verb/tense/pronoun specified above, not these):
            Example input: Verb: mangiare, Tense: presente, Pronoun: noi
            Example output:
            <flashcard>
                <scratchpad>
                Step 1: Conjugate 'mangiare' in 'presente': io mangio, tu mangi, lui/lei mangia, noi mangiamo, voi mangiate, loro mangiano.
                Step 2: Select for 'noi': mangiamo.
                </scratchpad>
                <sentence>Oggi noi _____ (mangiare) una pizza.</sentence>
                <answer>mangiamo</answer>
                <explanation>Rule: mangi- + -iamo → mangiamo (regular -giare; adjacent i written once).</explanation>
            </flashcard>
            """
        )
        let validator = ConjugationValidator(verb: verb, tense: tense, pronoun: pronoun)
        let prompt = "Verb: \(verb), Tense: \(tense), Pronoun: \(pronoun)"
        for _ in 0..<3 {
            guard !Task.isCancelled else { return nil }
            do {
                let response = try await session.respond(to: prompt)
                if let challenge = validator.challenge(from: response.content) {
                    return challenge
                }
            } catch {
                // Retry on model errors, but stop as soon as the caller gives up.
                if error is CancellationError || Task.isCancelled { return nil }
            }
        }
        return nil
        #endif
    }
}
