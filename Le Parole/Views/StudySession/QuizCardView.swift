import SwiftUI
import GRDB
import Translation

struct QuizCardView: View {
    let card: StudyCard
    let vm: StudySessionViewModel

    private static let maxWrongAttempts = 3

    private struct SessionNotice {
        enum Tone {
            case success
            case encouragement
            case refresh
        }

        let icon: String
        let title: String
        let detail: String?
        let tone: Tone

        static func make(for outcome: ReviewOutcome) -> SessionNotice? {
            switch outcome {
            case .stageChanged(let oldStage, let newStage):
                stageChanged(from: oldStage, to: newStage)
            case .lapseRecovered(let feedback):
                SessionNotice(
                    icon: "checkmark.circle.fill",
                    title: "Back on track",
                    detail: feedback.detail,
                    tone: .success
                )
            case .reviewScheduled(let feedback):
                reviewScheduled(feedback)
            case .none:
                nil
            }
        }

        static func stageChanged(from oldStage: WordStage, to newStage: WordStage) -> SessionNotice? {
            switch (oldStage, newStage) {
            case (_, .mastered):
                return SessionNotice(
                    icon: "sparkles",
                    title: "Mastered!",
                    detail: nil,
                    tone: .success
                )
            case (.mastered, .production):
                return SessionNotice(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Quick refresh",
                    detail: "Review tomorrow",
                    tone: .refresh
                )
            case (_, .production):
                return SessionNotice(
                    icon: "arrow.up.right.circle.fill",
                    title: "Moving up!",
                    detail: nil,
                    tone: .success
                )
            case (_, .recognition):
                return SessionNotice(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Practice tomorrow",
                    detail: nil,
                    tone: .encouragement
                )
            case (_, .new), (_, .skipped):
                return nil
            }
        }

        static func reviewScheduled(_ feedback: ReviewScheduleFeedback) -> SessionNotice {
            SessionNotice(
                icon: "checkmark.seal.fill",
                title: feedback.title,
                detail: feedback.detail,
                tone: .success
            )
        }

        var tint: Color {
            switch tone {
            case .success: Theme.mastered
            case .encouragement: Theme.primary
            case .refresh: Theme.playfulAccent
            }
        }

        var haptic: UINotificationFeedbackGenerator.FeedbackType? {
            switch tone {
            case .success: .success
            case .encouragement, .refresh: nil
            }
        }

        var accessibilityLabel: String {
            [title, detail].compactMap { $0 }.joined(separator: ". ")
        }
    }

    @State private var input = ""
    @State private var isFlipped = false
    // Keep the rendered angle independent from the logical state. A spring on a
    // boolean-driven rotation can overshoot 180° and briefly reveal the wrong face.
    @State private var flipAngle: Double = 0
    @State private var isRevealed = false
    @State private var wasCorrect: Bool? = nil
    @FocusState private var inputFocused: Bool
    @State private var wrongCount = 0
    @State private var shakeTrigger: CGFloat = 0
    @State private var frontHighlight: Color = Theme.surface
    @State private var swipeOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1.0
    @State private var cardScale: CGFloat = 1.0
    @State private var interactionLocked = false
    @State private var animationTask: Task<Void, Never>?
    @State private var hintText: String? = nil
    @State private var isLoadingHint = false
    @State private var hintTask: Task<Void, Never>?
    @State private var isGrading = false
    @State private var gradingTask: Task<Void, Never>?
    @State private var exampleSentences: [String] = []
    @State private var isGeneratingExamples = false
    @State private var examplesTask: Task<Void, Never>?
    @State private var inflectionsText: String? = nil
    @State private var isGeneratingInflections = false
    @State private var inflectionsTask: Task<Void, Never>?
    @State private var sessionNotice: SessionNotice?
    @State private var activeSheet: ActiveSheet?
    @State private var visualQuizData: (target: WordDiagram, options: [WordDiagram])? = nil
    @State private var selectedVisualOptionId: String? = nil

    private enum ActiveSheet: Identifiable {
        case diagram(WordDiagram)
        case diagramCrop(diagram: WordDiagram, imageName: String)
        case relatedConcept(RelatedConceptItem)
        case relatedTerm(String)

        var id: String {
            switch self {
            case .diagram(let d): return "diagram_\(d.id)"
            case .diagramCrop(let d, let img): return "crop_\(d.id)_\(img)"
            case .relatedConcept(let item): return "concept_\(item.id)"
            case .relatedTerm(let t): return "term_\(t)"
            }
        }
    }

    private var sailingDiagram: WordDiagram? {
        SailingDiagramService.diagram(for: card.userWord.word.italian)
    }

    private var wordConcept: WordConcept? {
        ConceptService.shared.concept(for: card.userWord.word.italian)
    }

    private var diagramLearningCue: String? {
        SailingDiagramService.learningCue(for: card.userWord.word.italian)
    }
    // Conjugation states (computed from vm cache)
    private var isGeneratingConjugation: Bool {
        if card.cardType != .conjugation { return false }
        return vm.conjugationCache[card.id] == nil || {
            if case .loading = vm.conjugationCache[card.id] { return true }
            return false
        }()
    }
    
    private var conjugationSentence: String? {
        if case .success(let sentence, _, _, _, _, _) = vm.conjugationCache[card.id] { return sentence }
        return nil
    }

    private var conjugationAnswer: String? {
        if case .success(_, let answer, _, _, _, _) = vm.conjugationCache[card.id] { return answer }
        return nil
    }

    private var conjugationExplanation: String? {
        if case .success(_, _, let explanation, _, _, _) = vm.conjugationCache[card.id] {
            return conciseExplanation(explanation)
        }
        return nil
    }

    private func conciseExplanation(_ explanation: String) -> String {
        var concise = explanation
            .replacingOccurrences(of: "Formation:", with: "Rule:", options: .caseInsensitive)
            .replacingOccurrences(
                of: #"(?i)\s+Full\s+(?:presente|passato prossimo|imperfetto|futuro semplice|imperativo|condizionale presente|condizionale passato|congiuntivo presente|congiuntivo imperfetto|presente progressivo):\s*"#,
                with: "\nForms: ",
                options: .regularExpression
            )

        let tenseNames = [
            "presente", "passato prossimo", "imperfetto", "futuro semplice",
            "imperativo", "condizionale presente", "condizionale passato",
            "congiuntivo presente", "congiuntivo imperfetto", "presente progressivo",
        ]
        for tense in tenseNames {
            concise = concise.replacingOccurrences(of: " in \(tense)", with: "", options: .caseInsensitive)
        }
        return concise
    }

    private var conjugationTense: String? {
        if case .success(_, _, _, let tense, _, _) = vm.conjugationCache[card.id] { return tense }
        return nil
    }

    private var conjugationPronoun: String? {
        if case .success(_, _, _, _, let pronoun, _) = vm.conjugationCache[card.id] { return pronoun }
        return nil
    }

    private var geminiEnglishTranslation: String? {
        if case .success(_, _, _, _, _, let translation) = vm.conjugationCache[card.id] { return translation }
        return nil
    }



    var body: some View {
        ZStack {
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if visualQuizData != nil && !isRevealed {
                            Spacer(minLength: 4).frame(maxHeight: 8)
                        } else if sailingDiagram != nil && !isRevealed {
                            Spacer(minLength: 6).frame(maxHeight: 14)
                        } else {
                            Spacer(minLength: 16)
                        }

                        flipCard
                            .padding(.horizontal, 20)
                            .scaleEffect(cardScale)
                            .offset(x: swipeOffset)
                            .modifier(ShakeEffect(animatableData: shakeTrigger))
                            .opacity(cardOpacity)

                        if visualQuizData != nil && !isRevealed {
                            Color.clear.frame(height: 10)
                        } else if sailingDiagram != nil && !isRevealed {
                            Color.clear.frame(height: 12)
                        } else {
                            Spacer(minLength: 16)
                        }

                        if isRevealed && (!exampleSentences.isEmpty || isGeneratingExamples) && (wasCorrect == false) {
                            VStack(alignment: .leading, spacing: 8) {
                                if isGeneratingExamples {
                                    HStack {
                                        ProgressView()
                                        Text("Generating examples...")
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Examples:")
                                        .font(.theme(.headline, weight: .semibold))
                                    ForEach(exampleSentences, id: \.self) { ex in
                                        Text(ex)
                                            .font(.theme(.subheadline))
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .themeCard(cornerRadius: Theme.controlCornerRadius)
                            .padding(.horizontal, 20)
                            .padding(.bottom, inputFocused ? 8 : 20)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)), removal: .opacity))
                        }

                        if (isRevealed || isFlipped), let concept = wordConcept {
                            ConceptSectionView(
                                concept: concept,
                                onSelectRelatedItem: { item in
                                    activeSheet = .relatedConcept(item)
                                },
                                onSelectRelatedTerm: { term in
                                    activeSheet = .relatedTerm(term)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, inputFocused ? 8 : 20)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }

                        Group {
                            if isRevealed {
                                incorrectRevealedControls
                            } else if visualQuizData != nil {
                                visualChoiceGrid
                            } else {
                                inputControls
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isRevealed)

                        if visualQuizData != nil && !isRevealed {
                            Spacer(minLength: 8).frame(maxHeight: 20)
                        } else if sailingDiagram != nil && !isRevealed {
                            Spacer(minLength: 12).frame(maxHeight: 24)
                        } else {
                            Spacer().frame(height: inputFocused ? 16 : 32)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: inputFocused)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }

            if let sessionNotice {
                HStack(spacing: 12) {
                    Image(systemName: sessionNotice.icon)
                        .font(.theme(.title3, weight: .bold))
                        .foregroundStyle(sessionNotice.tint)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionNotice.title)
                            .font(.theme(.headline, weight: .bold))
                            .foregroundStyle(sessionNotice.tint)

                        if let detail = sessionNotice.detail {
                            Text(detail)
                                .font(.theme(.subheadline, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                .clipShape(Capsule())
                .shadow(color: Theme.cardShadow, radius: 15, y: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 24) // Hover above the flashcard, below the top edge
                .padding(.horizontal, 20)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(sessionNotice.accessibilityLabel)
                .zIndex(100)
            }
        }
        .onAppear {
            if card.cardType == .recognition && visualQuizData == nil {
                visualQuizData = SailingDiagramService.visualQuizOptions(for: card.userWord.word.italian)
            }
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                playFrontAudioIfNeeded()
                preloadInflectionsIfNeeded()
            }
        }
        .task(id: card.id) {
            await Task.yield()
            guard !isRevealed, !Task.isCancelled else { return }
            if card.cardType == .recognition {
                visualQuizData = SailingDiagramService.visualQuizOptions(for: card.userWord.word.italian)
            }
            let showsFrontDiagram = (card.cardType == .production && sailingDiagram?.promptImageName != nil)
            if !showsFrontDiagram && visualQuizData == nil {
                inputFocused = true
            } else {
                inputFocused = false
            }
        }
        .onChange(of: isRevealed) { _, revealed in
            if revealed {
                inputFocused = false
            }
        }
        .onChange(of: isFlipped) { _, flipped in
            if flipped {
                inputFocused = false
            }
        }
        .onChange(of: conjugationSentence) { _, newSentence in
            if let sentence = newSentence, card.cardType == .conjugation, !isFlipped, vm.autoPlayPronunciation {
                SpeechService.shared.speak(sentence, languageCode: "it-IT")
            }
        }
        .onDisappear {
            animationTask?.cancel(); hintTask?.cancel(); gradingTask?.cancel(); examplesTask?.cancel(); inflectionsTask?.cancel()
        }
        .onChange(of: card.id) { _, _ in resetState() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .diagram(let diag):
                DiagramPlateSheet(diagram: diag)
            case .diagramCrop(let diag, let imageName):
                DiagramPlateSheet(diagram: diag, displayImageName: imageName)
            case .relatedConcept(let item):
                RelatedWordSheet(item: item)
            case .relatedTerm(let term):
                RelatedWordSheet(term: term)
            }
        }
    }

    private func playFrontAudioIfNeeded() {
        if vm.autoPlayPronunciation && card.cardType == .recognition {
            SpeechService.shared.speak(card.prompt, languageCode: "it-IT")
        }
    }

    // MARK: - Audio

    private var frontLanguageCode: String {
        card.cardType == .production ? "en-US" : "it-IT"
    }

    private var backLanguageCode: String {
        card.cardType == .production ? "it-IT" : "en-US"
    }

    // MARK: - Card faces

    private var backFaceBackground: Color {
        switch wasCorrect {
        case true:  return Color.green.opacity(0.15)
        case false: return Color.red.opacity(0.08)
        case nil:   return Theme.surface
        }
    }

    private var backFaceBorderColor: Color {
        switch wasCorrect {
        case true:  return Color.green.opacity(0.5)
        case false: return Color.red.opacity(0.4)
        case nil:   return Color(.systemGray4)
        }
    }

    private var completedConjugationSentence: String {
        guard let sentence = conjugationSentence, let answer = conjugationAnswer else { return "" }
        if let regex = try? Regex("_{3,}\\s*\\([^)]+\\)", as: Substring.self), sentence.contains(regex) {
            return sentence.replacing(regex, with: answer)
        }
        if let regex = try? Regex("_{3,}", as: Substring.self) {
            return sentence.replacing(regex, with: answer)
        }
        return sentence
    }

    private var flipCard: some View {
        ZStack {
            cardFace(
                word: card.cardType == .conjugation ? (conjugationSentence ?? "") : card.prompt,
                language: card.cardType == .production ? "English" : "Italian",
                explanation: nil,
                alternatives: (card.cardType == .production) ? card.userWord.word.cleanAlternatives : nil,
                background: frontHighlight,
                borderColor: Theme.border,
                showHintArea: (card.cardType == .production || visualQuizData == nil),
                isLoading: isGeneratingConjugation,
                diagramImageName: card.cardType == .production ? sailingDiagram?.promptImageName : nil,
                diagramLearningCue: card.cardType == .production ? diagramLearningCue : nil,
                diagramAction: {
                    inputFocused = false
                    if let d = sailingDiagram { activeSheet = .diagram(d) }
                }
            ) { SpeechService.shared.speak(card.cardType == .conjugation ? (conjugationSentence ?? "") : card.prompt, languageCode: frontLanguageCode) }
            // Both faces rotate around the vertical axis. The front is hidden
            // after the edge-on midpoint so it can never be read upside down.
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.25
            )
            .opacity(flipAngle < 90 ? 1 : 0)
            .allowsHitTesting(!isFlipped)

            cardFace(
                word: card.cardType == .conjugation ? completedConjugationSentence : card.correctAnswer,
                language: card.cardType == .production ? "Italian" : (card.cardType == .conjugation ? "Italian" : "English"),
                explanation: (card.cardType == .conjugation) ? (wasCorrect == true ? geminiEnglishTranslation : conjugationExplanation) : nil,
                alternatives: (card.cardType == .recognition) ? card.userWord.word.cleanAlternatives : nil,
                inflections: (card.cardType == .production) ? inflectionsText : nil,
                isGeneratingInflections: (card.cardType == .production) ? isGeneratingInflections : false,
                background: backFaceBackground,
                borderColor: backFaceBorderColor,
                showHintArea: false,
                isLoading: false,
                diagramImageName: sailingDiagram?.revealedImageName,
                diagramLearningCue: diagramLearningCue,
                diagramAction: {
                    inputFocused = false
                    if let d = sailingDiagram { activeSheet = .diagram(d) }
                }
            ) { SpeechService.shared.speak(card.cardType == .conjugation ? completedConjugationSentence : card.correctAnswer, languageCode: backLanguageCode) }
            .rotation3DEffect(
                .degrees(flipAngle - 180),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.25
            )
            .opacity(flipAngle >= 90 ? 1 : 0)
            .allowsHitTesting(isFlipped)
        }
        .onTapGesture {
            guard !interactionLocked, !isGeneratingConjugation else { return }
            inputFocused = false
            if isRevealed {
                toggleFlip()
            } else {
                performReveal(correct: false)
            }
        }
    }

    private func cardFace(
        word: String,
        language: String,
        explanation: String?,
        alternatives: [String]? = nil,
        inflections: String? = nil,
        isGeneratingInflections: Bool = false,
        background: Color,
        borderColor: Color,
        showHintArea: Bool,
        isLoading: Bool,
        diagramImageName: String? = nil,
        diagramLearningCue: String? = nil,
        diagramAction: (() -> Void)? = nil,
        speakAction: @escaping () -> Void
    ) -> some View {
        let isCardFlippedOrRevealed = isFlipped || isRevealed
        let imageMaxHeight: CGFloat = isCardFlippedOrRevealed ? 330 : 210
        let cardMinHeight: CGFloat = (diagramImageName != nil)
            ? (isCardFlippedOrRevealed ? 540 : 400)
            : (visualQuizData != nil ? (isCardFlippedOrRevealed ? 225 : 120) : (isCardFlippedOrRevealed ? 190 : 170))
        let cardPadding: CGFloat = (diagramImageName != nil)
            ? (isCardFlippedOrRevealed ? 16 : 18)
            : (visualQuizData != nil ? (isCardFlippedOrRevealed ? 20 : 14) : 22)

        // The back face has a static 180° inner rotation that is cancelled by the outer
        // flip animation's 180°, so layout coordinates map directly to visual coordinates
        // on both faces — .topLeading always appears at top-left.
        return ZStack(alignment: .topLeading) {
            VStack(spacing: diagramImageName != nil ? 10 : (visualQuizData != nil && !isCardFlippedOrRevealed ? 6 : 12)) {
                Text(language.uppercased())
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .tracking(1)

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else {
                    if let diagramImageName {
                        Button {
                            diagramAction?()
                        } label: {
                            VStack(spacing: 6) {
                                Image(diagramImageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: imageMaxHeight)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, y: 3)

                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(sailingDiagram?.hasMatchingFullPlate == true ? "Open the related full plate" : "Enlarge this reference diagram")
                                        .font(.theme(.caption, weight: .medium))
                                }
                                .foregroundStyle(Theme.primary)
                                .padding(.top, 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open full diagram plate")

                        if let diagramLearningCue {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Why this helps", systemImage: "lightbulb.fill")
                                    .font(.theme(.caption, weight: .bold))
                                    .foregroundStyle(Theme.primary)
                                Text(diagramLearningCue)
                                    .font(.theme(.caption))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }

                    Text(word)
                        .font(card.cardType == .conjugation ? Theme.wordPrompt : (diagramImageName != nil ? .theme(.title2, weight: .bold) : Theme.wordDisplay))
                        .foregroundStyle(diagramImageName != nil ? Theme.primary : .primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    if visualQuizData != nil && !isFlipped && !isRevealed {
                        HStack(spacing: 5) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Tap the matching diagram")
                                .font(.theme(.caption, weight: .semibold))
                        }
                        .foregroundStyle(Theme.primary)
                        .padding(.top, 2)
                    }

                    if let answer = conjugationAnswer, isRevealed {
                        Text(answer)
                            .font(.theme(.title3, weight: .bold))
                            .foregroundStyle(wasCorrect == true ? Theme.primary : Theme.playfulAccent)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    if let translation = geminiEnglishTranslation, isRevealed {
                        Text(translation)
                            .font(.theme(.body))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .padding(.horizontal, 16)
                    }

                    if let explanation = conjugationExplanation, isRevealed {
                        Text(explanation)
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .padding(.horizontal, 16)
                    }

                    if showHintArea {
                        VStack(spacing: 4) {
                            hintArea(alternatives: alternatives)

                            if wrongCount > 0 && !vm.isTestMode {
                                let remaining = Self.maxWrongAttempts - wrongCount
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(remaining == 1 ? "1 attempt left" : "\(remaining) attempts left")
                                        .font(.theme(.caption, weight: .semibold))
                                }
                                .foregroundStyle(Theme.playfulAccent)
                                .transition(.opacity)
                            }
                        }
                        .padding(.top, 4)
                    }

                    if isGeneratingInflections {
                        ProgressView()
                            .scaleEffect(0.75)
                            .padding(.top, 4)
                    } else if let infl = inflections {
                        Text(infl)
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .padding(.horizontal, 16)
                    }
                }
            }
            .padding(cardPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: cardMinHeight)


            Button(action: speakAction) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.primary, in: Circle())
            }
            .disabled(isLoading)
            .padding(20)
        }
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous).stroke(borderColor, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 16, y: 8)
    }

    @ViewBuilder
    private func hintArea(alternatives: [String]?) -> some View {
        Group {
            if isLoadingHint {
                ProgressView()
                    .scaleEffect(0.75)
            } else if let hint = hintText {
                Text(hint)
                    .font(.theme(.callout))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let alts = alternatives, !alts.isEmpty {
                Text("Also: " + alts.joined(separator: ", "))
                    .font(.theme(.subheadline))
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }


    // MARK: - Controls

    private var inputControls: some View {
        VStack(spacing: 12) {
            TextField(
                card.cardType == .recognition ? "Type in English…" : "Type in Italian…",
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
            .focused($inputFocused)
            .onSubmit {
                submitAnswer()
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                if !vm.isTestMode {
                    Button("Hint") { requestHint() }
                        .buttonStyle(SecondaryButtonStyle(verticalPadding: 14))
                        .disabled(!canRequestHint)
                }

                Button { submitAnswer() } label: {
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
            .padding(.horizontal, 20)
        }
        .layoutPriority(1)
    }

    private var incorrectRevealedControls: some View {
        Button("Next →") { vm.advance() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
    }

    // MARK: - Visual Multiple Choice Grid

    private var visualChoiceGrid: some View {
        guard let quiz = visualQuizData else { return AnyView(EmptyView()) }

        return AnyView(
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(quiz.options) { option in
                    VisualOptionTile(
                        option: option,
                        isSelected: selectedVisualOptionId == option.id,
                        isTarget: option.id == quiz.target.id,
                        showFeedback: isRevealed || selectedVisualOptionId != nil,
                        isDisabled: interactionLocked || isRevealed,
                        onZoom: {
                            activeSheet = .diagramCrop(diagram: option, imageName: option.promptImageName)
                        }
                    ) {
                        selectVisualOption(option, target: quiz.target)
                    }
                }
            }
            .padding(.horizontal, 20)
            .layoutPriority(1)
        )
    }

    private func selectVisualOption(_ option: WordDiagram, target: WordDiagram) {
        guard !interactionLocked, !isRevealed else { return }
        selectedVisualOptionId = option.id
        interactionLocked = true

        if option.id == target.id {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                performReveal(correct: true)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            wrongCount += 1
            animationTask = Task { @MainActor in
                await performShakeAndRed()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                performReveal(correct: false)
            }
        }
    }

    // MARK: - Actions

    private func resetState() {
        animationTask?.cancel()
        animationTask = nil
        hintTask?.cancel()
        hintTask = nil
        gradingTask?.cancel()
        gradingTask = nil
        examplesTask?.cancel()
        examplesTask = nil
        input = ""
        selectedVisualOptionId = nil
        if card.cardType == .recognition {
            visualQuizData = SailingDiagramService.visualQuizOptions(for: card.userWord.word.italian)
        } else {
            visualQuizData = nil
        }
        isFlipped = false
        flipAngle = 0
        isRevealed = false
        wasCorrect = nil
        wrongCount = 0
        shakeTrigger = 0
        frontHighlight = Theme.surface
        interactionLocked = false
        isGrading = false
        hintText = nil
        sessionNotice = nil
        isLoadingHint = false
        swipeOffset = 0
        cardOpacity = 0
        cardScale = 0.92
        exampleSentences = []
        isGeneratingExamples = false
        inflectionsText = nil
        isGeneratingInflections = false
        inflectionsTask?.cancel()
        inflectionsTask = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            cardOpacity = 1.0
            cardScale = 1.0
        }
        playFrontAudioIfNeeded()
        preloadInflectionsIfNeeded()
    }

    private func preloadInflectionsIfNeeded() {
        if card.cardType == .production {
            if let inflections = card.userWord.word.inflections {
                inflectionsText = inflections
            } else {
                inflectionsText = nil
            }
        }
    }

    private func generateExamplesIfNeeded() {
        guard card.cardType != .conjugation,
              examplesTask == nil,
              exampleSentences.isEmpty else { return }

        let requestedCardID = card.id
        let targetItalian = card.userWord.word.italian
        let targetEnglish = card.userWord.word.english
        let targetTopic = card.userWord.word.level
        isGeneratingExamples = true
        examplesTask = Task { @MainActor in
            let sentences = await AppleIntelligenceService.generateExamples(
                for: targetItalian,
                englishMeaning: targetEnglish,
                topic: targetTopic
            )
            guard !Task.isCancelled, card.id == requestedCardID else { return }
            withAnimation {
                exampleSentences = sentences
                isGeneratingExamples = false
                examplesTask = nil
            }
        }
    }

    private var canRequestHint: Bool {
        if isRevealed || isLoadingHint { return false }
        if hintText == nil { return true }
        if hintText?.hasPrefix("Correct, but") == true { return true }
        if hintText?.hasPrefix("Close! Check") == true { return true }
        if hintText?.hasPrefix("Correct word, but check") == true { return true }
        return false
    }

    private func requestHint() {
        guard !interactionLocked, canRequestHint else { return }

        if card.cardType == .conjugation {
            let tenseInfo = conjugationTense ?? "unknown tense"
            let pronounInfo = conjugationPronoun ?? "unknown"
            withAnimation { hintText = "Tense: \(tenseInfo) • Pronoun: \(pronounInfo)" }
        } else if card.cardType == .production {
            // en → it: display other ways to translate the Italian word
            let allEnglish = [card.userWord.word.english] + card.userWord.word.cleanAlternatives
            let otherTranslations = allEnglish.filter { $0.lowercased() != card.prompt.lowercased() }
            
            if !otherTranslations.isEmpty {
                withAnimation { hintText = "Also means: \(otherTranslations.joined(separator: ", "))" }
            } else {
                isLoadingHint = true
                hintTask = Task { @MainActor in
                    if let sentence = await AppleIntelligenceService.generateFillInTheBlankHint(for: card.correctAnswer) {
                        withAnimation {
                            isLoadingHint = false
                            hintText = sentence
                        }
                    } else {
                        let first = card.correctAnswer.first.map(String.init) ?? "?"
                        withAnimation {
                            isLoadingHint = false
                            hintText = "\(first)..."
                        }
                    }
                }
            }
        } else {
            // it → en: use Apple Intelligence for contextual hint
            isLoadingHint = true
            hintTask = Task { @MainActor in
                if let sentence = await AppleIntelligenceService.generateHintSentence(for: card.prompt) {
                    withAnimation {
                        isLoadingHint = false
                        hintText = sentence
                    }
                } else {
                    let first = card.correctAnswer.first.map(String.init) ?? "?"
                    withAnimation {
                        isLoadingHint = false
                        hintText = "\(first)..."
                    }
                }
            }
        }
    }

    private func submitAnswer() {
        guard !interactionLocked, !isGeneratingConjugation else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Determine if correct based on cardType
        let isCorrect: Bool
        if card.cardType == .conjugation {
            if let answerStr = conjugationAnswer {
                let options = answerStr.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                isCorrect = options.contains(trimmed.lowercased())
            } else {
                isCorrect = false
            }
        } else {
            isCorrect = card.isCorrect(trimmed)
        }

        if isCorrect {
            handleCorrect()
            return
        }

        // For production (EN→IT) cards, verify if the input is a valid Italian synonym in the DB.
        if card.cardType == .production {
            if card.userWord.word.isInflectionVariant(trimmed) && trimmed.lowercased() != card.correctAnswer.lowercased() {
                withAnimation {
                    hintText = "That's a valid form! But please use the root form (e.g. masculine singular for adjectives, or standard singular for nouns)."
                    input = ""
                }
                inputFocused = true
                return
            }

            interactionLocked = true
            gradingTask = Task { @MainActor in
                let dbSynonymMatch = await vm.isValidItalianSynonym(input: trimmed)
                guard !Task.isCancelled else { return }
                interactionLocked = false
                
                if dbSynonymMatch {
                    let firstLetter = card.correctAnswer.first.map(String.init) ?? "?"
                    withAnimation {
                        hintText = "Correct, but looking for another word (starts with \(firstLetter)...)"
                        input = ""
                    }
                    inputFocused = true
                } else {
                    handleWrong()
                }
            }
            return
        }
        handleWrong()
    }

    private func handleCorrect() {
        wasCorrect = true
        interactionLocked = true
        inputFocused = false
        examplesTask?.cancel()
        examplesTask = nil
        isGeneratingExamples = false
        
        animationTask = Task { @MainActor in
            animateFlip(to: 180)
            
            withAnimation(.easeOut(duration: 0.3)) {
                if card.cardType == .conjugation {
                    isRevealed = true
                }
            }
            
            if vm.autoPlayPronunciation {
                if card.cardType == .production {
                    SpeechService.shared.speak(card.correctAnswer, languageCode: "it-IT")
                } else if card.cardType == .conjugation {
                    SpeechService.shared.speak(completedConjugationSentence, languageCode: "it-IT")
                }
            }

            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            
            let context: MistakeContext?
            if card.cardType == .conjugation {
                context = MistakeContext(
                    question: conjugationSentence,
                    answer: conjugationAnswer,
                    explanation: conjugationExplanation
                )
            } else if let quiz = visualQuizData {
                context = MistakeContext(
                    question: quiz.target.title,
                    answer: quiz.target.title,
                    explanation: quiz.target.caption
                )
            } else {
                context = nil
            }
            let outcome = vm.recordResult(correct: true, context: context)
            let notice = SessionNotice.make(for: outcome)
            
            let hasInflections = (card.cardType == .production) && (inflectionsText != nil || isGeneratingInflections)
            let hasAlternatives = (card.cardType == .recognition) && !card.userWord.word.cleanAlternatives.isEmpty
            let hasExplanation = card.cardType == .conjugation && conjugationExplanation != nil
            let hasConcept = wordConcept != nil
            
            let remainingDelay: Double
            if hasExplanation {
                remainingDelay = 4.5
            } else if hasConcept {
                remainingDelay = 2.5
            } else if hasInflections {
                remainingDelay = 2.0
            } else if hasAlternatives {
                remainingDelay = 1.2
            } else {
                remainingDelay = card.cardType == .conjugation ? 2.1 : 0.8
            }
            
            async let noticeCompleted = presentSessionNotice(notice)
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled, await noticeCompleted else { return }
            
            withAnimation(.easeIn(duration: 0.3)) { swipeOffset = 500; cardOpacity = 0 }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            vm.advance()
        }
    }

    @MainActor
    private func presentSessionNotice(_ notice: SessionNotice?) async -> Bool {
        guard let notice else { return true }

        if let haptic = notice.haptic {
            UINotificationFeedbackGenerator().notificationOccurred(haptic)
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            sessionNotice = notice
        }

        do {
            try await Task.sleep(for: .seconds(1.5))
        } catch {
            return false
        }

        withAnimation(.easeOut(duration: 0.3)) {
            sessionNotice = nil
        }

        do {
            try await Task.sleep(for: .seconds(0.3))
            return true
        } catch {
            return false
        }
    }

    private func handleWrong() {
        withAnimation(.easeInOut(duration: 0.25)) {
            wrongCount += 1
        }
        if wrongCount == 1 {
            generateExamplesIfNeeded()
        }
        interactionLocked = true
        animationTask = Task { @MainActor in
            await performShakeAndRed()
            guard !Task.isCancelled else { return }
            interactionLocked = false
            if vm.isTestMode || wrongCount >= Self.maxWrongAttempts {
                performReveal(correct: false)
            } else {
                inputFocused = true
            }
        }
    }

    private func performReveal(correct: Bool) {
        guard !isRevealed else { return }
        wasCorrect = correct
        interactionLocked = true
        inputFocused = false

        animationTask = Task { @MainActor in
            animateFlip(to: 180)
            
            if vm.autoPlayPronunciation {
                if card.cardType == .production {
                    SpeechService.shared.speak(card.correctAnswer, languageCode: "it-IT")
                } else if card.cardType == .conjugation {
                    SpeechService.shared.speak(completedConjugationSentence, languageCode: "it-IT")
                }
            }

            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isRevealed = true
                inputFocused = false
            }
            
            try? await Task.sleep(for: .seconds(0.35))
            guard !Task.isCancelled else { return }
            
            let context: MistakeContext?
            if card.cardType == .conjugation {
                context = MistakeContext(
                    question: conjugationSentence,
                    answer: conjugationAnswer,
                    explanation: conjugationExplanation
                )
            } else if let quiz = visualQuizData {
                context = MistakeContext(
                    question: quiz.target.title,
                    answer: quiz.target.title,
                    explanation: quiz.target.caption
                )
            } else {
                context = nil
            }
            let outcome = vm.recordResult(correct: correct, context: context)
            _ = await presentSessionNotice(SessionNotice.make(for: outcome))
            
            interactionLocked = false
        }
    }

    private func toggleFlip() {
        inputFocused = false
        animateFlip(to: isFlipped ? 0 : 180)
    }

    private func animateFlip(to angle: Double) {
        withAnimation(.easeInOut(duration: 0.32)) {
            flipAngle = angle
            isFlipped = angle >= 90
        }
    }

    private func performShakeAndRed() async {
        withAnimation(.easeIn(duration: 0.12)) {
            frontHighlight = Color.red.opacity(0.2)
        }
        withAnimation(.easeInOut(duration: 0.42)) {
            shakeTrigger += 1.0
        }

        try? await Task.sleep(for: .seconds(0.35))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.22)) {
            frontHighlight = Theme.surface
        }
        try? await Task.sleep(for: .seconds(0.12))
    }
}
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 12
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let unitProgress = animatableData.truncatingRemainder(dividingBy: 1.0)
        let progress = unitProgress == 0 && animatableData > 0 ? 1.0 : unitProgress
        let damping = max(0, 1.0 - progress)
        let translation = travel * damping * sin(progress * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Visual Option Tile

struct VisualOptionTile: View {
    let option: WordDiagram
    let isSelected: Bool
    let isTarget: Bool
    let showFeedback: Bool
    let isDisabled: Bool
    let onZoom: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Image(option.promptImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 175)
                        .padding(6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 185)
                .background(Color.white)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)

                // Magnifying zoom button in top-left
                VStack {
                    HStack {
                        Button {
                            onZoom()
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .padding(7)
                                .background(Color.white.opacity(0.92), in: Circle())
                                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        Spacer()
                    }
                    Spacer()
                }

                if showFeedback {
                    if isTarget {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.green)
                            .background(Circle().fill(Color.white))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.red)
                            .background(Circle().fill(Color.white))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .scaleEffect(isSelected ? 0.98 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showFeedback)
    }

    private var borderColor: Color {
        if showFeedback {
            if isTarget {
                return Color.green
            } else if isSelected {
                return Color.red
            }
        }
        return Theme.border
    }

    private var borderWidth: CGFloat {
        if showFeedback && (isTarget || isSelected) {
            return 2.5
        }
        return 1.0
    }
}
