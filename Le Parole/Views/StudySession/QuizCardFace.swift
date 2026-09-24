import SwiftUI

/// The hint line under a prompt.
enum QuizHint: Equatable {
    case none
    case loading
    /// `allowsAnother`: the learner may ask again (e.g. after a synonym).
    case shown(String, allowsAnother: Bool)
}

/// One side of the study card: the prompt, or the answer it flips to. The
/// answer side sizes the card only once revealed (see `FlipCardLayout`), so
/// it is always laid out expanded.
struct QuizCardFace: View {
    enum Side { case prompt, answer }

    let side: Side
    let presentation: CardPresentation
    let isRevealed: Bool
    /// nil until the card is revealed.
    let wasCorrect: Bool?
    /// Prompt background; turns red briefly on a wrong answer.
    let promptHighlight: Color
    let hint: QuizHint
    let attemptsLeft: Int?
    let onOpenDiagram: () -> Void

    private var card: StudyCard { presentation.card }
    private var isAnswer: Bool { side == .answer }
    private var isVisualQuiz: Bool { presentation.visualQuiz != nil }
    private var text: String { isAnswer ? presentation.answerText : presentation.promptText }
    private var language: CardPresentation.Language {
        isAnswer ? presentation.answerLanguage : presentation.promptLanguage
    }
    private var diagramImageName: String? {
        isAnswer
            ? presentation.diagram?.revealedImageName
            : (card.cardType == .production ? presentation.diagram?.promptImageName : nil)
    }
    private var showsHintArea: Bool {
        !isAnswer && (card.cardType == .production || !isVisualQuiz)
    }

    var body: some View {
        let hasDiagram = diagramImageName != nil
        let minHeight: CGFloat = hasDiagram
            ? (isAnswer ? 500 : 320)
            : (isVisualQuiz ? (isAnswer ? 225 : 120) : (isAnswer ? 190 : 170))
        let padding: CGFloat = hasDiagram
            ? (isAnswer ? 16 : 18)
            : (isVisualQuiz ? (isAnswer ? 20 : 14) : 22)

        // The answer side has a static 180° inner rotation that is cancelled by
        // the flip's 180°, so .topLeading always appears at the top left.
        ZStack(alignment: .topLeading) {
            VStack(spacing: hasDiagram ? 10 : (isVisualQuiz && !isAnswer ? 6 : 12)) {
                Text(language.label.uppercased())
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .tracking(1)

                if let diagramImageName {
                    diagramButton(imageName: diagramImageName)
                }

                Text(text)
                    .font(card.cardType == .conjugation ? Theme.wordPrompt : (hasDiagram ? .theme(.title2, weight: .bold) : Theme.wordDisplay))
                    .foregroundStyle(hasDiagram ? Theme.primary : .primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                if isVisualQuiz && !isRevealed {
                    Label("Tap the matching diagram", systemImage: "hand.tap.fill")
                        .labelStyle(CaptionLabelStyle(weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 2)
                }

                if isRevealed, let conjugation = presentation.conjugation {
                    detailText(conjugation.englishTranslation, font: .theme(.body), topPadding: 4)
                    detailText(conjugation.explanation, font: .theme(.subheadline), topPadding: 6)
                }

                if showsHintArea {
                    VStack(spacing: 4) {
                        hintLine
                        if let attemptsLeft {
                            Label(attemptsLeft == 1 ? "1 attempt left" : "\(attemptsLeft) attempts left", systemImage: "exclamationmark.circle.fill")
                                .labelStyle(CaptionLabelStyle(weight: .semibold))
                                .foregroundStyle(Theme.playfulAccent)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 4)
                }

                if isAnswer, isRevealed, let inflections = presentation.inflections {
                    detailText(inflections, font: .theme(.subheadline), topPadding: 4)
                }
            }
            .padding(padding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)

            Button {
                SpeechService.shared.speak(text, languageCode: language.speechCode)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.primary, in: Circle())
            }
            .padding(20)
        }
        // The answer colours switch instantly: that side is hidden when they
        // change, and a blend would show mid-flip.
        .background { background.animation(nil, value: wasCorrect) }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1.5)
                .animation(nil, value: wasCorrect)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous))
        // Cast the shadow from the card's shape, not its content: a content
        // shadow is re-rendered offscreen on every frame of the 3D flip, and
        // the translucent answer backgrounds let it show through as halos
        // around the text. The canvas fill keeps those backgrounds looking as
        // they do over the page.
        .background(
            RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous)
                .fill(Theme.canvas)
                .shadow(color: Theme.cardShadow, radius: 16, y: 8)
        )
        .compositingGroup()
    }

    private var background: Color {
        switch (isAnswer, wasCorrect) {
        case (false, _): return promptHighlight
        case (true, true): return Color.green.opacity(0.15)
        case (true, false): return Color.red.opacity(0.08)
        case (true, nil): return Theme.surface
        }
    }

    private var borderColor: Color {
        switch (isAnswer, wasCorrect) {
        case (false, _): return Theme.border
        case (true, true): return Color.green.opacity(0.5)
        case (true, false): return Color.red.opacity(0.4)
        case (true, nil): return Color(.systemGray4)
        }
    }

    private func diagramButton(imageName: String) -> some View {
        Button(action: onOpenDiagram) {
            VStack(spacing: 6) {
                // Framed to the image's own aspect ratio, so there are no empty
                // bands around a wide or tall diagram and the frame and the
                // image resize together when the card expands.
                AspectFitFrame(
                    aspectRatio: isAnswer ? presentation.answerImageAspectRatio : presentation.promptImageAspectRatio,
                    maxHeight: isAnswer ? 330 : 210
                ) {
                    Image(imageName)
                        .resizable()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.1), radius: 8, y: 3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                }

                Label(
                    presentation.diagram?.hasMatchingFullPlate == true ? "Open the related full plate" : "Enlarge this reference diagram",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
                .labelStyle(CaptionLabelStyle(weight: .medium))
                .foregroundStyle(Theme.primary)
                .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open full diagram plate")
    }

    @ViewBuilder
    private var hintLine: some View {
        Group {
            switch hint {
            case .loading:
                ProgressView()
                    .scaleEffect(0.75)
            case .shown(let text, _):
                Text(text)
                    .font(.theme(.callout))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            case .none:
                if card.cardType == .production, !presentation.alternatives.isEmpty {
                    Text("Also: " + presentation.alternatives.joined(separator: ", "))
                        .font(.theme(.subheadline))
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func detailText(_ text: String, font: Font, topPadding: CGFloat) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, topPadding)
            .padding(.horizontal, 16)
            .transition(.opacity)
    }
}

/// As wide as offered and exactly the given aspect ratio, but no taller than
/// `maxHeight`.
private struct AspectFitFrame: Layout {
    let aspectRatio: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? maxHeight * aspectRatio
        let height = min(width / aspectRatio, maxHeight)
        return CGSize(width: height * aspectRatio, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// Small icon + caption used for the card's inline cues.
private struct CaptionLabelStyle: LabelStyle {
    let weight: Font.Weight

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 11, weight: .semibold))
            configuration.title
                .font(.theme(.caption, weight: weight))
        }
    }
}
