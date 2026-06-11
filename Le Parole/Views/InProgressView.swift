import SwiftUI

struct InProgressView: View {
    let words: [UserWord]

    @Environment(\.dismiss) private var dismiss

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
                        }
                    } header: {
                        Label("Recognition", systemImage: "eye")
                    }
                }

                if !productionWords.isEmpty {
                    Section {
                        ForEach(productionWords) { uw in
                            InProgressRow(userWord: uw)
                        }
                    } header: {
                        Label("Production", systemImage: "pencil")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("In Progress")
            .navigationBarTitleDisplayMode(.inline)
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
        if days <= 0 { return Theme.primary }
        if days <= 1 { return Theme.primaryLight }
        return .secondary
    }

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
                Text(dueLabel)
                    .font(.caption)
                    .foregroundStyle(dueColor)
            }
        }
        .padding(.vertical, 2)
    }
}
