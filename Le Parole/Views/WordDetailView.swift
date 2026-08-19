import SwiftUI

struct WordDetailView: View {
    let userWord: UserWord
    @Environment(\.dismiss) private var dismiss

    private var stageLabel: String {
        switch userWord.stage {
        case .new:         "Not started"
        case .skipped:     "Skipped"
        case .recognition: "Recognition"
        case .production:  "Production"
        case .mastered:    "Mastered"
        }
    }

    private var stageIcon: String {
        switch userWord.stage {
        case .new:         "circle"
        case .skipped:     "slash.circle"
        case .recognition: "eye"
        case .production:  "pencil"
        case .mastered:    "checkmark.seal.fill"
        }
    }

    private var stageColor: Color {
        switch userWord.stage {
        case .new:         Color(.systemGray3)
        case .skipped:     Color(.systemGray)
        case .recognition: Theme.recognition
        case .production:  Theme.production
        case .mastered:    Theme.mastered
        }
    }

    private var accuracy: String {
        guard userWord.totalAttempts > 0 else { return "—" }
        let pct = Int((Double(userWord.totalCorrect) / Double(userWord.totalAttempts)) * 100)
        return "\(pct)%"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(userWord.word.italian)
                        .font(Theme.wordDisplay)
                        .multilineTextAlignment(.center)
                        
                    if let pos = userWord.word.partOfSpeech {
                        Text(pos)
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                        
                    Text(userWord.word.english)
                        .font(.theme(.title3))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        
                    if !userWord.word.cleanAlternatives.isEmpty {
                        Text(userWord.word.cleanAlternatives.joined(separator: ", "))
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 12) {
                    Text(userWord.word.level)
                        .font(.theme(.subheadline, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.chipBackground)
                        .clipShape(Capsule())

                    Label(stageLabel, systemImage: stageIcon)
                        .font(.theme(.subheadline, weight: .semibold))
                        .foregroundStyle(stageColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(stageColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                if userWord.totalAttempts > 0 {
                    VStack(spacing: 0) {
                        statRow("Accuracy", value: accuracy)
                        Divider().padding(.leading, 16)
                        statRow("Total attempts", value: "\(userWord.totalAttempts)")
                        if userWord.stage != .new && userWord.stage != .skipped {
                            Divider().padding(.leading, 16)
                            statRow("Next review", value: userWord.nextReviewDate.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .themeCard()
                }

                Spacer()
            }
            .padding(20)
            }
            .navigationTitle("Word Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.theme(.body, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
