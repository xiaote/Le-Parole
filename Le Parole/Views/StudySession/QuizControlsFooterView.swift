import SwiftUI

struct QuizControlsFooterView: View {
    let isRevealed: Bool
    /// False for a visual quiz, which is answered by picking a diagram.
    let hasTextInput: Bool
    let cardType: StudyCard.CardType
    @Binding var input: String
    @FocusState.Binding var isFocused: Bool
    let isTestMode: Bool
    let canRequestHint: Bool
    let isGrading: Bool
    let onRequestHint: () -> Void
    let onSubmit: () -> Void
    let onNext: () -> Void

    var body: some View {
        if hasTextInput || isRevealed {
            // Next takes the Check button's place. The input controls stay in
            // the layout (hidden) once revealed, so the footer keeps its
            // height and the card above doesn't resize into its space while
            // it flips.
            ZStack(alignment: .bottom) {
                if hasTextInput {
                    inputControls
                        .opacity(isRevealed ? 0 : 1)
                        .disabled(isRevealed)
                        .accessibilityHidden(isRevealed)
                }
                if isRevealed {
                    Button("Next →", action: onNext)
                        .buttonStyle(PrimaryButtonStyle())
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

    private var inputControls: some View {
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
            .onSubmit(onSubmit)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            HStack(spacing: 12) {
                if !isTestMode {
                    Button("Hint", action: onRequestHint)
                        .buttonStyle(SecondaryButtonStyle(verticalPadding: 14))
                        .disabled(!canRequestHint)
                }

                Button(action: onSubmit) {
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
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
