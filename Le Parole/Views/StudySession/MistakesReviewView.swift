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
            VStack(spacing: 0) {
                if let word = current {
                    ProgressView(value: Double(currentIndex + 1), total: Double(words.count))
                        .padding(.horizontal)
                        .padding(.top, 8)

                    Text("\(currentIndex + 1) of \(words.count)")
                        .font(.subheadline)
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
                    .padding(.horizontal)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("Review Mistakes")
            .navigationBarTitleDisplayMode(.inline)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(question.replacingOccurrences(of: "_____", with: answer))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                }
                
                if let explanation = context.explanation {
                    Divider()
                        .padding(.horizontal, 40)
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 6) {
                    Text("Italian")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(item.userWord.word.italian)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 6) {
                    Text("English")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(item.userWord.word.english)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}
