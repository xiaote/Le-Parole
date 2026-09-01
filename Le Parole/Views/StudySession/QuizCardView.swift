import SwiftUI
import GRDB
import Translation

struct QuizCardView: View {
    let card: StudyCard
    let vm: StudySessionViewModel

    private static let maxWrongAttempts = 3

    private struct SessionNotice: Equatable {
        let icon: String
        let title: String
        let detail: String?

        static let mastered = SessionNotice(icon: "sparkles", title: "Mastered!", detail: nil)

        static func reviewScheduled(_ feedback: ReviewScheduleFeedback) -> SessionNotice {
            SessionNotice(
                icon: "checkmark.seal.fill",
                title: feedback.title,
                detail: feedback.detail
            )
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
    @State private var shakeOffset: CGFloat = 0
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
        if case .success(_, _, let explanation, _, _, _) = vm.conjugationCache[card.id] { return explanation }
        return nil
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
            VStack(spacing: 0) {
            Text("\(vm.currentIndex + 1) of \(vm.totalCardCount)")
                .font(.theme(.subheadline))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()

            flipCard
                .padding(.horizontal, 20)
                .scaleEffect(cardScale)
                .offset(x: swipeOffset + shakeOffset)
                .opacity(cardOpacity)
                .layoutPriority(1)

            Spacer()

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
                .padding(.bottom, 24)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)), removal: .opacity))
            }

            Group {
                if isRevealed {
                    incorrectRevealedControls
                } else {
                    inputControls
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isRevealed)

            Spacer().frame(height: 32)
        }

            if let sessionNotice {
                HStack(spacing: 12) {
                    Image(systemName: sessionNotice.icon)
                        .font(.theme(.title3, weight: .bold))
                        .foregroundStyle(Theme.mastered)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionNotice.title)
                            .font(.theme(.headline, weight: .bold))
                            .foregroundStyle(Theme.mastered)

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
            inputFocused = true
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
                showHintArea: true,
                isLoading: isGeneratingConjugation
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
                isLoading: false
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
            guard !interactionLocked else { return }
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
        speakAction: @escaping () -> Void
    ) -> some View {
        // The back face has a static 180° inner rotation that is cancelled by the outer
        // flip animation's 180°, so layout coordinates map directly to visual coordinates
        // on both faces — .topLeading always appears at top-left.
        ZStack(alignment: .topLeading) {
            VStack(spacing: 12) {
                Text(language.uppercased())
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .tracking(1)

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else {
                    Text(word)
                        .font(card.cardType == .conjugation ? Theme.wordPrompt : Theme.wordDisplay)
                        .lineLimit(4)
                        .multilineTextAlignment(.center)
                        
                    if let explanation = explanation {
                        Text(explanation)
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                            .padding(.horizontal, 16)
                    }

                    if showHintArea && (isLoadingHint || hintText != nil) {
                        if isLoadingHint {
                            ProgressView()
                                .scaleEffect(0.75)
                                .padding(.top, 4)
                        } else if let hint = hintText {
                            Text(hint)
                                .font(.theme(.callout))
                                .italic()
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        }
                    } else if let alts = alternatives, !alts.isEmpty {
                        Text("Also: " + alts.joined(separator: ", "))
                            .font(.theme(.subheadline))
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                            .padding(.horizontal, 16)
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
            .padding(32)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 200)

            Button(action: speakAction) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.theme(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.primary, in: Circle())
            }
            .padding(20)
        }
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous).stroke(borderColor, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.studyCardCornerRadius, style: .continuous))
        .shadow(color: Theme.cardShadow, radius: 16, y: 8)
    }

    // MARK: - Controls

    private var inputControls: some View {
        VStack(spacing: 16) {
            if wrongCount > 0 && !vm.isTestMode {
                let remaining = Self.maxWrongAttempts - wrongCount
                Text(remaining == 1 ? "1 attempt left" : "\(remaining) attempts left")
                    .font(.theme(.caption))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: wrongCount)
            }

            TextField(
                card.cardType == .recognition ? "Type English..." : "Type Italian...",
                text: $input
            )
            .multilineTextAlignment(.center)
            .font(.theme(.body))
            .padding(.vertical, 13)
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
                inputFocused = true
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                if !vm.isTestMode {
                    Button("Hint") { requestHint() }
                        .buttonStyle(SecondaryButtonStyle())
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
                .buttonStyle(PrimaryButtonStyle())
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || interactionLocked || isGeneratingConjugation)
            }
            .padding(.horizontal, 20)
        }
    }

    private var incorrectRevealedControls: some View {
        Button("Next →") { vm.advance() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
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
        isFlipped = false
        flipAngle = 0
        isRevealed = false
        wasCorrect = nil
        wrongCount = 0
        shakeOffset = 0
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
        isGeneratingExamples = true
        examplesTask = Task { @MainActor in
            let sentences = await AppleIntelligenceService.generateExamples(for: targetItalian)
            guard !Task.isCancelled, card.id == requestedCardID else { return }
            withAnimation {
                exampleSentences = sentences
                isGeneratingExamples = false
                examplesTask = nil
            }
        }
    }

    private var canRequestHint: Bool {
        if isRevealed || interactionLocked || isLoadingHint { return false }
        if hintText == nil { return true }
        if hintText?.hasPrefix("Correct, but") == true { return true }
        if hintText?.hasPrefix("Close! Check") == true { return true }
        if hintText?.hasPrefix("Correct word, but check") == true { return true }
        return false
    }

    private func requestHint() {
        guard canRequestHint else { return }

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
                guard !Task.isCancelled else { return }
                isGrading = false
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
        examplesTask?.cancel()
        examplesTask = nil
        isGeneratingExamples = false
        
        if card.cardType == .conjugation {
            inputFocused = false
        }
        
        let wasMastered = card.userWord.stage == .mastered
        
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
            
            let context = MistakeContext(
                question: conjugationSentence,
                answer: conjugationAnswer,
                explanation: conjugationExplanation
            )
            vm.recordResult(correct: true, context: context)
            let reviewFeedback = wasMastered ? vm.currentReviewScheduleFeedback : nil

            let isNowMastered = vm.cards[vm.currentIndex].userWord.stage == .mastered
            let notice: SessionNotice?
            if !wasMastered && isNowMastered {
                notice = .mastered
            } else if let reviewFeedback {
                notice = .reviewScheduled(reviewFeedback)
            } else {
                notice = nil
            }
            
            let hasInflections = (card.cardType == .production) && (inflectionsText != nil || isGeneratingInflections)
            let hasAlternatives = (card.cardType == .recognition) && !card.userWord.word.cleanAlternatives.isEmpty
            let hasExplanation = card.cardType == .conjugation && conjugationExplanation != nil
            
            let remainingDelay: Double
            if hasExplanation {
                remainingDelay = 4.5
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

        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        wrongCount += 1
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
            
            let context = card.cardType == .conjugation ? MistakeContext(
                question: conjugationSentence,
                answer: conjugationAnswer,
                explanation: conjugationExplanation
            ) : nil
            vm.recordResult(correct: correct, context: context)
            
            interactionLocked = false
        }
    }

    private func toggleFlip() {
        animateFlip(to: isFlipped ? 0 : 180)
    }

    private func animateFlip(to angle: Double) {
        withAnimation(.easeInOut(duration: 0.32)) {
            flipAngle = angle
            isFlipped = angle >= 90
        }
    }

    private func performShakeAndRed() async {
        withAnimation(.easeIn(duration: 0.1)) {
            frontHighlight = Color.red.opacity(0.25)
        }

        let amplitudes: [CGFloat] = [14, -14, 10, -10, 6, -6, 0]
        for amplitude in amplitudes {
            withAnimation(.linear(duration: 0.055)) {
                shakeOffset = amplitude
            }
            try? await Task.sleep(for: .seconds(0.055))
        }

        try? await Task.sleep(for: .seconds(0.25))

        withAnimation(.easeOut(duration: 0.3)) {
            frontHighlight = Theme.surface
        }
        try? await Task.sleep(for: .seconds(0.3))
    }
}
