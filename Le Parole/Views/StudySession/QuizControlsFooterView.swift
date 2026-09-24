import SwiftUI

struct QuizControlsFooterView: View {
    let isRevealed: Bool
    let showControls: Bool
    let cardType: StudyCard.CardType
    @Binding var input: String
    @FocusState.Binding var isFocused: Bool
    let isTestMode: Bool
    let canRequestHint: Bool
    let isGrading: Bool
    let isGeneratingConjugation: Bool
    let onRequestHint: () -> Void
    let onSubmit: () -> Void
    let onNext: () -> Void

    var body: some View {
        if showControls {
            VStack(spacing: 12) {
                if isRevealed {
                    Button("Next →") {
                        onNext()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .transition(.opacity)
                } else {
                    VStack(spacing: 12) {
                        TextField(
                            cardType == .recognition ? "Type in English…" : "Type in Italian…",
                            text: $input
                        )
                        .multilineTextAlignment(.center)
                        .font(.theme(.body))
                        .padding(.vertical, 11)
                        .padding(.horizontal, 16)
                        .background(Theme.inputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .focused($isFocused)
                        .onSubmit {
                            onSubmit()
                        }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        HStack(spacing: 12) {
                            if !isTestMode {
                                Button("Hint") { onRequestHint() }
                                    .buttonStyle(SecondaryButtonStyle(verticalPadding: 14))
                                    .disabled(!canRequestHint)
                            }

                            Button { onSubmit() } label: {
                                if isGrading {
                                    HStack(spacing: 6) {
                                        ProgressView().tint(.white).scaleEffect(0.85)
                                        Text("Checking…")
                                    }
                                } else {
                                    Text("Check")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(verticalPadding: 14))
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isGeneratingConjugation)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(
                Theme.canvas
                    .opacity(0.96)
                    .ignoresSafeArea(.container, edges: .bottom)
            )
        }
    }
}
