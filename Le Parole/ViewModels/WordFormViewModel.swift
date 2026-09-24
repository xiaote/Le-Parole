import Foundation
import GRDB
import NaturalLanguage
import Translation

@Observable
final class WordFormViewModel {
    enum Mode {
        case add
        case edit(UserWord)
    }

    static let newCategoryTag = "__new__"

    let mode: Mode

    var italian: String {
        didSet { if italian != oldValue { italianChanged() } }
    }
    var english: String
    var alternatives: [String]
    var selectedCategory: String
    var newCategoryName = ""

    private(set) var customCategories: [String] = []
    private(set) var isDuplicate = false
    private(set) var isConjugated = false
    private(set) var isTranslating = false
    private(set) var isAssessingLevel = false
    private(set) var translationConfig: TranslationSession.Configuration?
    /// True while a debounced duplicate/conjugation check is pending, so a
    /// stale result can't enable saving.
    private var isValidating = false

    private var validationTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            italian = ""
            english = ""
            alternatives = []
            selectedCategory = Word.cefrLevels[0]
        case .edit(let userWord):
            italian = userWord.word.italian
            english = userWord.word.english
            alternatives = userWord.word.alternatives
            selectedCategory = userWord.word.level
        }
    }

    var editingWord: Word? {
        if case .edit(let userWord) = mode { userWord.word } else { nil }
    }

    var allCategories: [String] { Word.cefrLevels + customCategories }

    var trimmedItalian: String { italian.trimmingCharacters(in: .whitespaces) }

    private var effectiveCategory: String {
        selectedCategory == Self.newCategoryTag
            ? newCategoryName.trimmingCharacters(in: .whitespaces)
            : selectedCategory
    }

    var canSave: Bool {
        !trimmedItalian.isEmpty
            && !english.trimmingCharacters(in: .whitespaces).isEmpty
            && !isValidating
            && !isDuplicate
            && !isConjugated
            && (selectedCategory != Self.newCategoryTag
                || !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    // MARK: - Loading & validation

    func load() async {
        scheduleValidation(delay: .zero)
        let levels = (try? await DatabaseService.shared.db.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT level FROM words")
        }) ?? []
        customCategories = Set(levels).subtracting(Word.cefrLevels).sorted()
    }

    private func italianChanged() {
        scheduleValidation(delay: .milliseconds(250))

        translationTask?.cancel()
        if case .add = mode { english = "" }
        let trimmed = trimmedItalian
        guard !trimmed.isEmpty, trimmed.lowercased() != editingWord?.italian.lowercased() else { return }
        translationTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            // The view's `.translationTask` picks this up and calls `applyTranslation`.
            isTranslating = true
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "it"),
                target: Locale.Language(identifier: "en")
            )
            isAssessingLevel = true
            defer { isAssessingLevel = false }
            if let level = await AppleIntelligenceService.assessCEFRLevel(for: trimmed), !Task.isCancelled {
                selectedCategory = level
            }
        }
    }

    func applyTranslation(_ text: String?) {
        if let text { english = text }
        translationConfig = nil
        isTranslating = false
    }

    private func scheduleValidation(delay: Duration) {
        validationTask?.cancel()
        let text = trimmedItalian.lowercased()
        guard !text.isEmpty else {
            isValidating = false
            isDuplicate = false
            isConjugated = false
            return
        }
        isValidating = true
        let excludedWordID = editingWord?.wordId ?? ""
        validationTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let duplicate = (try? await DatabaseService.shared.db.read { db in
                try Bool.fetchOne(
                    db,
                    // GRDB's swiftLowercaseString folds non-ASCII letters (È/è), unlike NOCASE.
                    sql: "SELECT EXISTS(SELECT 1 FROM words WHERE swiftLowercaseString(italian) = ? AND wordId != ?)",
                    arguments: [text, excludedWordID]
                ) ?? false
            }) ?? false
            guard !Task.isCancelled else { return }
            isDuplicate = duplicate
            isConjugated = Self.looksConjugated(text)
            isValidating = false
        }
    }

    // NLTagger mistakenly lemmas some non-verbs as verbs (e.g. "affatto" -> "affare")
    private static let conjugationFalsePositives: Set<String> = ["affatto"]

    /// Whether a lowercased word looks like a conjugated verb rather than an infinitive.
    private static func looksConjugated(_ word: String) -> Bool {
        guard !conjugationFalsePositives.contains(word) else { return false }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.italian, range: word.startIndex..<word.endIndex)
        let (tag, _) = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma)
        guard let lemma = tag?.rawValue else { return false }
        return (lemma.hasSuffix("are") || lemma.hasSuffix("ere") || lemma.hasSuffix("ire"))
            && lemma.lowercased() != word
    }

    // MARK: - Persistence

    func cancelPendingWork() {
        translationTask?.cancel()
        validationTask?.cancel()
    }

    func save() {
        guard canSave else { return }
        let trimmedEnglish = english.trimmingCharacters(in: .whitespaces)
        let category = effectiveCategory.isEmpty ? "Custom" : effectiveCategory
        let filteredAlternatives = alternatives
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        cancelPendingWork()

        switch mode {
        case .add:
            let word = Word(
                wordId: "user_\(UUID().uuidString)",
                italian: trimmedItalian,
                english: trimmedEnglish,
                alternatives: filteredAlternatives,
                level: category,
                frequencyRank: 0,
                isUserCreated: true
            )
            Task {
                try? await DatabaseService.shared.db.write { db in
                    try word.insert(db)
                    var userWord = UserWord(word: word)
                    try userWord.insert(db)
                }
            }
        case .edit(let userWord):
            var updated = userWord.word
            updated.italian = trimmedItalian
            updated.english = trimmedEnglish
            updated.alternatives = filteredAlternatives
            updated.level = category
            let word = updated
            Task {
                try? await DatabaseService.shared.db.write { db in try word.update(db) }
            }
        }
    }

    func delete() {
        guard let word = editingWord else { return }
        cancelPendingWork()
        Task {
            try? await DatabaseService.shared.db.write { db in _ = try word.delete(db) }
        }
    }
}
