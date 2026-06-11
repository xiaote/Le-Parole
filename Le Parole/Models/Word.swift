import Foundation
import GRDB

struct Word: Identifiable, Sendable, Equatable {
    static let databaseTableName = "words"

    var wordId: String
    var italian: String
    var english: String
    var alternatives: [String]
    var level: String
    var frequencyRank: Int
    var isUserCreated: Bool
    var inflections: String?
    var partOfSpeech: String?

    var id: String { wordId }

    var cleanAlternatives: [String] {
        var main = english.lowercased().trimmingCharacters(in: .whitespaces)
        if main.hasPrefix("to ") { main = String(main.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        
        func normalizeForDedupe(_ s: String) -> String {
            s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        }
        
        var seen = [String: String]()
        seen[normalizeForDedupe(main)] = main
        var result = [String]()
        
        for alt in alternatives {
            var cleanAlt = alt.lowercased().trimmingCharacters(in: .whitespaces)
            if cleanAlt.hasPrefix("to ") { cleanAlt = String(cleanAlt.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            let dedupeKey = normalizeForDedupe(cleanAlt)
            
            if let existing = seen[dedupeKey] {
                let scoreAlt = cleanAlt.filter({ $0 == " " || $0 == "-" }).count
                let scoreExisting = existing.filter({ $0 == " " || $0 == "-" }).count
                if scoreAlt > scoreExisting {
                    seen[dedupeKey] = cleanAlt
                    if existing != main, let idx = result.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == existing }) {
                        result[idx] = alt.trimmingCharacters(in: .whitespaces)
                    }
                }
            } else {
                seen[dedupeKey] = cleanAlt
                result.append(alt.trimmingCharacters(in: .whitespaces))
            }
        }
        return result
    }

    nonisolated init(
        wordId: String,
        italian: String,
        english: String,
        alternatives: [String] = [],
        level: String,
        frequencyRank: Int,
        isUserCreated: Bool = false,
        inflections: String? = nil,
        partOfSpeech: String? = nil
    ) {
        self.wordId = wordId
        self.italian = italian
        self.english = english
        self.alternatives = alternatives
        self.level = level
        self.frequencyRank = frequencyRank
        self.isUserCreated = isUserCreated
        self.inflections = inflections
        self.partOfSpeech = partOfSpeech
    }

    // MARK: - Answer checking

    

    private nonisolated static func normalizeApostrophes(_ str: String) -> String {
        return str.replacingOccurrences(of: "’", with: "'")
                  .replacingOccurrences(of: "`", with: "'")
                  .replacingOccurrences(of: "‘", with: "'")
    }

    private nonisolated static func normalizeEnglish(_ s: String) -> String {
        var t = normalizeApostrophes(s).trimmingCharacters(in: .whitespaces).lowercased()
        
        // Remove any text inside parentheses, e.g. "apple (fruit)" -> "apple"
        if let regex = try? NSRegularExpression(pattern: "\\([^)]*\\)") {
            let range = NSRange(location: 0, length: t.utf16.count)
            t = regex.stringByReplacingMatches(in: t, options: [], range: range, withTemplate: "")
            t = t.trimmingCharacters(in: .whitespaces)
        }
        
        // Strip leading "to " so "have to" matches "to have to" for verb infinitives
        if t.hasPrefix("to ") { t = String(t.dropFirst(3)) }
        let expansions: [(String, String)] = [
            ("aren't",   "are not"), ("can't",    "cannot"),   ("couldn't", "could not"),
            ("didn't",   "did not"), ("doesn't",  "does not"), ("don't",    "do not"),
            ("hadn't",   "had not"), ("hasn't",   "has not"),  ("haven't",  "have not"),
            ("he'd",     "he would"),("he'll",    "he will"),  ("he's",     "he is"),
            ("i'd",      "i would"), ("i'll",     "i will"),   ("i'm",      "i am"),
            ("i've",     "i have"),  ("isn't",    "is not"),   ("it's",     "it is"),
            ("it'd",     "it would"),("let's",    "let us"),   ("mustn't",  "must not"),
            ("needn't",  "need not"),("she'd",    "she would"),("she'll",   "she will"),
            ("she's",    "she is"),  ("shouldn't","should not"),("that's",  "that is"),
            ("there's",  "there is"),("they'd",   "they would"),("they'll", "they will"),
            ("they're",  "they are"),("they've",  "they have"),("wasn't",   "was not"),
            ("we'd",     "we would"),("we'll",    "we will"),  ("we're",    "we are"),
            ("we've",    "we have"), ("weren't",  "were not"), ("what'll",  "what will"),
            ("what're",  "what are"),("what's",   "what is"),  ("what've",  "what have"),
            ("where's",  "where is"),("who'd",    "who would"),("who'll",   "who will"),
            ("who're",   "who are"), ("who's",    "who is"),   ("who've",   "who have"),
            ("won't",    "will not"),("wouldn't", "would not"),("you'd",    "you would"),
            ("you'll",   "you will"),("you're",   "you are"),  ("you've",   "you have")
        ]
        for (abbr, full) in expansions {
            if t == abbr || t.contains(abbr + " ") || t.contains(" " + abbr) {
                t = t.replacingOccurrences(of: abbr, with: full)
            }
        }
        
        return t
    }
    
    /// Normalizes digits in a string to their spelled-out English forms (e.g. "50 years" -> "fifty years")
    /// Also strips hyphens to ensure "twenty-four" matches "twenty four".
    private nonisolated static func normalizeDigitsToWords(_ text: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let regex = try! NSRegularExpression(pattern: "\\d+")
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        var result = text
        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                let numberString = String(text[range])
                if let number = Int(numberString), let spelledOut = formatter.string(from: NSNumber(value: number)) {
                    result.replaceSubrange(range, with: spelledOut.replacingOccurrences(of: "-", with: " "))
                }
            }
        }
        return result.replacingOccurrences(of: "-", with: " ")
    }

    nonisolated func isCorrectEnglish(_ input: String) -> Bool {
        let normalizedInput = Self.normalizeEnglish(input)
        let acceptableAnswers = [english] + alternatives
        
        for ans in acceptableAnswers {
            let normalizedAns = Self.normalizeEnglish(ans)
            if normalizedAns == normalizedInput { return true }
            
            // Convert all digits to spelled-out words and remove hyphens, then compare
            let textAns = Self.normalizeDigitsToWords(normalizedAns)
            let textInput = Self.normalizeDigitsToWords(normalizedInput)
            if textAns == textInput { return true }
            
            // Typo tolerance for English words
            let dist = Self.levenshtein(aStr: textAns, bStr: textInput)
            if textAns.count > 4 && dist <= 1 { return true }
            if textAns.count > 8 && dist <= 2 { return true }
        }
        return false
    }

    private nonisolated static func levenshtein(aStr: String, bStr: String) -> Int {
        let a = Array(aStr)
        let b = Array(bStr)
        
        let aCount = a.count
        let bCount = b.count
        
        if aCount == 0 { return bCount }
        if bCount == 0 { return aCount }
        
        var dist = [[Int]](repeating: [Int](repeating: 0, count: bCount + 1), count: aCount + 1)
        
        for i in 0...aCount { dist[i][0] = i }
        for j in 0...bCount { dist[0][j] = j }
        
        for i in 1...aCount {
            for j in 1...bCount {
                if a[i-1] == b[j-1] {
                    dist[i][j] = dist[i-1][j-1]
                } else {
                    dist[i][j] = min(
                        dist[i-1][j] + 1,
                        dist[i][j-1] + 1,
                        dist[i-1][j-1] + 1
                    )
                }
            }
        }
        return dist[aCount][bCount]
    }

    nonisolated func isCorrectItalian(_ input: String) -> Bool {
        let normalized = Self.normalizeApostrophes(input).trimmingCharacters(in: .whitespaces).lowercased()
        let target = Self.normalizeApostrophes(italian).lowercased()
        if target == normalized { return true }
        
        return target.folding(options: .diacriticInsensitive, locale: nil) ==
               normalized.folding(options: .diacriticInsensitive, locale: nil)
    }

    nonisolated func isInflectionVariant(_ input: String) -> Bool {
        guard let inflections = inflections else { return false }
        let normalized = Self.normalizeApostrophes(input).trimmingCharacters(in: .whitespaces).lowercased()
        
        // Strip prefix "Noun:" or "Adj:"
        let parts = inflections.components(separatedBy: ":")
        guard parts.count > 1 else { return false }
        let formsString = parts[1...].joined(separator: ":")
        
        let forms = formsString.components(separatedBy: ",").map { Self.normalizeApostrophes($0).trimmingCharacters(in: .whitespaces).lowercased() }
        let articles = ["il ", "lo ", "la ", "l'", "i ", "gli ", "le "]
        
        for form in forms {
            var strippedForm = form
            for article in articles {
                if strippedForm.hasPrefix(article) {
                    strippedForm = String(strippedForm.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if strippedForm == normalized || strippedForm.folding(options: .diacriticInsensitive, locale: nil) == normalized.folding(options: .diacriticInsensitive, locale: nil) {
                return true
            }
        }
        return false
    }

    // MARK: - GRDB helpers (nonisolated so GRDB can call from any thread)

    nonisolated static func encodeAlternatives(_ alts: [String]) -> String {
        (try? String(data: JSONEncoder().encode(alts), encoding: .utf8)) ?? "[]"
    }

    nonisolated static func decodeAlternatives(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }
}

// MARK: - GRDB FetchableRecord

extension Word: FetchableRecord {
    nonisolated init(row: Row) throws {
        wordId        = row["wordId"]
        italian       = row["italian"]
        english       = row["english"]
        alternatives  = Word.decodeAlternatives(row["alternatives"])
        level         = row["level"]
        frequencyRank = row["frequencyRank"]
        isUserCreated = row["isUserCreated"]
        inflections   = row["inflections"]
        partOfSpeech  = row["partOfSpeech"]
    }
}

// MARK: - GRDB PersistableRecord

extension Word: PersistableRecord {
    nonisolated func encode(to container: inout PersistenceContainer) throws {
        container["wordId"]        = wordId
        container["italian"]       = italian
        container["english"]       = english
        container["alternatives"]  = Word.encodeAlternatives(alternatives)
        container["level"]         = level
        container["frequencyRank"] = frequencyRank
        container["isUserCreated"] = isUserCreated
        container["inflections"]   = inflections
        container["partOfSpeech"]  = partOfSpeech
    }
}
