import Foundation

final class ConceptService: @unchecked Sendable {
    static let shared = ConceptService()

    private let conceptsByWord: [String: WordConcept]

    private init() {
        var concepts: [String: WordConcept] = [:]

        if let url = Bundle.main.url(forResource: "concepts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([WordConcept].self, from: data) {
            for concept in list {
                concepts[concept.italian.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] = concept
            }
        }
        self.conceptsByWord = concepts
    }

    /// Matches the term as written, then without a leading article ("la virata" -> "virata").
    func concept(for italian: String) -> WordConcept? {
        let cleaned = italian.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return conceptsByWord[cleaned] ?? conceptsByWord[Word.strippingArticle(cleaned)]
    }
}
