import SwiftUI

struct MasteredWordsView: View {
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

    private var sortedWords: [UserWord] {
        words.sorted { $0.word.frequencyRank < $1.word.frequencyRank }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedWords) { uw in
                    MasteredRow(userWord: uw)
                        .listRowBackground(Theme.surface)
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
                        "No mastered words yet",
                        systemImage: "checkmark.seal",
                        description: Text("Words you master will appear here.")
                    )
                }
            }
            .task {
                if let loadWords {
                    words = await loadWords()
                    isLoading = false
                }
            }
            .navigationTitle("Mastered")
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

private struct MasteredRow: View {
    let userWord: UserWord

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
            }
        }
        .padding(.vertical, 2)
    }
}
