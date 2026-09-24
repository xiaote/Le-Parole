import SwiftUI

/// Sheet listing words in progress (grouped by stage, with due dates) or mastered words.
struct StageWordsView: View {
    enum Kind {
        case inProgress
        case mastered
    }

    let kind: Kind
    let loadWords: @Sendable () async -> [UserWord]

    @State private var words: [UserWord] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch kind {
                case .inProgress:
                    stageSection(.recognition)
                    stageSection(.production)
                case .mastered:
                    rows(words)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .overlay {
                if isLoading {
                    ProgressView()
                } else if words.isEmpty {
                    switch kind {
                    case .inProgress:
                        ContentUnavailableView(
                            "Nothing in progress",
                            systemImage: "checkmark.circle",
                            description: Text("Words you are actively learning will appear here.")
                        )
                    case .mastered:
                        ContentUnavailableView(
                            "No mastered words yet",
                            systemImage: "checkmark.seal",
                            description: Text("Words you master will appear here.")
                        )
                    }
                }
            }
            .task {
                // Already ordered by frequencyRank in the query.
                words = await loadWords()
                isLoading = false
            }
            .navigationTitle(kind == .inProgress ? "In Progress" : "Mastered")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func stageSection(_ stage: WordStage) -> some View {
        let stageWords = words.filter { $0.stage == stage }
        if !stageWords.isEmpty {
            Section {
                rows(stageWords)
            } header: {
                Label(stage.title, systemImage: stage.iconName)
            }
        }
    }

    private func rows(_ words: [UserWord]) -> some View {
        ForEach(words) { uw in
            StageWordRow(userWord: uw, showsDueDate: kind == .inProgress)
                .listRowBackground(Theme.surface)
        }
    }
}

private struct StageWordRow: View {
    let userWord: UserWord
    let showsDueDate: Bool

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
                LevelChip(level: userWord.word.level)
                if showsDueDate {
                    Text(dueLabel)
                        .font(.theme(.caption))
                        .foregroundStyle(dueColor)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
