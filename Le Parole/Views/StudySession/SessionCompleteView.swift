import SwiftUI

struct SessionCompleteView: View {
    let stats: SessionStats
    var isTestMode: Bool = false
    let onDismiss: () -> Void
    @State private var showingMistakes = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "bird")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(Theme.primary)

            Text(isTestMode ? "Test Complete!" : "Session Complete!")
                .font(.title.bold())

            VStack(spacing: 12) {
                ResultRow(label: isTestMode ? "Cards tested" : "Cards reviewed", value: "\(stats.total)")
                ResultRow(label: "Correct",        value: "\(stats.correct)")
                ResultRow(label: "Accuracy",       value: "\(Int(stats.accuracy * 100))%")
                if isTestMode {
                    if stats.correct > 0 {
                        ResultRow(label: "Words mastered", value: "\(stats.correct)")
                            .foregroundStyle(Theme.primaryDark)
                    }
                } else if stats.graduated > 0 {
                    ResultRow(label: "Words graduated to EN→IT", value: "\(stats.graduated)")
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                if !stats.wrongWords.isEmpty {
                    Button {
                        showingMistakes = true
                    } label: {
                        Label("Review Mistakes (\(stats.wrongWords.count))", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.regularMaterial)
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                }

                Button("Done", action: onDismiss)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 48)
        }
        .sheet(isPresented: $showingMistakes) {
            MistakesReviewView(words: stats.wrongWords)
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
