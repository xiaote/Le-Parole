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
///
/// Many keys are ordinary Italian words with other meanings ("ancora" = still,
/// "grillo" = cricket). Such keys carry `senses`, English keywords of the
/// nautical meaning; when the caller knows the word's English meanings, the key
/// matches only if one of them mentions a sense keyword.
enum SailingDiagramService {
    /// One diagram plus the lookup keys (normalized Italian terms) that resolve to it.
    private struct Entry: Decodable {
        struct Key: Decodable {
            let text: String
            /// Ordinary Italian words with non-sailing meanings ("coperta", "barra")
            /// match only the whole input, never as part of a longer phrase.
            let exactMatchOnly: Bool
            /// Lowercase English keywords of the nautical meaning; empty = no gating.
            let senses: [String]

            private enum CodingKeys: String, CodingKey { case text, exactMatchOnly, senses }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = try container.decode(String.self, forKey: .text)
                exactMatchOnly = try container.decodeIfPresent(Bool.self, forKey: .exactMatchOnly) ?? false
                senses = try container.decodeIfPresent([String].self, forKey: .senses) ?? []
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

    /// The key an Italian term resolved to, before any sense check.
    private struct Match {
        let key: String
        let senses: [String]
        let diagram: WordDiagram
    }

    private struct Catalog {
        let matchesByKey: [String: Match]
        /// Keys usable as the first/last word(s) of a longer phrase, longest first
        /// (ties alphabetical) so the most specific key wins deterministically.
        let phraseKeys: [Match]
        let allDiagrams: [WordDiagram]
        let diagramsByPlate: [String: [WordDiagram]]

        init(entries: [Entry]) {
            var byKey: [String: Match] = [:]
            var phrase: [Match] = []
            for entry in entries {
                for key in entry.keys {
                    let match = Match(key: key.text, senses: key.senses, diagram: entry.diagram)
                    byKey[key.text] = match
                    if !key.exactMatchOnly {
                        phrase.append(match)
                    }
                }
            }
            matchesByKey = byKey
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
    /// Italian-key resolution only; the sense check is cheap and applied per call.
    private static var lookupCache: [String: Match?] = [:]

    private static let articles = ["il ", "lo ", "la ", "l'", "i ", "gli ", "le ", "un ", "uno ", "una "]

    private static func normalize(_ str: String) -> String {
        var clean = str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let article = articles.first(where: clean.hasPrefix) {
            clean = String(clean.dropFirst(article.count))
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func match(for italianWord: String) -> Match? {
        let norm = normalize(italianWord)
        if let cached = lookupCache[norm] {
            return cached
        }

        let found = catalog.matchesByKey[norm] ?? catalog.phraseKeys.first { entry in
            norm.hasPrefix(entry.key + " ") || norm.hasSuffix(" " + entry.key)
        }

        lookupCache[norm] = found
        return found
    }

    /// True when some meaning contains a sense keyword as a whole word, e.g.
    /// "anchor" in "to anchor" or "cockpit (of a boat)", but not in "anchorage".
    private static func meanings(_ meanings: [String], mention senses: [String]) -> Bool {
        meanings.contains { meaning in
            var text = meaning.trimmingCharacters(in: .whitespaces).lowercased()
            if text.hasPrefix("to ") { text = String(text.dropFirst(3)) }
            return senses.contains { sense in
                text.ranges(of: sense).contains { range in
                    !(range.lowerBound > text.startIndex && text[text.index(before: range.lowerBound)].isLetter)
                        && !(range.upperBound < text.endIndex && text[range.upperBound].isLetter)
                }
            }
        }
    }

    /// Lookup by term alone, for callers that don't know the English meaning
    /// (e.g. related terms inside a sailing concept). Senses are not checked.
    static func diagram(for italianWord: String) -> WordDiagram? {
        match(for: italianWord)?.diagram
    }

    /// Lookup for a vocabulary word: sense-gated keys match only when one of
    /// the word's English meanings is the nautical one.
    static func diagram(for word: Word) -> WordDiagram? {
        guard let match = match(for: word.italian) else { return nil }
        let isNauticalSense = match.senses.isEmpty
            || meanings([word.english] + word.alternatives, mention: match.senses)
        return isNauticalSense ? match.diagram : nil
    }

    static func visualQuizOptions(for word: Word, count: Int = 4) -> (target: WordDiagram, options: [WordDiagram])? {
        guard let target = diagram(for: word) else { return nil }

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
