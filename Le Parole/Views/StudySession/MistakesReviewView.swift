import SwiftUI

struct MistakesReviewView: View {
    let words: [MistakeItem]
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0

    private var current: MistakeItem? {
        guard currentIndex < words.count else { return nil }
        return words[currentIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    if let word = current {
                    ProgressView(value: Double(currentIndex + 1), total: Double(words.count))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Text("\(currentIndex + 1) of \(words.count)")
                        .font(.theme(.subheadline))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Spacer()

                    MistakeCard(item: word)

                    Spacer()

                    Button(currentIndex + 1 < words.count ? "Next" : "Done") {
                        if currentIndex + 1 < words.count {
                            currentIndex += 1
                        } else {
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                    }
                }
            }
            .navigationTitle("Review Mistakes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct MistakeCard: View {
    let item: MistakeItem

    var body: some View {
        VStack(spacing: 24) {
            if item.cardType == .conjugation, let context = item.context, let question = context.question, let answer = context.answer {
                VStack(spacing: 6) {
                    Text("Conjugation")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(question.replacingOccurrences(of: "_____", with: answer))
                        .font(Theme.wordPrompt)
                        .multilineTextAlignment(.center)
                }
                
                if let explanation = context.explanation {
                    Divider()
                        .padding(.horizontal, 40)
                    Text(explanation)
                        .font(.theme(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 6) {
                    Text("Italian")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(item.userWord.word.italian)
                        .font(Theme.wordDisplay)
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 6) {
                    Text("English")
                        .font(.theme(.caption))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(item.userWord.word.english)
                        .font(Theme.wordPrompt)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .themeCard(cornerRadius: Theme.prominentCardCornerRadius, elevated: true)
        .padding(.horizontal, 20)
    }
}
