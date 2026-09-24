import SwiftUI
import GRDB
import Translation

struct QuizCardView: View {
    let card: StudyCard
    let vm: StudySessionViewModel
    private let sailingDiagram: WordDiagram?
    private let wordConcept: WordConcept?
    // Held in @State so the shuffled options are computed once per card
    // (the view is `.id(card.id)`) and don't reorder when the parent re-renders.
    @State private var visualQuizData: VisualQuizData?

    init(card: StudyCard, vm: StudySessionViewModel) {
        self.card = card
        self.vm = vm
        let italian = card.userWord.word.italian
        self.sailingDiagram = SailingDiagramService.diagram(for: italian)
        self.wordConcept = ConceptService.shared.concept(for: italian)
        self._visualQuizData = State(initialValue: card.cardType == .recognition
            ? SailingDiagramService.visualQuizOptions(for: italian)
            : nil)
    }

    private static let maxWrongAttempts = 3

    @State private var input = ""
    @State private var isFlipped = false
    // Keep the rendered angle independent from the logical state. A spring on a
    // boolean-driven rotation can overshoot 180° and briefly reveal the wrong face.
    @State private var flipAngle: Double = 0
    @State private var isRevealed = false
    @State private var showDetails = false
    @State private var wasCorrect: Bool? = nil
    @FocusState private var inputFocused: Bool
    @State private var wrongCount = 0
    @State private var shakeTrigger: CGFloat = 0
    @State private var frontHighlight: Color = Theme.surface
    @State private var swipeOffset: CGFloat = 0
    @State private var cardOpacity: Double = 0.0
    @State private var cardScale: CGFloat = 0.96
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

    // Conjugation states (computed from vm cache)
    private var isGeneratingConjugation: Bool {
        if card.cardType != .conjugation { return false }
        return vm.conjugationCache[card.id] == nil || {
            if case .loading = vm.conjugationCache[card.id] { return true }
            return false
        }()
    }
    
    private var conjugationSentence: String? {
        if case .success(let challenge) = vm.conjugationCache[card.id] { return challenge.sentence }
        return nil
    }

    private var conjugationAnswer: String? {
        if case .success(let challenge) = vm.conjugationCache[card.id] { return challenge.answer }
        return nil
    }

    private var conjugationExplanation: String? {
        if case .success(let challenge) = vm.conjugationCache[card.id] {
            return conciseExplanation(challenge.explanation)
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
        if case .success(let challenge) = vm.conjugationCache[card.id] { return challenge.tense }
        return nil
    }

    private var conjugationPronoun: String? {
        if case .success(let challenge) = vm.conjugationCache[card.id] { return challenge.pronoun }
        return nil
    }

    private var geminiEnglishTranslation: String? {
        if case .success(let challenge) = vm.conjugationCache[card.id] { return challenge.englishTranslation }
        return nil
    }



    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        flipCard
                            .padding(.horizontal, 20)
                            .compositingGroup()
                            .scaleEffect(cardScale)
                            .offset(x: swipeOffset)
                            .modifier(ShakeEffect(animatableData: shakeTrigger))
                            .opacity(cardOpacity)

                        if let quiz = visualQuizData, !isRevealed {
                            VisualChoiceGridView(
                                quiz: quiz,
                                selectedOptionId: selectedVisualOptionId,
                                isRevealed: isRevealed,
                                interactionLocked: interactionLocked,
                                onSelect: { option, target in
                                    selectVisualOption(option, target: target)
                                },
                                onZoom: { option in
                                    activeSheet = .diagramCrop(diagram: option, imageName: option.promptImageName)
                                }
                            )
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
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)), removal: .opacity))
                        }

                        if (showDetails || isRevealed), let concept = wordConcept {
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
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)

                controlsFooter
            }

            if let sessionNotice {
                SessionNoticeView(notice: sessionNotice)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardOpacity = 1.0
                cardScale = 1.0
            }
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled else { return }
                playFrontAudioIfNeeded()
                preloadInflectionsIfNeeded()
            }
        }
        .task(id: card.id) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !isRevealed, !Task.isCancelled else { return }
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
                isBackFace: false,
                diagramImageName: card.cardType == .production ? sailingDiagram?.promptImageName : nil,
                diagramAction: {
                    inputFocused = false
                    if let d = sailingDiagram { activeSheet = .diagram(d) }
                }
            ) { SpeechService.shared.speak(card.cardType == .conjugation ? (conjugationSentence ?? "") : card.prompt, languageCode: frontLanguageCode) }
            .modifier(FlipEffect(angle: flipAngle, isBack: false, perspective: 0.25))

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
                isBackFace: true,
                diagramImageName: sailingDiagram?.revealedImageName,
                diagramAction: {
                    inputFocused = false
                    if let d = sailingDiagram { activeSheet = .diagram(d) }
                }
            ) { SpeechService.shared.speak(card.cardType == .conjugation ? completedConjugationSentence : card.correctAnswer, languageCode: backLanguageCode) }
            .modifier(FlipEffect(angle: flipAngle, isBack: true, perspective: 0.25))
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
        isBackFace: Bool,
        diagramImageName: String? = nil,
        diagramAction: (() -> Void)? = nil,
        speakAction: @escaping () -> Void
    ) -> some View {
        let isCardExpanded = isBackFace && (showDetails || isRevealed)
        let imageMaxHeight: CGFloat = isCardExpanded ? 330 : 210
        let cardMinHeight: CGFloat = (diagramImageName != nil)
            ? (isCardExpanded ? 500 : 320)
            : (visualQuizData != nil ? (isCardExpanded ? 225 : 120) : (isCardExpanded ? 190 : 170))
        let cardPadding: CGFloat = (diagramImageName != nil)
            ? (isCardExpanded ? 16 : 18)
            : (visualQuizData != nil ? (isCardExpanded ? 20 : 14) : 22)

        // The back face has a static 180° inner rotation that is cancelled by the outer
        // flip animation's 180°, so layout coordinates map directly to visual coordinates
        // on both faces — .topLeading always appears at top-left.
        return ZStack(alignment: .topLeading) {
            VStack(spacing: diagramImageName != nil ? 10 : (visualQuizData != nil && !isCardExpanded ? 6 : 12)) {
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
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, y: 3)
                                    .frame(maxHeight: imageMaxHeight)

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

                    if (showDetails || isRevealed) {
                        if let translation = geminiEnglishTranslation {
                            Text(translation)
                                .font(.theme(.body))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        }

                        if let explanation = conjugationExplanation {
                            Text(explanation)
                                .font(.theme(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        }
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

                    if (showDetails || isRevealed) {
                        if isGeneratingInflections {
                            ProgressView()
                                .scaleEffect(0.75)
                                .padding(.top, 4)
                                .transition(.opacity)
                        } else if let infl = inflections {
                            Text(infl)
                                .font(.theme(.subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        }
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
        .compositingGroup()
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

    private var controlsFooter: some View {
        QuizControlsFooterView(
            isRevealed: isRevealed,
            showControls: isRevealed || visualQuizData == nil,
            cardType: card.cardType,
            input: $input,
            isFocused: $inputFocused,
            isTestMode: vm.isTestMode,
            canRequestHint: canRequestHint,
            isGrading: isGrading,
            isGeneratingConjugation: isGeneratingConjugation,
            onRequestHint: { requestHint() },
            onSubmit: { submitAnswer() },
            onNext: { advanceToNextCard() }
        )
    }

    private func advanceToNextCard() {
        guard !interactionLocked else { return }
        interactionLocked = true
        animationTask?.cancel()
        sessionNotice = nil
        withAnimation(.easeIn(duration: 0.25)) {
            swipeOffset = 500
            cardOpacity = 0
        }
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            vm.advance()
        }
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
            isGrading = true
            gradingTask = Task { @MainActor in
                let dbSynonymMatch = await vm.isValidItalianSynonym(input: trimmed)
                isGrading = false
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
        withAnimation(.easeInOut(duration: 0.25)) {
            isRevealed = true
            inputFocused = false
        }
        examplesTask?.cancel()
        examplesTask = nil
        isGeneratingExamples = false
        
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

        animationTask = Task { @MainActor in
            animateFlip(to: 180)
            
            if vm.autoPlayPronunciation {
                if card.cardType == .production {
                    SpeechService.shared.speak(card.correctAnswer, languageCode: "it-IT")
                } else if card.cardType == .conjugation {
                    SpeechService.shared.speak(completedConjugationSentence, languageCode: "it-IT")
                }
            }

            async let noticeCompleted = presentSessionNotice(notice)

            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showDetails = true
            }
            
            // Allow user to tap Next or interact immediately
            interactionLocked = false

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
            
            try? await Task.sleep(for: .seconds(remainingDelay))
            guard !Task.isCancelled, await noticeCompleted else { return }
            
            interactionLocked = true
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            sessionNotice = notice
        }

        do {
            try await Task.sleep(for: .seconds(1.5))
        } catch {
            return false
        }

        withAnimation(.easeOut(duration: 0.25)) {
            sessionNotice = nil
        }

        do {
            try await Task.sleep(for: .seconds(0.25))
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
        withAnimation(.easeInOut(duration: 0.25)) {
            isRevealed = true
            inputFocused = false
        }

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
        let notice = SessionNotice.make(for: outcome)

        animationTask = Task { @MainActor in
            animateFlip(to: 180)
            
            if vm.autoPlayPronunciation {
                if card.cardType == .production {
                    SpeechService.shared.speak(card.correctAnswer, languageCode: "it-IT")
                } else if card.cardType == .conjugation {
                    SpeechService.shared.speak(completedConjugationSentence, languageCode: "it-IT")
                }
            }

            async let noticeCompleted = presentSessionNotice(notice)

            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showDetails = true
            }
            
            _ = await noticeCompleted
            interactionLocked = false
        }
    }

    private func toggleFlip() {
        withAnimation(.easeInOut(duration: 0.25)) {
            inputFocused = false
        }
        if isFlipped {
            withAnimation(.easeInOut(duration: 0.2)) {
                showDetails = false
            }
            animateFlip(to: 0)
        } else {
            animateFlip(to: 180)
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showDetails = true
                }
            }
        }
    }

    private func animateFlip(to angle: Double) {
        withAnimation(.easeInOut(duration: 0.32)) {
            flipAngle = angle
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
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

