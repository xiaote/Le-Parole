import SwiftUI

struct MasteredWordsView: View {
    let words: [UserWord]

    @Environment(\.dismiss) private var dismiss

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
                if words.isEmpty {
                    ContentUnavailableView(
                        "No mastered words yet",
                        systemImage: "checkmark.seal",
                        description: Text("Words you master will appear here.")
                    )
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
