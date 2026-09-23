import SwiftUI

struct InProgressView: View {
    @State private var words: [UserWord] = []
    @State private var isLoading = false
    private let loadWords: (@Sendable () async -> [UserWord])?

    @Environment(\.dismiss) private var dismiss

    init(words: [UserWord]) {
        self._words = State(initialValue: words)
        self._isLoading = State(initialValue: false)
        self.loadWords = nil
    }

    init(loadWords: @escaping @Sendable () async -> [UserWord]) {
        self._words = State(initialValue: [])
        self._isLoading = State(initialValue: true)
        self.loadWords = loadWords
    }

    private var recognitionWords: [UserWord] {
        words.filter { $0.stage == .recognition }
            .sorted { $0.word.frequencyRank < $1.word.frequencyRank }
    }

    private var productionWords: [UserWord] {
        words.filter { $0.stage == .production }
            .sorted { $0.word.frequencyRank < $1.word.frequencyRank }
    }

    var body: some View {
        NavigationStack {
            List {
                if !recognitionWords.isEmpty {
                    Section {
                        ForEach(recognitionWords) { uw in
                            InProgressRow(userWord: uw)
                                .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Label("Recognition", systemImage: "eye")
                    }
                }

                if !productionWords.isEmpty {
                    Section {
                        ForEach(productionWords) { uw in
                            InProgressRow(userWord: uw)
                                .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Label("Production", systemImage: "pencil")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .overlay {
                if isLoading {
                    ProgressView()
                } else if words.isEmpty {
                    ContentUnavailableView(
                        "Nothing in progress",
                        systemImage: "checkmark.circle",
                        description: Text("Words you are actively learning will appear here.")
                    )
                }
            }
            .task {
                if let loadWords {
                    words = await loadWords()
                    isLoading = false
                }
            }
            .navigationTitle("In Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct InProgressRow: View {
    let userWord: UserWord

    private var dueLabel: String {
        let now = Date.now
        let due = userWord.nextReviewDate
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: due)).day ?? 0
        if days <= 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }

    private var dueColor: Color {
        let days = Calendar.current.dateComponents([.day], from: .now, to: userWord.nextReviewDate).day ?? 0
        if days <= 0 { return Theme.production }
        if days <= 1 { return Theme.recognition }
        return .secondary
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(userWord.word.italian)
                    .font(Theme.wordList)
                Text(userWord.word.english)
                    .font(.theme(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(userWord.word.level)
                    .font(.theme(.caption, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.chipBackground)
                    .clipShape(Capsule())
                Text(dueLabel)
                    .font(.theme(.caption))
                    .foregroundStyle(dueColor)
            }
        }
        .padding(.vertical, 2)
    }
}
