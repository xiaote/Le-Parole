import SwiftUI

struct QuizCardView: View {
    let presentation: CardPresentation
    let vm: StudySessionViewModel

    private static let maxWrongAttempts = 3

    /// Where the card is in its life. Each user action makes one transition;
    /// input is accepted only in `.answering` and `.revealed`.
    private enum Phase {
        /// Waiting for a typed answer or a picked diagram.
        case answering
        /// Checking whether a wrong answer is a synonym.
        case grading
        /// Showing a wrong answer or a picked diagram before moving on.
        case feedback
        /// Flipping to the answer.
        case revealing
        /// The answer is shown; Next and flipping are enabled.
        case revealed
        /// Sliding off before the next card.
        case leaving
    }

    private enum Examples: Equatable {
        case none
        case loading
        case loaded([String])

        var hasContent: Bool {
            switch self {
            case .none: false
            case .loading: true
            case .loaded(let sentences): !sentences.isEmpty
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case diagram(WordDiagram)
        case diagramCrop(diagram: WordDiagram, imageName: String)
        case relatedConcept(RelatedConceptItem)
        case relatedTerm(String)

        var id: String {
            switch self {
            case .diagram(let d): "diagram_\(d.id)"
            case .diagramCrop(let d, let img): "crop_\(d.id)_\(img)"
            case .relatedConcept(let item): "concept_\(item.id)"
            case .relatedTerm(let t): "term_\(t)"
            }
        }
    }

    @State private var phase = Phase.answering
    /// nil until the answer is revealed.
    @State private var wasCorrect: Bool?
    /// Drives the flip. Only ever changed with an ease curve: a spring would
    /// overshoot 180° and briefly show the wrong side.
    @State private var showsAnswerSide = false
    @State private var hasAppeared = false
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @State private var wrongCount = 0
    @State private var shakeTrigger: CGFloat = 0
    @State private var promptHighlight = Theme.surface
    @State private var hint = QuizHint.none
    @State private var examples = Examples.none
    @State private var selectedVisualOptionId: String?
    @State private var sessionNotice: SessionNotice?
    @State private var activeSheet: ActiveSheet?
    /// The running grading / feedback / reveal / auto-advance sequence.
    @State private var sequenceTask: Task<Void, Never>?
    @State private var hintTask: Task<Void, Never>?
    @State private var examplesTask: Task<Void, Never>?

    private var card: StudyCard { presentation.card }
    private var isRevealed: Bool { wasCorrect != nil }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        flipCard
                            .padding(.horizontal, 20)
                            .compositingGroup()
                            .scaleEffect(hasAppeared ? 1 : 0.96)
                            .offset(x: phase == .leaving ? 500 : 0)
                            .modifier(ShakeEffect(animatableData: shakeTrigger))
                            .opacity(hasAppeared && phase != .leaving ? 1 : 0)
                            // Above the diagram grid, which fades out where it
                            // was while the revealed card grows over it.
                            .zIndex(1)

                        if let quiz = presentation.visualQuiz, !isRevealed {
                            VisualChoiceGridView(
                                quiz: quiz,
                                selectedOptionId: selectedVisualOptionId,
                                isDisabled: phase != .answering,
                                onSelect: selectVisualOption,
                                onZoom: { option in
                                    activeSheet = .diagramCrop(diagram: option, imageName: option.promptImageName)
                                }
                            )
                        }

                        if isRevealed, wasCorrect == false, examples.hasContent {
                            examplesCard
                        }

                        if isRevealed, let concept = presentation.concept {
                            ConceptSectionView(
                                concept: concept,
                                onSelectRelatedItem: { activeSheet = .relatedConcept($0) },
                                onSelectRelatedTerm: { activeSheet = .relatedTerm($0) }
                            )
                            .padding(.horizontal, 20)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)

                QuizControlsFooterView(
                    isRevealed: isRevealed,
                    hasTextInput: presentation.visualQuiz == nil,
                    cardType: card.cardType,
                    input: $input,
                    isFocused: $inputFocused,
                    isTestMode: vm.isTestMode,
                    canRequestHint: canRequestHint,
                    isGrading: phase == .grading,
                    onRequestHint: requestHint,
                    onSubmit: submitAnswer,
                    onNext: {
                        if phase == .revealed { leave(duration: 0.25) }
                    }
                )
            }

            if let sessionNotice {
                SessionNoticeView(notice: sessionNotice)
            }
        }
        .onAppear {
            // Raise the keyboard together with the entrance, while the card is
            // still transparent, so the layout shift it causes is part of one
            // motion instead of a second jump once the card is visible.
            let showsPromptDiagram = card.cardType == .production && presentation.diagram != nil
            inputFocused = !showsPromptDiagram && presentation.visualQuiz == nil
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                hasAppeared = true
            }
            if vm.autoPlayPronunciation && card.cardType == .recognition {
                SpeechService.shared.speak(presentation.promptText, languageCode: presentation.promptLanguage.speechCode)
            }
        }
        .onDisappear {
            sequenceTask?.cancel()
            hintTask?.cancel()
            examplesTask?.cancel()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .diagram(let diagram):
                DiagramPlateSheet(diagram: diagram)
            case .diagramCrop(let diagram, let imageName):
                DiagramPlateSheet(diagram: diagram, displayImageName: imageName)
            case .relatedConcept(let item):
                RelatedWordSheet(term: item.term, relatedItem: item)
            case .relatedTerm(let term):
                RelatedWordSheet(term: term)
            }
        }
    }

    // MARK: - Card

    private var flipCard: some View {
        let angle: Double = showsAnswerSide ? 180 : 0
        return FlipCardLayout(showsBack: isRevealed) {
            face(.prompt)
                .modifier(FlipEffect(angle: angle, isBack: false))
            face(.answer)
                .modifier(FlipEffect(angle: angle, isBack: true))
        }
        .onTapGesture {
            switch phase {
            case .answering:
                inputFocused = false
                reveal(correct: false)
            case .revealed:
                withAnimation(.easeInOut(duration: 0.32)) { showsAnswerSide.toggle() }
            case .grading, .feedback, .revealing, .leaving:
                break
            }
        }
    }

    private func face(_ side: QuizCardFace.Side) -> some View {
        QuizCardFace(
            side: side,
            presentation: presentation,
            isRevealed: isRevealed,
            wasCorrect: wasCorrect,
            promptHighlight: promptHighlight,
            hint: hint,
            attemptsLeft: wrongCount > 0 && !vm.isTestMode ? Self.maxWrongAttempts - wrongCount : nil,
            onOpenDiagram: {
                inputFocused = false
                if let diagram = presentation.diagram { activeSheet = .diagram(diagram) }
            }
        )
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch examples {
            case .loading:
                HStack {
                    ProgressView()
                    Text("Generating examples...")
                        .foregroundStyle(.secondary)
                }
            case .loaded(let sentences):
                Text("Examples:")
                    .font(.theme(.headline, weight: .semibold))
                ForEach(sentences, id: \.self) { sentence in
                    Text(sentence)
                        .font(.theme(.subheadline))
                }
            case .none:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.controlCornerRadius)
        .padding(.horizontal, 20)
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)), removal: .opacity))
    }

    // MARK: - Answering

    private func submitAnswer() {
        guard phase == .answering else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if presentation.accepts(trimmed) {
            examplesTask?.cancel()
            reveal(correct: true, autoAdvance: true)
            return
        }
        // Production (EN→IT) answers may be another valid Italian word.
        guard card.cardType == .production else {
            handleWrong()
            return
        }
        if card.userWord.word.isInflectionVariant(trimmed) && trimmed.lowercased() != card.correctAnswer.lowercased() {
            withAnimation {
                hint = .shown("That's a valid form! But please use the root form (e.g. masculine singular for adjectives, or standard singular for nouns).", allowsAnother: false)
                input = ""
            }
            inputFocused = true
            return
        }

        phase = .grading
        sequenceTask = Task {
            let isSynonym = await vm.isValidItalianSynonym(input: trimmed)
            guard !Task.isCancelled else { return }
            phase = .answering
            if isSynonym {
                let firstLetter = card.correctAnswer.first.map(String.init) ?? "?"
                withAnimation {
                    hint = .shown("Correct, but looking for another word (starts with \(firstLetter)...)", allowsAnother: true)
                    input = ""
                }
                inputFocused = true
            } else {
                handleWrong()
            }
        }
    }

    private func handleWrong() {
        withAnimation(.easeInOut(duration: 0.25)) {
            wrongCount += 1
        }
        if wrongCount == 1 {
            generateExamples()
        }
        phase = .feedback
        sequenceTask = Task {
            await shakeAndFlashRed()
            guard !Task.isCancelled else { return }
            if vm.isTestMode || wrongCount >= Self.maxWrongAttempts {
                reveal(correct: false)
            } else {
                phase = .answering
                inputFocused = true
            }
        }
    }

    private func selectVisualOption(_ option: WordDiagram) {
        guard phase == .answering, let target = presentation.visualQuiz?.target else { return }
        selectedVisualOptionId = option.id
        phase = .feedback

        if option.id == target.id {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            sequenceTask = Task {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                reveal(correct: true)
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            wrongCount += 1
            sequenceTask = Task {
                await shakeAndFlashRed()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(0.45))
                guard !Task.isCancelled else { return }
                reveal(correct: false)
            }
        }
    }

    // MARK: - Reveal and advance

    /// Flips to the answer and records the result. The flip, the footer swap,
    /// the keyboard dismissal and the answer styling share one transaction,
    /// so the card turns and moves as a single animation in a single update.
    /// A correct typed answer then moves on by itself after a pause.
    private func reveal(correct: Bool, autoAdvance: Bool = false) {
        guard !isRevealed else { return }
        withAnimation(.easeInOut(duration: 0.32)) {
            showsAnswerSide = true
            wasCorrect = correct
            phase = .revealing
            inputFocused = false
        }

        let outcome = vm.recordResult(correct: correct, context: presentation.mistakeContext)
        if vm.autoPlayPronunciation && card.cardType != .recognition {
            SpeechService.shared.speak(presentation.answerText, languageCode: presentation.answerLanguage.speechCode)
        }

        let notice = SessionNotice.make(for: outcome)
        sequenceTask = Task {
            async let noticeFinished = presentSessionNotice(notice)
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            guard autoAdvance else {
                _ = await noticeFinished
                phase = .revealed
                return
            }
            phase = .revealed
            try? await Task.sleep(for: presentation.autoAdvanceDelay)
            guard !Task.isCancelled, await noticeFinished else { return }
            leave(duration: 0.3)
        }
    }

    private func leave(duration: Double) {
        guard phase != .leaving else { return }
        sequenceTask?.cancel()
        sessionNotice = nil
        let cardID = card.id
        withAnimation(.easeIn(duration: duration)) {
            phase = .leaving
        } completion: {
            // The session may have ended meanwhile.
            if vm.presentation?.card.id == cardID { vm.advance() }
        }
    }

    /// Shows the notice, if any, and returns whether it ran to completion.
    private func presentSessionNotice(_ notice: SessionNotice?) async -> Bool {
        guard let notice else { return true }

        if let haptic = notice.haptic {
            UINotificationFeedbackGenerator().notificationOccurred(haptic)
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            sessionNotice = notice
        }
        do {
            try await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.25)) {
                sessionNotice = nil
            }
            try await Task.sleep(for: .seconds(0.25))
            return true
        } catch {
            return false
        }
    }

    private func shakeAndFlashRed() async {
        withAnimation(.easeIn(duration: 0.12)) {
            promptHighlight = Color.red.opacity(0.2)
        }
        withAnimation(.easeInOut(duration: 0.42)) {
            shakeTrigger += 1.0
        }
        try? await Task.sleep(for: .seconds(0.35))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            promptHighlight = Theme.surface
        }
        try? await Task.sleep(for: .seconds(0.12))
    }

    // MARK: - Hints and examples

    private var canRequestHint: Bool {
        guard !isRevealed else { return false }
        switch hint {
        case .none: return true
        case .loading: return false
        case .shown(_, let allowsAnother): return allowsAnother
        }
    }

    private func requestHint() {
        guard phase == .answering, canRequestHint else { return }

        switch card.cardType {
        case .conjugation:
            let tense = presentation.conjugation?.tense ?? "unknown tense"
            let pronoun = presentation.conjugation?.pronoun ?? "unknown"
            withAnimation { hint = .shown("Tense: \(tense) • Pronoun: \(pronoun)", allowsAnother: false) }
        case .production:
            // EN → IT: other ways to translate the Italian word.
            let meanings = [card.userWord.word.english] + presentation.alternatives
            let others = meanings.filter { $0.lowercased() != card.prompt.lowercased() }
            if others.isEmpty {
                loadHint { await AppleIntelligenceService.generateFillInTheBlankHint(for: card.correctAnswer) }
            } else {
                withAnimation { hint = .shown("Also means: \(others.joined(separator: ", "))", allowsAnother: false) }
            }
        case .recognition:
            // IT → EN: a contextual sentence.
            loadHint { await AppleIntelligenceService.generateHintSentence(for: card.prompt) }
        }
    }

    /// Falls back to the answer's first letter when no sentence is generated.
    private func loadHint(_ generate: @escaping () async -> String?) {
        hint = .loading
        hintTask = Task {
            let sentence = await generate()
            let fallback = "\(card.correctAnswer.first.map(String.init) ?? "?")..."
            withAnimation { hint = .shown(sentence ?? fallback, allowsAnother: false) }
        }
    }

    private func generateExamples() {
        guard card.cardType != .conjugation, examples == .none else { return }
        let word = card.userWord.word
        examples = .loading
        examplesTask = Task {
            let sentences = await AppleIntelligenceService.generateExamples(
                for: word.italian,
                englishMeaning: word.english,
                topic: word.level
            )
            guard !Task.isCancelled else { return }
            withAnimation { examples = .loaded(sentences) }
        }
    }
}
