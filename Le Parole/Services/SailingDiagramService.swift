import Foundation

struct WordDiagram: Identifiable, Sendable, Equatable, Decodable {
    let id: String
    let promptImageName: String
    let revealedImageName: String
    let title: String
    let plateName: String
    let plateTitle: String
    let caption: String?
    let hasMatchingFullPlate: Bool

    /// Some source tables are represented only by a focused crop. Never expand
    /// those terms into a different, merely related boat plate.
    var expandedImageName: String {
        hasMatchingFullPlate ? plateName : revealedImageName
    }

    var expandedTitle: String {
        hasMatchingFullPlate ? plateTitle : title
    }
}

/// Maps Italian sailing terms to CVC diagram crops. Data lives in `Data/diagrams.json`.
enum SailingDiagramService {
    /// One diagram plus the lookup keys (normalized Italian terms) that resolve to it.
    private struct Entry: Decodable {
        struct Key: Decodable {
            let text: String
            /// Ordinary Italian words with non-sailing meanings ("coperta", "barra")
            /// match only the whole input, never as part of a longer phrase.
            let exactMatchOnly: Bool

            private enum CodingKeys: String, CodingKey { case text, exactMatchOnly }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = try container.decode(String.self, forKey: .text)
                exactMatchOnly = try container.decodeIfPresent(Bool.self, forKey: .exactMatchOnly) ?? false
            }
        }

        let keys: [Key]
        let diagram: WordDiagram

        private enum CodingKeys: String, CodingKey { case keys }

        init(from decoder: any Decoder) throws {
            keys = try decoder.container(keyedBy: CodingKeys.self).decode([Key].self, forKey: .keys)
            diagram = try WordDiagram(from: decoder)
        }
    }

    private struct Catalog {
        let diagramsByKey: [String: WordDiagram]
        /// Keys usable as the first/last word(s) of a longer phrase, longest first
        /// (ties alphabetical) so the most specific key wins deterministically.
        let phraseKeys: [(key: String, diagram: WordDiagram)]
        let allDiagrams: [WordDiagram]
        let diagramsByPlate: [String: [WordDiagram]]

        init(entries: [Entry]) {
            var byKey: [String: WordDiagram] = [:]
            var phrase: [(key: String, diagram: WordDiagram)] = []
            for entry in entries {
                for key in entry.keys {
                    byKey[key.text] = entry.diagram
                    if !key.exactMatchOnly {
                        phrase.append((key.text, entry.diagram))
                    }
                }
            }
            diagramsByKey = byKey
            phraseKeys = phrase.sorted {
                $0.key.count != $1.key.count ? $0.key.count > $1.key.count : $0.key < $1.key
            }
            allDiagrams = entries.map(\.diagram)
            diagramsByPlate = Dictionary(grouping: allDiagrams, by: \.plateName)
        }

        static func load() -> Catalog {
            guard let url = Bundle.main.url(forResource: "diagrams", withExtension: "json") else {
                assertionFailure("diagrams.json missing from app bundle")
                return Catalog(entries: [])
            }
            do {
                let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
                return Catalog(entries: entries)
            } catch {
                assertionFailure("Failed to decode diagrams.json: \(error)")
                return Catalog(entries: [])
            }
        }
    }

    private static let catalog = Catalog.load()
    private static var lookupCache: [String: WordDiagram?] = [:]

    private static let articles = ["il ", "lo ", "la ", "l'", "i ", "gli ", "le ", "un ", "uno ", "una "]

    private static func normalize(_ str: String) -> String {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let article = articles.first(where: clean.hasPrefix) {
            clean = String(clean.dropFirst(article.count))
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func diagram(for italianWord: String) -> WordDiagram? {
        let norm = normalize(italianWord)
        if let cached = lookupCache[norm] {
            return cached
        }

        let found = catalog.diagramsByKey[norm] ?? catalog.phraseKeys.first { entry in
            norm.hasPrefix(entry.key + " ") || norm.hasSuffix(" " + entry.key)
        }?.diagram

        lookupCache[norm] = found
        return found
    }

    static func visualQuizOptions(for italianWord: String, count: Int = 4) -> (target: WordDiagram, options: [WordDiagram])? {
        guard let target = diagram(for: italianWord) else { return nil }

        var selectedDistractors: [WordDiagram] = []
        var usedPromptImages = Set<String>([target.promptImageName])
        var usedIds = Set<String>([target.id])

        func pick(from candidates: [WordDiagram]) {
            for diag in candidates {
                guard selectedDistractors.count < count - 1 else { break }
                if !usedPromptImages.contains(diag.promptImageName) {
                    selectedDistractors.append(diag)
                    usedPromptImages.insert(diag.promptImageName)
                    usedIds.insert(diag.id)
                }
            }
        }

        // 1. Prioritize distractors from the same diagram plate
        pick(from: (catalog.diagramsByPlate[target.plateName] ?? [])
            .filter { !usedIds.contains($0.id) }
            .shuffled())

        // 2. Fall back to other plates if the same plate has fewer items than needed
        if selectedDistractors.count < count - 1 {
            pick(from: catalog.allDiagrams
                .filter { $0.plateName != target.plateName && !usedIds.contains($0.id) }
                .shuffled())
        }

        var options = selectedDistractors
        options.append(target)
        options.shuffle()

        return (target, options)
    }
}
