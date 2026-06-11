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
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mastered")
            .navigationBarTitleDisplayMode(.inline)
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
                    .font(.body.bold())
                Text(userWord.word.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(userWord.word.level)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}
