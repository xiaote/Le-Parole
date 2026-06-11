import SwiftUI
import GRDB
import NaturalLanguage
import Translation

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var allWords: [Word] = []

    @State private var italian = ""
    @State private var english = ""
    @State private var selectedCategory = "A1"
    @State private var newCategoryName = ""
    @State private var alternatives: [String] = []
    @State private var isTranslating = false
    @State private var isAssessingLevel = false
    @State private var translationTask: Task<Void, Never>?
    @State private var translationConfig: TranslationSession.Configuration?

    private static let builtInLevels = ["A1", "A2", "B1", "B2", "C1"]
    private static let newCategoryTag = "__new__"

    private var allCategories: [String] {
        let custom = Set(allWords.map { $0.level })
            .subtracting(Self.builtInLevels)
            .sorted()
        return Self.builtInLevels + custom
    }

    private var effectiveCategory: String {
        selectedCategory == Self.newCategoryTag
            ? newCategoryName.trimmingCharacters(in: .whitespaces)
            : selectedCategory
    }

    private var isDuplicate: Bool {
        let trimmed = italian.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return false }
        return allWords.contains { $0.italian.lowercased() == trimmed }
    }
    
    private var isConjugated: Bool {
        let trimmed = italian.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return false }
        
        // NLTagger mistakenly lemmas some non-verbs as verbs (e.g. "affatto" -> "affare")
        let falsePositives: Set<String> = ["affatto"]
        if falsePositives.contains(trimmed) { return false }
        
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = trimmed
        tagger.setLanguage(.italian, range: trimmed.startIndex..<trimmed.endIndex)
        let (tag, _) = tagger.tag(at: trimmed.startIndex, unit: .word, scheme: .lemma)
        if let lemma = tag?.rawValue {
            if (lemma.hasSuffix("are") || lemma.hasSuffix("ere") || lemma.hasSuffix("ire")) && lemma.lowercased() != trimmed {
                return true
            }
        }
        return false
    }

    private var canSave: Bool {
        !italian.trimmingCharacters(in: .whitespaces).isEmpty
            && !english.trimmingCharacters(in: .whitespaces).isEmpty
            && !isDuplicate
            && !isConjugated
            && (selectedCategory != Self.newCategoryTag
                || !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. ciao", text: $italian)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: italian) { _, newValue in
                            scheduleTranslation(for: newValue)
                        }
                    if isDuplicate {
                        Label("This word is already in your word bank", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if isConjugated {
                        Label("Please add the infinitive form of this verb instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Italian Word")
                }

                Section {
                    HStack {
                        TextField("Translation", text: $english)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if isTranslating {
                            ProgressView().scaleEffect(0.75)
                        }
                    }
                } header: {
                    Text("English Translation")
                } footer: {
                    Text("Auto-filled — edit as needed.")
                }

                Section {
                    ForEach(alternatives.indices, id: \.self) { i in
                        HStack {
                            TextField("Alternative translation", text: $alternatives[i])
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Button { alternatives.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button { alternatives.append("") } label: {
                        Label("Add Alternative", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Alternative Translations")
                } footer: {
                    Text("Other accepted English answers for this word.")
                }

                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { level in
                            Text(level).tag(level)
                        }
                        Text("New Category…").tag(Self.newCategoryTag)
                    }
                    if selectedCategory == Self.newCategoryTag {
                        TextField("e.g. Food, Travel…", text: $newCategoryName)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Category")
                } footer: {
                    if isAssessingLevel {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text("Assessing level…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        translationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveWord() }
                        .disabled(!canSave)
                }
            }
        }
        .task {
            allWords = (try? DatabaseService.shared.db.read { db in try Word.fetchAll(db) }) ?? []
        }
        .translationTask(translationConfig) { session in
            if let response = try? await session.translate(italian.trimmingCharacters(in: .whitespaces)) {
                english = response.targetText
            }
            translationConfig = nil
            isTranslating = false
        }
    }

    // MARK: - Translation

    private func scheduleTranslation(for text: String) {
        translationTask?.cancel()
        english = ""
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        translationTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await fetchTranslation(for: trimmed) }
                group.addTask { await fetchAndApplyLevel(for: trimmed) }
            }
        }
    }

    @MainActor
    private func fetchAndApplyLevel(for word: String) async {
        isAssessingLevel = true
        defer { isAssessingLevel = false }
        if let level = await AppleIntelligenceService.assessCEFRLevel(for: word) {
            selectedCategory = level
        }
    }

    @MainActor
    private func fetchTranslation(for word: String) async {
        isTranslating = true
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "it"),
            target: Locale.Language(identifier: "en")
        )
    }

    // MARK: - Save

    private func saveWord() {
        let trimmedItalian = italian.trimmingCharacters(in: .whitespaces)
        let trimmedEnglish = english.trimmingCharacters(in: .whitespaces)
        let category = effectiveCategory.isEmpty ? "Custom" : effectiveCategory
        guard !trimmedItalian.isEmpty, !trimmedEnglish.isEmpty, !isDuplicate else { return }

        let filteredAlternatives = alternatives
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let word = Word(
            wordId: "user_\(UUID().uuidString)",
            italian: trimmedItalian,
            english: trimmedEnglish,
            alternatives: filteredAlternatives,
            level: category,
            frequencyRank: 0,
            isUserCreated: true
        )
        let newUserWord = UserWord(word: word)
        Task.detached {
            var uw = newUserWord
            try? DatabaseService.shared.db.write { db in
                try word.insert(db)
                try uw.insert(db)
            }
        }
        translationTask?.cancel()
        dismiss()
    }
}
