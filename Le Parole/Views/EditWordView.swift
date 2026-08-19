import SwiftUI
import GRDB
import NaturalLanguage
import Translation

struct EditWordView: View {
    let userWord: UserWord
    @Environment(\.dismiss) private var dismiss
    @State private var allWords: [Word] = []

    @State private var italian: String
    @State private var english: String
    @State private var alternatives: [String]
    @State private var selectedCategory: String
    @State private var newCategoryName = ""
    @State private var isTranslating = false
    @State private var isAssessingLevel = false
    @State private var translationTask: Task<Void, Never>?
    @State private var translationSession: TranslationSession?
    @State private var showingDeleteAlert = false
    @State private var translationConfig: TranslationSession.Configuration?

    private static let builtInLevels = ["A1", "A2", "B1", "B2", "C1"]
    private static let newCategoryTag = "__new__"

    init(userWord: UserWord) {
        self.userWord = userWord
        _italian = State(initialValue: userWord.word.italian)
        _english = State(initialValue: userWord.word.english)
        _alternatives = State(initialValue: userWord.word.alternatives)
        _selectedCategory = State(initialValue: userWord.word.level)
    }

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
        return allWords.contains { $0.italian.lowercased() == trimmed && $0.wordId != userWord.wordId }
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
                            .font(.theme(.caption))
                            .foregroundStyle(.red)
                    }
                    if isConjugated {
                        Label("Please add the infinitive form of this verb instead.", systemImage: "exclamationmark.triangle.fill")
                            .font(.theme(.caption))
                            .foregroundStyle(Theme.playfulAccent)
                    }
                } header: {
                    Text("Italian word")
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
                    Text("English translation")
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
                        Label("Add alternative", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Alternative translations")
                } footer: {
                    Text("Other accepted English answers for this word.")
                }

                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { level in
                            Text(level).tag(level)
                        }
                        Text("New category…").tag(Self.newCategoryTag)
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
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Text("Delete word")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Edit Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        translationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveWord() }
                        .disabled(!canSave)
                }
            }
        }
        .alert("Delete \"\(userWord.word.italian)\"?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { deleteWord() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This word and all its progress will be permanently deleted.")
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

    private func scheduleTranslation(for text: String) {
        translationTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != userWord.word.italian.lowercased() else { return }
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

    private func deleteWord() {
        let word = userWord.word
        Task.detached {
            try? DatabaseService.shared.db.write { db in
                try word.delete(db)
            }
        }
        translationTask?.cancel()
        dismiss()
    }

    private func saveWord() {
        let trimmedItalian = italian.trimmingCharacters(in: .whitespaces)
        let trimmedEnglish = english.trimmingCharacters(in: .whitespaces)
        let category = effectiveCategory.isEmpty ? "Custom" : effectiveCategory
        guard !trimmedItalian.isEmpty, !trimmedEnglish.isEmpty, !isDuplicate else { return }

        let filteredAlternatives = alternatives
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var updatedWord = userWord.word
        updatedWord.italian = trimmedItalian
        updatedWord.english = trimmedEnglish
        updatedWord.alternatives = filteredAlternatives
        updatedWord.level = category

        Task.detached {
            try? DatabaseService.shared.db.write { db in
                try updatedWord.update(db)
            }
        }
        translationTask?.cancel()
        dismiss()
    }
}
