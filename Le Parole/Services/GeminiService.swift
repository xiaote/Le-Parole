import Foundation

/// Gemini REST calls. All state lives on the main actor (the module default),
/// so the static rate-limiting properties need no extra synchronization.
enum GeminiService {
    private static let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent")!
    /// 12 requests per minute, well under the free-tier limit.
    private static let minimumRequestSpacing: TimeInterval = 5
    private static var nextRequestSlot: Date = .distantPast
    private static var lastRateLimitDate: Date?

    static var isRateLimited: Bool {
        guard let last = lastRateLimitDate else { return false }
        return Date().timeIntervalSince(last) < 60
    }

    /// Reserves the next request slot and sleeps until it arrives.
    /// Throws `CancellationError` if the caller is cancelled while waiting.
    private static func waitForNextSlot() async throws {
        let now = Date()
        let slot = max(now, nextRequestSlot)
        nextRequestSlot = slot.addingTimeInterval(minimumRequestSpacing)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        try Task.checkCancellation()
    }

    struct BatchChallengeRequest: Codable, Sendable {
        let id: String
        let verb: String
        let englishMeaning: String
        let tense: String
        let pronoun: String
    }

    /// Generates one challenge per request, keyed by request id. Returns nil
    /// when the request fails or the response doesn't cover every request.
    static func generateBatchedConjugationChallenges(requests: [BatchChallengeRequest], apiKey: String) async -> [String: ConjugationChallenge]? {
        guard !apiKey.isEmpty else { return nil }
        guard !requests.isEmpty else { return [:] }

        do {
            try await waitForNextSlot()

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "x-goog-api-key")
            // Gemini's REST API uses lower-camel-case configuration keys. Keeping
            // that spelling also preserves the response-schema property names.
            request.httpBody = try JSONEncoder().encode(GeminiRequest(
                contents: [.init(role: "user", parts: [.init(text: batchInstructions(for: requests))])],
                generationConfig: .init(responseMimeType: "application/json", responseSchema: BatchChallengeResponseSchema())
            ))

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print(errorDescription(statusCode: httpResponse.statusCode, data: data))
                if httpResponse.statusCode == 429 || httpResponse.statusCode == 503 {
                    lastRateLimitDate = Date()
                }
                return nil
            }

            let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let text = geminiResponse.candidates?.first?.content.parts.first?.text else {
                print("Gemini returned no candidates: \(String(decoding: data, as: UTF8.self))")
                return nil
            }
            // The request carries a responseSchema, so the text is the JSON array itself.
            let items = try JSONDecoder().decode([BatchChallengeResponse].self, from: Data(text.utf8))
            return try validated(items, requests: requests)
        } catch is CancellationError {
            return nil
        } catch {
            print("Gemini conjugation error: \(error)")
            return nil
        }
    }

    private static func batchInstructions(for requests: [BatchChallengeRequest]) -> String {
        var requestedTenses: [String] = []
        for request in requests where !requestedTenses.contains(request.tense) {
            requestedTenses.append(request.tense)
        }
        let tenseContexts = requestedTenses
            .map { "  * \($0): \(ConjugationPrompt.tenseContext(for: $0))" }
            .joined(separator: "\n")
        let requestLines = requests
            .map { "- ID: \($0.id) | Verb: \($0.verb) (English: \($0.englishMeaning)) | Tense: \($0.tense) | Pronoun: \($0.pronoun)" }
            .joined(separator: "\n")

        return """
        You are an Italian language tutor creating fill-in-the-blank flashcards.

        YOUR TASK: Produce \(requests.count) flashcards for the following conjugations.
        Return ONLY a JSON array of objects. Do not return markdown tags.

        Each object MUST have the following keys:
        - "id": the exact string ID provided
        - "sentence": one natural Italian sentence using the conjugated form. Replace the conjugated verb in the sentence with '_____' (5 underscores) immediately followed by the infinitive in parentheses. e.g. "_____ (mangiare)".
        - "answer": the exact conjugated verb only, following the ANSWER rule below
        - "explanation": brief explanation of how the answer is conjugated, following the explanation rules below
        - "tense": echo the exact requested tense character-for-character; never shorten it (for example, "congiuntivo presente", not "congiuntivo")
        - "pronoun": echo the exact requested pronoun character-for-character
        - "englishTranslation": an accurate English translation of the full 'sentence'

        RULES:
        - Use EXACTLY the requested verb, and conjugate it for EXACTLY the requested tense and pronoun.
        \(ConjugationPrompt.rules)
        - TENSE CONTEXT: The sentence MUST contain context that tells the learner to use the requested tense:
        \(tenseContexts)

        FORMAT EXAMPLE:
        [
            {
                "id": "123e4567-e89b-12d3-a456-426614174000",
                "sentence": "Oggi io _____ (mangiare) una pizza.",
                "answer": "mangio",
                "explanation": "Rule: mangi- + -o → mangio (regular -are, io).\\nForms (io→loro): mangio · mangi · mangia · mangiamo · mangiate · mangiano",
                "tense": "presente",
                "pronoun": "io",
                "englishTranslation": "Today I eat a pizza."
            }
        ]

        REQUESTS:
        \(requestLines)
        """
    }

    private static func errorDescription(statusCode: Int, data: Data) -> String {
        struct GeminiErrorResponse: Decodable {
            struct Detail: Decodable { let message: String }
            let error: Detail
        }
        guard let message = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error.message else {
            return "Gemini API error \(statusCode): \(String(decoding: data, as: UTF8.self))"
        }
        if message.contains("Quota exceeded") {
            return message.contains("retry in") || message.contains("per minute")
                ? "Gemini rate limit hit (per-minute quota)."
                : "Gemini daily free-tier quota exceeded."
        }
        if statusCode == 503 { return "Gemini overloaded (HTTP 503)." }
        return "Gemini API error \(statusCode): \(message)"
    }

    // MARK: - Response validation

    private struct BatchResponseValidationError: LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }

    private static func validated(_ responses: [BatchChallengeResponse], requests: [BatchChallengeRequest]) throws -> [String: ConjugationChallenge] {
        guard responses.count == requests.count else {
            throw BatchResponseValidationError(
                description: "Expected \(requests.count) cards but Gemini returned \(responses.count)."
            )
        }

        let requestsByID = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0) })
        var challenges: [String: ConjugationChallenge] = [:]

        for (index, response) in responses.enumerated() {
            let item = "Card at array index \(index) (id \(response.id))"
            guard let request = requestsByID[response.id] else {
                throw BatchResponseValidationError(description: "\(item) has an unknown id.")
            }
            guard challenges[response.id] == nil else {
                throw BatchResponseValidationError(description: "\(item) repeats its id.")
            }
            let fields = [
                ("sentence", response.sentence), ("answer", response.answer),
                ("explanation", response.explanation), ("tense", response.tense),
                ("pronoun", response.pronoun), ("englishTranslation", response.englishTranslation),
            ]
            if let (name, _) = fields.first(where: { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw BatchResponseValidationError(description: "\(item) has an empty \(name).")
            }

            // IDs originate in the app, so the requested tense and pronoun are
            // authoritative. Gemini occasionally returns a broad label such as
            // "congiuntivo" instead of "congiuntivo presente"; persisting that
            // value would show the wrong hint and corrupt tense-level stats.
            challenges[response.id] = ConjugationChallenge(
                sentence: sentenceWithBlank(response.sentence, answer: response.answer, verb: request.verb),
                answer: response.answer,
                explanation: response.explanation,
                tense: request.tense,
                pronoun: request.pronoun,
                englishTranslation: response.englishTranslation
            )
        }
        // Equal counts, known ids and no repeats imply every request was answered.
        return challenges
    }

    /// Inserts the blank if Gemini forgot it: first the whole answer, then just
    /// its last word (for reflexives like "si fidanzi"), else append a blank.
    private static func sentenceWithBlank(_ sentence: String, answer: String, verb: String) -> String {
        guard !sentence.contains("_____") else { return sentence }
        let blank = "_____ (\(verb))"
        var candidates = [answer]
        let words = answer.split(separator: " ")
        if words.count > 1, let lastWord = words.last {
            candidates.append(String(lastWord))
        }
        for candidate in candidates {
            if let range = sentence.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: candidate))\\b",
                options: [.regularExpression, .caseInsensitive]
            ) {
                var result = sentence
                result.replaceSubrange(range, with: blank)
                return result
            }
        }
        return sentence + "\n\n[\(blank)]"
    }

    // MARK: - Wire types

    private struct GeminiRequest: Encodable {
        let contents: [Content]
        let generationConfig: GenerationConfig

        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct GenerationConfig: Encodable {
            let responseMimeType: String
            let responseSchema: BatchChallengeResponseSchema
        }
    }

    private struct GeminiResponse: Decodable {
        let candidates: [Candidate]?

        struct Candidate: Decodable {
            let content: Content
        }

        struct Content: Decodable {
            let parts: [Part]
        }

        struct Part: Decodable {
            let text: String
        }
    }

    private struct BatchChallengeResponse: Decodable {
        let id: String
        let sentence: String
        let answer: String
        let explanation: String
        let tense: String
        let pronoun: String
        let englishTranslation: String
    }

    /// The exact contract sent to Gemini. Requiring every field prevents a
    /// syntactically valid but incomplete object from reaching the decoder.
    private struct BatchChallengeResponseSchema: Encodable {
        let type = "array"
        let items = Item()

        struct Item: Encodable {
            let type = "object"
            let properties = Properties()
            let required = ["id", "sentence", "answer", "explanation", "tense", "pronoun", "englishTranslation"]
        }

        struct Properties: Encodable {
            let id = StringField()
            let sentence = StringField()
            let answer = StringField()
            let explanation = StringField()
            let tense = StringField()
            let pronoun = StringField()
            let englishTranslation = StringField()
        }

        struct StringField: Encodable {
            let type = "string"
        }
    }
}
