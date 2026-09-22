import Foundation
import GRDB

final class ConceptService: @unchecked Sendable {
    static let shared = ConceptService()

    private let conceptsByWord: [String: WordConcept]

    private init() {
        var concepts: [String: WordConcept] = [:]

        let bundleURL = Bundle.main.url(forResource: "concepts", withExtension: "json")
        let fallbackURL = Bundle.main.bundleURL.appendingPathComponent("concepts.json")

        if let url = bundleURL ?? (FileManager.default.fileExists(atPath: fallbackURL.path) ? fallbackURL : nil),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([WordConcept].self, from: data) {
            for concept in list {
                concepts[concept.italian.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)] = concept
            }
        }
        self.conceptsByWord = concepts
    }

    func concept(for italian: String) -> WordConcept? {
        let cleaned = italian.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = conceptsByWord[cleaned] { return direct }

        // Try stripping articles e.g. "la virata" -> "virata", "il bordo" -> "bordo"
        let articles = ["il ", "lo ", "la ", "l'", "i ", "gli ", "le "]
        for art in articles {
            if cleaned.hasPrefix(art) {
                let stripped = String(cleaned.dropFirst(art.count)).trimmingCharacters(in: .whitespaces)
                if let matched = conceptsByWord[stripped] {
                    return matched
                }
            }
        }
        return nil
    }

    func fetchWord(for italian: String) async -> Word? {
        let candidates = Word.italianLookupCandidates(italian)
        guard !candidates.isEmpty else { return nil }

        return try? await DatabaseService.shared.db.read { db in
            try Word.filter(candidates.contains(Column("italian"))).fetchOne(db)
        }
    }
}
