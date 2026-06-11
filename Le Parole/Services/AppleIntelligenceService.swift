import Foundation
import FoundationModels
import GRDB
import NaturalLanguage

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

    /// Semantically grades an Italian→English answer. Returns true if the input is a correct
    /// synonym or valid paraphrase. Falls back to false if the model is unavailable.
    static func gradeEnglish(_ input: String, for word: Word) async -> Bool {
        guard isAvailable else { return false }
        let accepted = ([word.english] + word.alternatives).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You are a forgiving semantic grader.
            Does the Student's Answer mean the same thing as the Acceptable Answer?
            Accept synonyms, dropping unnecessary words, or equivalent concepts.
            Output ONLY "yes" or "no".
            
            Examples:
            Acceptable: swiss person | Student: swiss -> yes
            Acceptable: button | Student: brick -> no
            Acceptable: water | Student: h2o -> yes
            Acceptable: to turn off | Student: to turn -> no
            """
        )
        guard let response = try? await session.respond(to: """
            Acceptable: \(accepted) | Student: \(input)
            """
        ) else { return false }
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let clean = content.trimmingCharacters(in: .punctuationCharacters)
        return clean.hasPrefix("yes")
    }

    enum ItalianWordFormResult: String {
        case grammar
        case spelling
        case unrelated
    }

    /// Evaluates if an Italian input is a grammatical variation or a spelling typo of the target.
    static func gradeItalianWordForm(_ input: String, for target: String) async -> ItalianWordFormResult {
        guard isAvailable else { return .unrelated }
        let session = LanguageModelSession(instructions: """
            You are an Italian language grader evaluating a flashcard answer.
            Compare the Student's answer to the Target Italian word.
            Classify the student's answer into one of these 3 categories:
            1. 'grammar': The answer is a valid grammatical variation of the exact same root word (e.g. conjugation, plural/singular form, masculine/feminine variation).
            2. 'spelling': The answer is extremely close to the target word but contains a minor spelling typo (e.g., missing a double letter, wrong vowel, or slight misspelling).
            3. 'unrelated': The answer is a completely different word, or too far off.
            Reply with ONLY ONE word: 'grammar', 'spelling', or 'unrelated'.
            """
        )
        guard let response = try? await session.respond(to: """
            Target Italian word: "\(target)"
            Student's answer: "\(input)"
            """
        ) else { return .unrelated }
        
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if content.contains("grammar") { return .grammar }
        if content.contains("spelling") { return .spelling }
        return .unrelated
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
            return sentence.isEmpty ? nil : sentence
        } catch {
            return nil
        }
        #endif
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
    static func generateExamples(for italianWord: String) async -> [String] {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(2))
        return [
            "Esempio uno per '\(italianWord)'. - Example one for '\(italianWord)'."
        ]
        #else
        guard isAvailable else { return [] }
        
        let session = LanguageModelSession(instructions: """
            You are an Italian language tutor.
            Generate 1 short, highly practical example sentence using the provided Italian word.
            
            Rules:
            1. You MUST generate a full, complete sentence.
            2. The exact provided Italian word MUST literally appear in the Italian sentence.
            3. ALWAYS use the verb 'avere' (to have) for age, hunger, thirst, ecc.
            4. Output ONLY valid JSON in the following format:
            [
              {
                "it": "Italian sentence",
                "en": "English translation"
              }
            ]
            """
        )
        do {
            let response = try await session.respond(to: "Word: \(italianWord)")
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

    static func generateConjugationChallenge(for verb: String, englishMeaning: String, tense requestedTense: String, pronoun requestedPronoun: String) async -> (sentence: String, answer: String, explanation: String, tense: String, pronoun: String, englishTranslation: String)? {
        #if targetEnvironment(simulator)
        try? await Task.sleep(for: .seconds(2))
        return (
            sentence: "Ieri, io e Marco _____ (andare) al cinema.",
            answer: "siamo andati",
            explanation: "The pronoun 'noi' requires the first person plural 'siamo andati' in passato prossimo.",
            tense: "passato prossimo",
            pronoun: "noi",
            englishTranslation: "Yesterday, Marco and I went to the cinema."
        )
        #else
        guard isAvailable else { return nil }

        
        let examplesText = """
        Example input: Verb: mangiare, Tense: presente, Pronoun: noi
        Example output:
        <flashcard>
            <scratchpad>
            Step 1: Conjugate 'mangiare' in 'presente': io mangio, tu mangi, lui/lei mangia, noi mangiamo, voi mangiate, loro mangiano.
            Step 2: Select for 'noi': mangiamo.
            </scratchpad>
            <sentence>Oggi noi _____ (mangiare) una pizza.</sentence>
            <answer>mangiamo</answer>
            <explanation>The sentence uses 'noi' and refers to the present, so 'mangiamo' is required.</explanation>
        </flashcard>
        """
        
        var rulesText = """
        - Use EXACTLY the verb '\(verb)'.
        - <answer> MUST be the exact conjugated verb only (no SUBJECT pronoun like io/tu/lui/noi/voi/loro, no infinitive). If the verb is reflexive (ends in -rsi), you MUST include the reflexive pronoun (mi, ti, si, ci, vi) in the <answer>.
        - Pronoun '\(requestedPronoun)' must match the verb perfectly.
        - INVERTED VERBS (piacere, mancare, bastare, servire, sembrare, importare): The requested pronoun MUST be the GRAMMATICAL SUBJECT of the verb, NOT the indirect object! If the requested pronoun is 'voi', the verb MUST be conjugated for 'voi' (e.g. 'Voi mi mancate', NOT 'Vi manca'). NEVER write a sentence where the requested pronoun is the indirect object.
        - DUAL AUXILIARY VERBS: Some verbs change auxiliary based on meaning. For example, 'mancare' uses ESSERE when meaning 'to be missed by someone' (e.g. 'Lui mi è mancato') but uses AVERE when meaning 'to fail to attend / miss an event' (e.g. 'Lui ha mancato all'appuntamento'). Ensure you use the correct auxiliary for the context you create.
        - REFLEXIVE PRONOUNS: If the verb is reflexive (e.g. 'svegliarsi'), the reflexive pronoun (mi, ti, si, ci, vi) MUST be inside the <answer>. DO NOT write the reflexive pronoun outside the blank in the <sentence>. The blank replaces the ENTIRE conjugated reflexive verb. Incorrect: 'lui si _____ (svegliarsi)'. Correct: 'lui _____ (svegliarsi)'.
        - UNNECESSARY PRONOUNS: DO NOT add unnecessary direct or indirect object pronouns (lo, la, li, le, mi, ti, gli, ci, vi) to the sentence unless the verb strictly requires them (e.g. reflexives). The requested pronoun is the SUBJECT of the sentence.
        - GERUNDIO / STARE + GERUNDIO: NEVER combine stare with a simple present or infinitive. The gerundio ALWAYS ends in -ando or -endo (irregular: facendo, dicendo, bevendo).
        - SUBJECT PRONOUNS: 'loro' means 'they'. NEVER write 'I loro'.
        - SPELLING & ACCENTS: Pay strict attention to spelling! Verbs like 'bere', 'volere', 'venire', 'tenere', 'rimanere' have irregular future/conditional stems (e.g. berrò, vorrò, verrò, terrò, rimarrò). Verify spelling in the <scratchpad> step-by-step.
        - MULTI-WORD VERBS (e.g. 'alzarsi in piedi', 'andare d'accordo'): Put the extra words (e.g. 'in piedi') OUTSIDE the blank in the sentence. The blank and parentheses MUST only contain the root verb. Example sentence: "_____ (alzarsi) in piedi." The answer MUST be only the conjugated root verb (e.g., "ti alzi").
        """

        // Only include the rule for the requested tense — keeps prompt short for on-device model
        let tenseContextRule: String
        switch requestedTense.lowercased() {
        case "passato prossimo":
            tenseContextRule = "Include a specific past time marker: 'ieri', 'stamattina', 'la settimana scorsa', 'poco fa'. Answer = TWO words: auxiliary + past participle (e.g. 'ho mangiato', 'sono andato'). Auxiliary: ESSERE for motion/state verbs (andare, venire, uscire, arrivare, partire, tornare, stare, rimanere, essere, diventare) and reflexive verbs; AVERE for all others. With ESSERE the participle agrees in gender/number (lui è andato, lei è andata, loro sono andati)."
        case "imperfetto":
            tenseContextRule = "Signal habitual/ongoing past: use 'da bambino/a', 'una volta', 'a quei tempi', 'mentre', 'allora', or describe a past state/feeling ('Mi sentivo stanco', 'Avevo fame', 'Era grande'). Do NOT use 'ieri' (that implies passato prossimo). Do NOT use 'ogni giorno', 'spesso', or 'di solito' by themselves as they cause you to accidentally use present tense."
        case "futuro semplice":
            tenseContextRule = "Include a future time marker: 'domani', 'tra una settimana', 'l'anno prossimo', 'fra poco', 'presto'."
        case "imperativo":
            tenseContextRule = "Write the sentence as a direct command to '\(requestedPronoun)'. CRITICAL GRAMMAR RULE: For formal 'lui/lei' and 'loro', the imperative takes the present subjunctive form (e.g. for -are verbs, use -i ending like 'parli', 'basti', 'guardi'. For -ere/-ire verbs, use -a ending like 'legga', 'senta'). Do NOT use time markers that imply the past or habitual action. Make it a direct order or suggestion."
        case "condizionale presente":
            tenseContextRule = "Use a hypothetical or polite context: 'vorrei', 'potrei', 'se potessi...', 'al posto tuo'."
        case "condizionale passato":
            tenseContextRule = "Express a past hypothetical: 'Se avessi saputo...', 'Avrei voluto...', 'Sarebbe stato meglio'."
        case "congiuntivo presente":
            tenseContextRule = "Use a trigger clause: 'penso che', 'spero che', 'è importante che', 'voglio che'."
        case "congiuntivo imperfetto":
            tenseContextRule = "Use a past trigger clause: 'pensavo che', 'volevo che', 'sembrava che', 'sarei felice se'."
        case "presente progressivo":
            tenseContextRule = "Express an action happening RIGHT NOW: include 'in questo momento', 'adesso', or 'proprio ora'. Answer MUST be TWO words: stare conjugated + gerundio. Stare: sto/stai/sta/stiamo/state/stanno. Gerundio: -are→-ando, -ere/-ire→-endo (irregular: fare→facendo, dire→dicendo, bere→bevendo). Example answer for 'io': 'sto mangiando'. The blank replaces both words."
        default:
            tenseContextRule = "Use a natural context that makes the tense clear."
        }
        rulesText += "\n- The sentence MUST contain context that tells the learner to use '\(requestedTense)': \(tenseContextRule)"
        
        let session = LanguageModelSession(instructions: """
            You are an Italian language tutor creating fill-in-the-blank flashcards.

            YOUR TASK: Produce one flashcard for this EXACT conjugation — do not deviate:
            - Verb (infinitive): \(verb) (English meaning: \(englishMeaning))
            - Required tense: \(requestedTense)
            - Required pronoun: \(requestedPronoun)

            STEPS:
            1. In the scratchpad, state the target pronoun, verb, and tense. Then write the correctly conjugated verb.
            2. Write one natural Italian sentence using that exact conjugated form.
            3. Replace the conjugated verb in the sentence with '_____' (5 underscores) immediately followed by the infinitive '\(verb)' in parentheses. The blank MUST always appear as: _____ (\(verb)). Never omit the infinitive.

            RULES:
            \(rulesText)

            Return ONLY this XML:
            <flashcard>
                <scratchpad>
                Conjugation: [\(requestedPronoun) conjugated form]
                </scratchpad>
                <sentence>SCRIVERE_QUI</sentence>
                <answer>conjugated form only</answer>
                <explanation>brief explanation</explanation>
            </flashcard>

            FORMAT EXAMPLES (structure only — use the verb/tense/pronoun specified above, not these):
            \(examplesText)
            """
        )
        for _ in 0..<3 {
            do {
                let response = try await session.respond(to: "Verb: \(verb), Tense: \(requestedTense), Pronoun: \(requestedPronoun)")
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let sStart = content.range(of: "<sentence>", options: .caseInsensitive), let sEnd = content.range(of: "</sentence>", options: .caseInsensitive),
                      let aStart = content.range(of: "<answer>", options: .caseInsensitive), let aEnd = content.range(of: "</answer>", options: .caseInsensitive),
                      let eStart = content.range(of: "<explanation>", options: .caseInsensitive), let eEnd = content.range(of: "</explanation>", options: .caseInsensitive) else {
                    continue
                }
                
                var sentence = String(content[sStart.upperBound..<sEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                // Reject if the model echoed our template placeholder or English instructions
                let sentenceLower = sentence.lowercased()
                if sentenceLower.contains("scrivere_qui") || sentenceLower.contains("write_sentence") ||
                   sentenceLower.contains("your italian") || sentenceLower.contains("blank must") ||
                   sentenceLower.contains("replace this") { continue }
                   
                // Reject if the AI accidentally wrote the sentence in English
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(sentence)
                if recognizer.dominantLanguage == .english { continue }
                let rawAnswer = String(content[aStart.upperBound..<aEnd.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
                let answer = rawAnswer.trimmingCharacters(in: .punctuationCharacters)
                let explanation = String(content[eStart.upperBound..<eEnd.lowerBound]).trimmingCharacters(in: .whitespaces)

                // If the AI accidentally left the answer right next to the blank, remove it
                if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: answer))\\s*_{5}", options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: sentence.utf16.count)
                    sentence = regex.stringByReplacingMatches(in: sentence, options: [], range: range, withTemplate: "_____")
                }
                if let regex = try? NSRegularExpression(pattern: "_{5}\\s*\(NSRegularExpression.escapedPattern(for: answer))\\b", options: .caseInsensitive) {
                    let range = NSRange(location: 0, length: sentence.utf16.count)
                    sentence = regex.stringByReplacingMatches(in: sentence, options: [], range: range, withTemplate: "_____")
                }
                
                // If the AI split the compound answer and left the auxiliary before the blank
                let answerTokens = answer.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if answerTokens.count > 1 {
                    let firstWord = answerTokens[0]
                    if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: firstWord))\\s*_{5}", options: .caseInsensitive) {
                        let range = NSRange(location: 0, length: sentence.utf16.count)
                        sentence = regex.stringByReplacingMatches(in: sentence, options: [], range: range, withTemplate: "_____")
                    }
                }
                
                // If the AI completely forgot to include a blank, replace the answer with a blank
                if !sentence.contains("_____") {
                    if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: answer))\\b", options: .caseInsensitive) {
                        let range = NSRange(location: 0, length: sentence.utf16.count)
                        let matches = regex.matches(in: sentence, options: [], range: range)
                        if let firstMatch = matches.first {
                            let swiftRange = Range(firstMatch.range, in: sentence)!
                            sentence.replaceSubrange(swiftRange, with: "_____ (\(requestedPronoun) - \(verb))")
                        }
                    }
                }
                
                // Normalize: atomically replace _____ (anything) → _____ (verb)
                // This also fixes cases where the sentence contains a different infinitive in the hint
                // e.g. "Voi _____ (vivere) felici..." when verb is "essere" → "Voi _____ (essere) felici..."
                if sentence.contains("_____"),
                   let blankRegex = try? NSRegularExpression(pattern: "_{5}\\s*(?:\\([^)]*\\))?", options: []) {
                    let range = NSRange(location: 0, length: sentence.utf16.count)
                    sentence = blankRegex.stringByReplacingMatches(in: sentence, options: [], range: range,
                                                                    withTemplate: "_____ (\(requestedPronoun) - \(verb))")
                }

                // FINAL SAFETY CHECK: If the sentence still doesn't have a blank, the replacement failed. Reject it.
                if !sentence.contains("_____") {
                    continue
                }
                
                // The AI should not output the exact infinitive as the answer; if it does, it failed to conjugate.
                let cleanVerb = verb.trimmingCharacters(in: .whitespaces).lowercased()
                if answer.lowercased().contains(cleanVerb) {
                    continue
                }

                // Since the AI no longer outputs <tense> and <pronoun> tags for performance reasons, 
                // we simply use the requested values.
                let tense = requestedTense
                let parsedPronoun = requestedPronoun
                
                let qp = requestedPronoun.lowercased().trimmingCharacters(in: .whitespaces)

                // Compound tenses must have a space (two-word answer)
                let tenseLower = requestedTense.lowercased()
                if (tenseLower == "passato prossimo" || tenseLower == "presente progressivo" || tenseLower == "condizionale passato") {
                    let tokens = answer.lowercased().components(separatedBy: .whitespaces)
                    if tokens.count < 2 { continue }
                    
                    if tenseLower == "presente progressivo" {
                        let expectedStare: String
                        switch qp {
                        case "io": expectedStare = "sto"
                        case "tu": expectedStare = "stai"
                        case "lui/lei", "lui", "lei": expectedStare = "sta"
                        case "noi": expectedStare = "stiamo"
                        case "voi": expectedStare = "state"
                        case "loro": expectedStare = "stanno"
                        default: expectedStare = ""
                        }
                        if !expectedStare.isEmpty && !tokens.contains(expectedStare) {
                            continue
                        }
                    } else if tenseLower == "passato prossimo" || tenseLower == "condizionale passato" {
                        let verbLower = verb.lowercased()
                        let essereVerbs = ["andare", "venire", "partire", "tornare", "arrivare", "uscire", "entrare", "stare", "essere", "rimanere", "nascere", "morire", "diventare", "cadere", "costare", "succedere", "scendere", "salire", "piacere", "restare", "sparire", "crescere", "scappare", "durare", "bastare", "mancare", "sembrare", "servire", "dispiacere", "interessare", "sfuggire", "capitare", "occorrere", "parere", "vivere", "correre", "volare", "piovere", "nevicare"]
                        let isEssereSafe = verbLower.hasSuffix("rsi") || essereVerbs.contains(verbLower)

                        let expectedAux: [String]
                        if tenseLower == "passato prossimo" {
                            switch qp {
                            case "io": expectedAux = isEssereSafe ? ["ho", "sono"] : ["ho"]
                            case "tu": expectedAux = isEssereSafe ? ["hai", "sei"] : ["hai"]
                            case "lui/lei", "lui", "lei": expectedAux = isEssereSafe ? ["ha", "è", "e'"] : ["ha"]
                            case "noi": expectedAux = isEssereSafe ? ["abbiamo", "siamo"] : ["abbiamo"]
                            case "voi": expectedAux = isEssereSafe ? ["avete", "siete"] : ["avete"]
                            case "loro": expectedAux = isEssereSafe ? ["hanno", "sono"] : ["hanno"]
                            default: expectedAux = []
                            }
                        } else {
                            switch qp {
                            case "io": expectedAux = isEssereSafe ? ["avrei", "sarei"] : ["avrei"]
                            case "tu": expectedAux = isEssereSafe ? ["avresti", "saresti"] : ["avresti"]
                            case "lui/lei", "lui", "lei": expectedAux = isEssereSafe ? ["avrebbe", "sarebbe"] : ["avrebbe"]
                            case "noi": expectedAux = isEssereSafe ? ["avremmo", "saremmo"] : ["avremmo"]
                            case "voi": expectedAux = isEssereSafe ? ["avreste", "sareste"] : ["avreste"]
                            case "loro": expectedAux = isEssereSafe ? ["avrebbero", "sarebbero"] : ["avrebbero"]
                            default: expectedAux = []
                            }
                        }
                        if !expectedAux.isEmpty && !tokens.contains(where: { expectedAux.contains($0) }) {
                            continue
                        }
                    }
                }

                let ansLower = answer.lowercased()
                // Enforce valid suffixes per pronoun to reject hallucinations where AI changes the pronoun
                let expectedSuffixes: [String]
                if tenseLower == "imperfetto" {
                    switch qp {
                    case "io": expectedSuffixes = ["vo", "ero"]
                    case "tu": expectedSuffixes = ["vi", "eri"]
                    case "lui/lei", "lui", "lei": expectedSuffixes = ["va", "era"]
                    case "noi": expectedSuffixes = ["vamo"] // eravamo ends in vamo
                    case "voi": expectedSuffixes = ["vate"] // eravate ends in vate
                    case "loro": expectedSuffixes = ["vano", "erano"]
                    default: expectedSuffixes = []
                    }
                } else if tenseLower == "condizionale presente" {
                    switch qp {
                    case "io": expectedSuffixes = ["ei"]
                    case "tu": expectedSuffixes = ["esti"]
                    case "lui/lei", "lui", "lei": expectedSuffixes = ["ebbe"]
                    case "noi": expectedSuffixes = ["emmo"]
                    case "voi": expectedSuffixes = ["este"]
                    case "loro": expectedSuffixes = ["ebbero"]
                    default: expectedSuffixes = []
                    }
                } else if tenseLower == "futuro semplice" {
                    switch qp {
                    case "io": expectedSuffixes = ["rò", "ro'"]
                    case "tu": expectedSuffixes = ["rai"]
                    case "lui/lei", "lui", "lei": expectedSuffixes = ["rà", "ra'"]
                    case "noi": expectedSuffixes = ["remo"]
                    case "voi": expectedSuffixes = ["rete"]
                    case "loro": expectedSuffixes = ["ranno"]
                    default: expectedSuffixes = []
                    }
                } else if tenseLower == "imperativo" {
                    switch qp {
                    case "tu": expectedSuffixes = ["a", "i", "ai", "di'", "fa'", "sta'", "va'"]
                    case "lui/lei", "lui", "lei": expectedSuffixes = ["i", "a"]
                    case "noi": expectedSuffixes = ["iamo"]
                    case "voi": expectedSuffixes = ["te"]
                    case "loro": expectedSuffixes = ["no"]
                    default: expectedSuffixes = []
                    }
                } else {
                    expectedSuffixes = []
                }
                
                if !expectedSuffixes.isEmpty && !expectedSuffixes.contains(where: { ansLower.hasSuffix($0) }) {
                    continue
                }
                
                // Enforce reflexive pronouns
                let verbLower = verb.lowercased()
                if verbLower.hasSuffix("rsi") {
                    let reflexives = ["mi", "ti", "si", "ci", "vi"]
                    let tokens = ansLower.components(separatedBy: .whitespaces)
                    var hasReflexive = false
                    for r in reflexives {
                        if tokens.contains(r) { hasReflexive = true; break }
                        // For imperative, the pronoun is attached to the end (e.g. fidanzatevi)
                        if tokens.count == 1 && ansLower.hasSuffix(r) { hasReflexive = true; break }
                    }
                    if !hasReflexive {
                        continue
                    }
                }

                // Detect wrong-verb hallucination: 
                // First check if the NLP lemma of the answer matches the requested verb.
                let tagger = NLTagger(tagSchemes: [.lemma])
                tagger.string = answer
                tagger.setLanguage(.italian, range: answer.startIndex..<answer.endIndex)
                var lemmaMatched = false
                tagger.enumerateTags(in: answer.startIndex..<answer.endIndex, unit: .word, scheme: .lemma) { tag, _ in
                    if let lemma = tag?.rawValue.lowercased(), lemma == verbLower {
                        lemmaMatched = true
                    }
                    return true
                }
                
                // Fallback to stem check if lemma doesn't match (due to Apple NLP bugs like 'ebbi' -> 'ebbio')
                var stemMatched = false
                for suffix in ["are", "ere", "ire"] where verbLower.hasSuffix(suffix) {
                    let stem = String(verbLower.dropLast(suffix.count))
                    if stem.count >= 3 {
                        let stemPrefix = String(stem.prefix(3))
                        let tokens = answer.lowercased().components(separatedBy: .whitespaces)
                        if tokens.contains(where: { $0.hasPrefix(stemPrefix) }) {
                            stemMatched = true
                        }
                    }
                    break
                }
                
                // If the verb is very short (stem < 3) and lemma matching failed, we let it pass to avoid false rejections.
                var stemIsShort = false
                for suffix in ["are", "ere", "ire"] where verbLower.hasSuffix(suffix) {
                    let stem = String(verbLower.dropLast(suffix.count))
                    if stem.count < 3 { stemIsShort = true }
                    break
                }

                if !lemmaMatched && !stemMatched && !stemIsShort {
                    continue
                }

                return (sentence: sentence, answer: answer, explanation: explanation, tense: tense, pronoun: parsedPronoun, englishTranslation: "")
            } catch {
                continue
            }
        }
        return nil
        #endif
    }
    

}
import Foundation

final class GeminiService: Sendable {
    static var lastErrorMessage: String? = nil
    static var lastRateLimitDate: Date? = nil
    static var isRateLimited: Bool {
        if let last = lastRateLimitDate, Date().timeIntervalSince(last) < 60.0 {
            return true
        }
        return false
    }

    actor RateLimiter {
        static let shared = RateLimiter()
        private var lastRequestTime: Date = .distantPast
        
        func waitForNextSlot() async {
            let now = Date()
            let timeSinceLast = now.timeIntervalSince(lastRequestTime)
            let delay: TimeInterval = 5.0 // 12 RPM, super safe limit
            if timeSinceLast < delay {
                let sleepTime = delay - timeSinceLast
                lastRequestTime = now.addingTimeInterval(sleepTime)
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            } else {
                lastRequestTime = now
            }
        }
    }
    
    struct GeminiRequest: Codable {
        let contents: [Content]
        let generationConfig: GenerationConfig
        
        struct Content: Codable {
            let role: String
            let parts: [Part]
        }
        
        struct Part: Codable {
            let text: String
        }
        
        struct GenerationConfig: Codable {
            let responseMimeType: String
        }
    }
    
    struct GeminiResponse: Codable {
        let candidates: [Candidate]?
        let error: GeminiError?
        
        struct Candidate: Codable {
            let content: Content
        }
        
        struct Content: Codable {
            let parts: [Part]
        }
        
        struct Part: Codable {
            let text: String
        }
        
        struct GeminiError: Codable {
            let message: String
        }
    }
    struct BatchChallengeRequest: Codable {
        let id: String
        let verb: String
        let englishMeaning: String
        let tense: String
        let pronoun: String
    }
    
    struct BatchChallengeResponse: Codable {
        let id: String
        var sentence: String
        let answer: String
        let explanation: String?
        let tense: String?
        let pronoun: String?
        let englishTranslation: String?
    }
    
    static func generateConjugationChallenge(for verb: String, englishMeaning: String, tense requestedTense: String, pronoun requestedPronoun: String, apiKey: String, retryCount: Int = 0) async -> (sentence: String, answer: String, explanation: String, tense: String, pronoun: String, englishTranslation: String)? {
        guard !apiKey.isEmpty else {
            print("Gemini API key is empty.")
            return nil
        }
        
        await RateLimiter.shared.waitForNextSlot()
        
        let examplesText = """
        Example input: Verb: mangiare (English meaning: to eat), Tense: presente, Pronoun: noi
        Example output:
        {
          "scratchpad": "Step 1: Conjugate 'mangiare' in 'presente': io mangio, tu mangi, lui/lei mangia, noi mangiamo, voi mangiate, loro mangiano. Step 2: Select for 'noi': mangiamo.",
          "sentence": "Oggi noi _____ (mangiare) una pizza.",
          "answer": "mangiamo",
          "explanation": "The sentence uses 'noi' and refers to the present, so 'mangiamo' is required.",
          "englishTranslation": "Today we are eating a pizza."
        }
        """
        
        var rulesText = """
        - Use EXACTLY the verb '\(verb)'.
        - 'answer' MUST be the exact conjugated verb only (no SUBJECT pronoun like io/tu/lui/noi/voi/loro, no infinitive). If the verb is reflexive (ends in -rsi), you MUST include the reflexive pronoun (mi, ti, si, ci, vi) in the 'answer'.
        - Pronoun '\(requestedPronoun)' must match the verb perfectly.
        - CONGIUNTIVO TRIGGERS: NEVER use phrases like 'sperare che', 'pensare che', 'credere che', 'aspettarsi che', 'volere che' UNLESS the requested tense is explicitly 'congiuntivo'. If the requested tense is 'imperfetto', 'passato prossimo', or 'presente', you MUST NOT use verbs of opinion or expectation + 'che' because they grammatically require the subjunctive, which makes the sentence incorrect.
        - INVERTED VERBS (piacere, mancare, bastare, servire, sembrare, importare): The requested pronoun MUST be the GRAMMATICAL SUBJECT of the verb, NOT the indirect object! If the requested pronoun is 'voi', the verb MUST be conjugated for 'voi' (e.g. 'Voi mi mancate', NOT 'Vi manca'). NEVER write a sentence where the requested pronoun is the indirect object.
        - DUAL AUXILIARY VERBS: Some verbs change auxiliary based on meaning. For example, 'mancare' uses ESSERE when meaning 'to be missed by someone' (e.g. 'Lui mi è mancato') but uses AVERE when meaning 'to fail to attend / miss an event' (e.g. 'Lui ha mancato all'appuntamento'). Ensure you use the correct auxiliary for the context you create.
        - REFLEXIVE PRONOUNS: If the verb is reflexive (e.g. 'svegliarsi'), the reflexive pronoun (mi, ti, si, ci, vi) MUST be inside the 'answer'. DO NOT write the reflexive pronoun outside the blank in the 'sentence'. The blank replaces the ENTIRE conjugated reflexive verb. Incorrect: 'lui si _____ (svegliarsi)'. Correct: 'lui _____ (svegliarsi)'.
        - UNNECESSARY PRONOUNS: DO NOT add unnecessary direct or indirect object pronouns (lo, la, li, le, mi, ti, gli, ci, vi) to the sentence unless the verb strictly requires them (e.g. reflexives). The requested pronoun is the SUBJECT of the sentence.
        - GERUNDIO / STARE + GERUNDIO: NEVER combine stare with a simple present or infinitive. The gerundio ALWAYS ends in -ando or -endo (irregular: facendo, dicendo, bevendo).
        - SUBJECT PRONOUNS: 'loro' means 'they'. NEVER write 'I loro'.
        - AUXILIARY VERBS & PARTICIPLES: For compound tenses, use ESSERE for motion/state verbs (andare, venire, uscire, arrivare, partire, tornare, stare, rimanere, essere, diventare), intransitive verbs of happening (succedere, capitare), and all reflexive verbs. Use AVERE for all others. With ESSERE, the past participle MUST agree in gender and number with the subject. For 'succedere', the past participle is 'successo' (e.g. è successo).
        - SPELLING & ACCENTS: Pay strict attention to spelling! Verbs like 'bere', 'volere', 'venire', 'tenere', 'rimanere' have irregular future/conditional stems (e.g. berrò, vorrò, verrò, terrò, rimarrò). Verify spelling in the 'scratchpad' step-by-step.
        - MULTI-WORD VERBS (e.g. 'alzarsi in piedi', 'andare d'accordo'): Put the extra words (e.g. 'in piedi') OUTSIDE the blank in the sentence. The blank and parentheses MUST only contain the root verb. Example sentence: "_____ (alzarsi) in piedi." The answer MUST be only the conjugated root verb (e.g., "ti alzi").
        """
        
        let simpleTenses = ["presente", "imperfetto", "futuro semplice", "condizionale presente", "congiuntivo presente", "congiuntivo imperfetto", "imperativo"]
        if simpleTenses.contains(requestedTense.lowercased()) {
            rulesText += "\n- CRITICAL TENSE RULE: '\(requestedTense)' is a SIMPLE tense. The conjugated answer MUST be exactly ONE word (plus reflexive pronoun if applicable). NEVER use auxiliary verbs (essere/avere + past participle) for this tense, otherwise you will accidentally create a compound tense (like passato prossimo or trapassato) which is grammatically incorrect for this prompt."
        }
        
        rulesText += "\n- NATURAL LANGUAGE: Ensure the generated sentence sounds like something a native Italian speaker would actually say in everyday conversation. Avoid overly formal, robotic, or unnatural phrasing."

        let tenseContextRule: String
        switch requestedTense.lowercased() {
        case "passato prossimo":
            tenseContextRule = "Include a specific past time marker: 'ieri', 'stamattina', 'la settimana scorsa', 'poco fa'. Answer = TWO words: auxiliary + past participle (e.g. 'ho mangiato', 'sono andato'). Auxiliary: ESSERE for motion/state verbs (andare, venire, uscire, arrivare, partire, tornare, stare, rimanere, essere, diventare) and reflexive verbs; AVERE for all others. With ESSERE the participle agrees in gender/number (lui è andato, lei è andata, loro sono andati)."
        case "imperfetto":
            tenseContextRule = "Signal habitual/ongoing past: use 'da bambino/a', 'una volta', 'a quei tempi', 'mentre', 'allora', or describe a past state/feeling ('Mi sentivo stanco', 'Avevo fame', 'Era grande'). CRITICAL: Imperfetto is a SIMPLE tense. The answer must be ONE word (plus reflexive pronoun if applicable). DO NOT use auxiliary verbs (essere/avere + past participle) as that creates trapassato prossimo instead (e.g. use 'tornavate', NEVER 'eravate tornati'). Do NOT use 'ieri'."
        case "futuro semplice":
            tenseContextRule = "Include a future time marker: 'domani', 'tra una settimana', 'l'anno prossimo', 'fra poco', 'presto'."
        case "imperativo":
            tenseContextRule = "Write the sentence as a direct command to '\(requestedPronoun)'. CRITICAL GRAMMAR RULE: For formal 'lui/lei' and 'loro', the imperative takes the present subjunctive form (e.g. for -are verbs, use -i ending like 'parli', 'basti', 'guardi'. For -ere/-ire verbs, use -a ending like 'legga', 'senta'). Do NOT use time markers that imply the past or habitual action. Make it a direct order or suggestion."
        case "condizionale presente":
            tenseContextRule = "Use a hypothetical or polite context: 'vorrei', 'potrei', 'se potessi...', 'al posto tuo'."
        case "condizionale passato":
            tenseContextRule = "Express a past hypothetical: 'Se avessi saputo...', 'Avrei voluto...', 'Sarebbe stato meglio'."
        case "congiuntivo presente":
            tenseContextRule = "Use a trigger clause: 'penso che', 'spero che', 'è importante che', 'voglio che'."
        case "congiuntivo imperfetto":
            tenseContextRule = "Use a past trigger clause: 'pensavo che', 'volevo che', 'sembrava che', 'sarei felice se'."
        case "presente progressivo":
            tenseContextRule = "Express an action happening RIGHT NOW: include 'in questo momento', 'adesso', or 'proprio ora'. Answer MUST be TWO words: stare conjugated + gerundio. Stare: sto/stai/sta/stiamo/state/stanno. Gerundio: -are→-ando, -ere/-ire→-endo (irregular: fare→facendo, dire→dicendo, bere→bevendo). Example answer for 'io': 'sto mangiando'. The blank replaces both words."
        default:
            tenseContextRule = "Use a natural context that makes the tense clear."
        }
        rulesText += "\n- The sentence MUST contain context that tells the learner to use '\(requestedTense)': \(tenseContextRule)"
        
        let instructions = """
            You are an Italian language tutor creating fill-in-the-blank flashcards.

            YOUR TASK: Produce one flashcard for this EXACT conjugation — do not deviate:
            - Verb (infinitive): \(verb) (English meaning: \(englishMeaning))
            - Required tense: \(requestedTense)
            - Required pronoun: \(requestedPronoun)

            STEPS:
            1. In the scratchpad, state the target pronoun, verb, and tense. Then write the correctly conjugated verb.
            2. Write one natural Italian sentence using that exact conjugated form.
            3. Replace the conjugated verb in the sentence with '_____' (5 underscores) immediately followed by the infinitive '\(verb)' in parentheses. The blank MUST always appear as: _____ (\(verb)). CRITICAL: If you decide to use the verb reflexively in your sentence (e.g. 'mi sveglio'), you MUST modify the infinitive in the parentheses to be the reflexive form (e.g. '_____ (svegliarsi)', NOT '_____ (svegliare)'). Never omit the infinitive.

            RULES:
            \(rulesText)

            Return ONLY valid JSON using the following structure. Do not return markdown tags.
            {
                "scratchpad": "Conjugation: [\(requestedPronoun) conjugated form]",
                "sentence": "SCRIVERE_QUI",
                "answer": "conjugated form only",
                "explanation": "brief explanation",
                "englishTranslation": "English translation of the generated sentence"
            }

            FORMAT EXAMPLES (structure only — use the verb/tense/pronoun specified above, not these):
            \(examplesText)
            """
            
        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=\(cleanApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanApiKey)") else {
            return (sentence: "Invalid URL string", answer: "error", explanation: "The API key might contain invalid characters.", tense: requestedTense, pronoun: requestedPronoun, englishTranslation: "")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = GeminiRequest(
            contents: [.init(role: "user", parts: [.init(text: instructions)])],
            generationConfig: .init(responseMimeType: "application/json")
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let errorStr = String(data: data, encoding: .utf8) ?? "Unknown Error"
                print("Gemini API Error: \(httpResponse.statusCode) - \(errorStr)")
                return nil
            }
            
            let geminiResponse: GeminiResponse
            do {
                geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            } catch {
                print("Gemini JSON Decode Error: \(error)")
                return nil
            }
            if let text = geminiResponse.candidates?.first?.content.parts.first?.text {
                struct FlashcardResponse: Codable {
                    let sentence: String
                    let answer: String
                    let explanation: String
                    let englishTranslation: String?
                }
                var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanText.hasPrefix("```json") {
                    cleanText = String(cleanText.dropFirst(7))
                } else if cleanText.hasPrefix("```") {
                    cleanText = String(cleanText.dropFirst(3))
                }
                if cleanText.hasSuffix("```") {
                    cleanText = String(cleanText.dropLast(3))
                }
                cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = cleanText.data(using: .utf8) {
                    do {
                        let result = try JSONDecoder().decode(FlashcardResponse.self, from: jsonData)
                        return (
                            sentence: result.sentence,
                            answer: result.answer,
                            explanation: result.explanation,
                            tense: requestedTense,
                            pronoun: requestedPronoun,
                            englishTranslation: result.englishTranslation ?? ""
                        )
                    } catch {
                        print("Flashcard Parse Error: \(error)")
                        return nil
                    }
                } else {
                    return nil
                }
            } else if geminiResponse.error != nil {
                return nil
            } else {
                return nil
            }
            
        } catch {
            print("Gemini Network Exception: \(error)")
            return nil
        }
    }
    
    private static func extractBalancedJSONArray(_ text: String) -> String {
        var depth = 0
        var startIndex: String.Index?
        var endIndex: String.Index?
        var insideString = false
        var escapeNext = false
        
        for (i, char) in text.enumerated() {
            let index = text.index(text.startIndex, offsetBy: i)
            if escapeNext { escapeNext = false; continue }
            if char == "\\" { escapeNext = true; continue }
            if char == "\"" { insideString.toggle(); continue }
            
            if !insideString {
                if char == "[" {
                    if depth == 0 { startIndex = index }
                    depth += 1
                } else if char == "]" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = index
                        break
                    }
                }
            }
        }
        
        if let start = startIndex, let end = endIndex {
            return String(text[start...end])
        }
        return text
    }
    
    private static func processBatchResponses(_ responses: [BatchChallengeResponse], requests: [BatchChallengeRequest]) -> [BatchChallengeResponse] {
        return responses.map { response in
            var processed = response
            if !processed.sentence.contains("_____") {
                let req = requests.first { $0.id == response.id }
                let verb = req?.verb ?? "verbo"
                
                // Try to find the exact answer in the sentence (case-insensitive word match)
                let pattern = "(?i)\\b\\Q\(response.answer)\\E\\b"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: processed.sentence, range: NSRange(location: 0, length: processed.sentence.utf16.count)),
                   let swiftRange = Range(match.range, in: processed.sentence) {
                    processed.sentence.replaceSubrange(swiftRange, with: "_____ (\(verb))")
                } else {
                    // Try matching just the last word of the answer (for reflexives like "si fidanzi")
                    let words = response.answer.split(separator: " ")
                    if words.count > 1, let lastWord = words.last {
                        let pattern2 = "(?i)\\b\\Q\(lastWord)\\E\\b"
                        if let regex2 = try? NSRegularExpression(pattern: pattern2),
                           let match2 = regex2.firstMatch(in: processed.sentence, range: NSRange(location: 0, length: processed.sentence.utf16.count)),
                           let swiftRange = Range(match2.range, in: processed.sentence) {
                            processed.sentence.replaceSubrange(swiftRange, with: "_____ (\(verb))")
                        } else {
                            processed.sentence += "\n\n[_____ (\(verb))]"
                        }
                    } else {
                        processed.sentence += "\n\n[_____ (\(verb))]"
                    }
                }
            }
            return processed
        }
    }
    
    static func generateBatchedConjugationChallenges(requests: [BatchChallengeRequest], apiKey: String, retryCount: Int = 0) async -> [BatchChallengeResponse]? {
        guard !apiKey.isEmpty else { return nil }
        guard !requests.isEmpty else { return [] }
        
        await RateLimiter.shared.waitForNextSlot()
        
        let instructions = """
        You are an Italian language tutor creating fill-in-the-blank flashcards.

        YOUR TASK: Produce \(requests.count) flashcards for the following conjugations.
        Return ONLY a JSON array of objects. Do not return markdown tags.
        
        Each object MUST have the following keys:
        - "id": the exact string ID provided
        - "scratchpad": step-by-step reasoning
        - "sentence": one natural Italian sentence using the conjugated form. Replace the conjugated verb in the sentence with '_____' (5 underscores) immediately followed by the infinitive in parentheses. e.g. "_____ (mangiare)". CRITICAL: If you use the verb reflexively (e.g. 'mi sveglio'), you MUST use the reflexive infinitive in the parentheses (e.g. '_____ (svegliarsi)', NOT '_____ (svegliare)').
        - "answer": the exact conjugated verb only (no subject pronouns unless reflexive)
        - "explanation": brief explanation of why this form is used
        - "tense": the exact tense requested
        - "pronoun": the exact pronoun requested
        - "englishTranslation": an accurate English translation of the full 'sentence'
        
        RULES:
        - INVERTED VERBS (piacere, mancare, bastare, servire, sembrare, importare): The requested pronoun MUST be the GRAMMATICAL SUBJECT of the verb, NOT the indirect object! If the requested pronoun is 'voi', the verb MUST be conjugated for 'voi' (e.g. 'Voi mi mancate'). NEVER write a sentence where the requested pronoun is the indirect object.
        - DUAL AUXILIARY VERBS: Some verbs change auxiliary based on meaning. For example, 'mancare' uses ESSERE when meaning 'to be missed by someone' (e.g. 'Lui mi è mancato') but uses AVERE when meaning 'to fail to attend / miss an event' (e.g. 'Lui ha mancato all'appuntamento'). Ensure you use the correct auxiliary for the context you create.
        - REFLEXIVE PRONOUNS: If the verb is reflexive (e.g. 'svegliarsi'), the reflexive pronoun (mi, ti, si, ci, vi) MUST be inside the 'answer'. DO NOT write the reflexive pronoun outside the blank in the 'sentence'. The blank replaces the ENTIRE conjugated reflexive verb. Incorrect: 'lui si _____ (svegliarsi)'. Correct: 'lui _____ (svegliarsi)'.
        - UNNECESSARY PRONOUNS: DO NOT add unnecessary direct or indirect object pronouns (lo, la, li, le, mi, ti, gli, ci, vi) to the sentence unless the verb strictly requires them (e.g. reflexives). The requested pronoun is the SUBJECT of the sentence.
        - MULTI-WORD VERBS (e.g. 'alzarsi in piedi', 'andare d'accordo'): Put the extra words (e.g. 'in piedi') OUTSIDE the blank in the sentence. The blank and parentheses MUST only contain the root verb. Example sentence: "_____ (alzarsi) in piedi." The answer MUST be only the conjugated root verb (e.g., "ti alzi").
        - CONGIUNTIVO TRIGGERS: NEVER use phrases like 'sperare che', 'pensare che', 'credere che', 'aspettarsi che', 'volere che' UNLESS the requested tense is explicitly 'congiuntivo'. If the requested tense is 'imperfetto', 'passato prossimo', or 'presente', you MUST NOT use verbs of opinion or expectation + 'che'.
        - AUXILIARY VERBS & PARTICIPLES: For compound tenses, use ESSERE for motion/state verbs (andare, venire, uscire, arrivare, partire, tornare, stare, rimanere, essere, diventare), intransitive verbs of happening (succedere, capitare), and all reflexive verbs. Use AVERE for all others. With ESSERE, the past participle MUST agree in gender and number with the subject. For 'succedere', the past participle is 'successo' (e.g. è successo).
        - GENDER AMBIGUITY: If the pronoun is 'io', 'tu', 'noi', or 'voi' AND the verb requires 'essere', the gender is ambiguous. You MUST provide BOTH the masculine and feminine forms in the 'answer' field, separated by a slash (e.g., "sono andato/sono andata", "ci siamo vestiti/ci siamo vestite"). DO NOT use abbreviations like 'andato/a'. Do NOT include gendered adjectives in the 'sentence' that would force one specific gender.
        - TENSES context:
          * presente: Express a current action, habit, or general truth (e.g. oggi, di solito, tutti i giorni). NEVER use past time markers like 'ieri', 'scorso', or 'fa'.
          * passato prossimo: Include a specific past time marker: 'ieri', 'stamattina', 'la settimana scorsa', 'poco fa'. Use correct auxiliary (ESSERE/AVERE).
          * imperfetto: Signal habitual/ongoing past: use 'da bambino', 'una volta', 'mentre', or describe a past state. Do NOT use 'ieri' (implies passato prossimo).
          * futuro semplice: Include a future time marker: 'domani', 'tra una settimana', 'l'anno prossimo'.
          * imperativo: Make it a direct order or suggestion. Use present subjunctive for lui/lei/loro.
          * condizionale: Use hypothetical context (vorrei, potrei, se potessi, al posto tuo).
          * congiuntivo: Use trigger clauses (spero che, penso che, volevo che).
          * presente progressivo: Express an action happening RIGHT NOW (in questo momento, adesso).
        
        FORMAT EXAMPLE:
        [
            {
                "id": "123e4567-e89b-12d3-a456-426614174000",
                "scratchpad": "Conjugation: io mangio",
                "sentence": "Oggi io _____ (mangiare) una pizza.",
                "answer": "mangio",
                "explanation": "The sentence uses 'io' and refers to the present, so 'mangio' is required.",
                "tense": "presente",
                "pronoun": "io",
                "englishTranslation": "Today I eat a pizza."
            }
        ]

        REQUESTS:
        \(requests.map { "- ID: \($0.id) | Verb: \($0.verb) (English: \($0.englishMeaning)) | Tense: \($0.tense) | Pronoun: \($0.pronoun)" }.joined(separator: "\n"))
        """
        
        let cleanApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=\(cleanApiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanApiKey)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = GeminiRequest(
            contents: [.init(role: "user", parts: [.init(text: instructions)])],
            generationConfig: .init(responseMimeType: "application/json")
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                var errorString = "API Error: HTTP \(httpResponse.statusCode)"
                
                struct GeminiErrorResponse: Codable {
                    struct ErrorDetail: Codable {
                        let message: String
                    }
                    let error: ErrorDetail
                }
                
                if let decodedError = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data) {
                    let msg = decodedError.error.message
                    if msg.contains("Quota exceeded") {
                        if msg.contains("retry in") || msg.contains("per minute") {
                            errorString = "API Rate Limit: You've hit the 20 requests/min limit. Please wait about 30 seconds before continuing."
                        } else {
                            errorString = "API Quota Exceeded: You've hit your daily free tier limit for Gemini. Please try again tomorrow."
                        }
                    } else if httpResponse.statusCode == 503 {
                        errorString = "API Overloaded: Google Gemini is currently experiencing high demand. Please try again later."
                    } else {
                        errorString = "API Error: \(msg)"
                    }
                } else if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
                    errorString = "API Error \(httpResponse.statusCode): \(rawString)"
                }
                
                print(errorString)
                if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                    GeminiService.lastRateLimitDate = Date()
                }
                GeminiService.lastErrorMessage = errorString
                return nil
            }
            
            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            if let text = geminiResponse.candidates?.first?.content.parts.first?.text {
                var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanText.hasPrefix("```json") { cleanText = String(cleanText.dropFirst(7)) }
                else if cleanText.hasPrefix("```") { cleanText = String(cleanText.dropFirst(3)) }
                if cleanText.hasSuffix("```") { cleanText = String(cleanText.dropLast(3)) }
                cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
                
                cleanText = extractBalancedJSONArray(cleanText)
                
                // Fix common LLM trailing comma JSON formatting errors
                cleanText = cleanText.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
                cleanText = cleanText.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
                
                if let jsonData = cleanText.data(using: .utf8) {
                    do {
                        let items = try JSONDecoder().decode([BatchChallengeResponse].self, from: jsonData)
                        return processBatchResponses(items, requests: requests)
                    } catch let arrayError {
                        struct Wrapper: Codable {
                            let flashcards: [BatchChallengeResponse]?
                            let cards: [BatchChallengeResponse]?
                            let items: [BatchChallengeResponse]?
                        }
                        if let wrapper = try? JSONDecoder().decode(Wrapper.self, from: jsonData),
                           let items = wrapper.flashcards ?? wrapper.cards ?? wrapper.items {
                            return processBatchResponses(items, requests: requests)
                        }
                        
                        let snakeDecoder = JSONDecoder()
                        snakeDecoder.keyDecodingStrategy = .convertFromSnakeCase
                        if let snakeArray = try? snakeDecoder.decode([BatchChallengeResponse].self, from: jsonData) {
                            return processBatchResponses(snakeArray, requests: requests)
                        }
                        
                        GeminiService.lastErrorMessage = "JSON Error: \(arrayError)\n\nRaw:\n\(cleanText)"
                        print("Gemini JSON Error: \(arrayError)")
                    }
                } else {
                    GeminiService.lastErrorMessage = "Failed to convert response to data"
                }
            } else {
                let rawDataStr = String(data: data, encoding: .utf8) ?? "Unknown Data"
                GeminiService.lastErrorMessage = "Empty response. Missing candidates. Raw: \(rawDataStr)"
            }
            return nil
        } catch {
            print("Gemini Batch Exception: \(error)")
            GeminiService.lastErrorMessage = "Network/Decode Exception: \(error.localizedDescription)"
            return nil
        }
    }
}
