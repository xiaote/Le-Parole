import SwiftUI

struct MistakesReviewView: View {
    let words: [MistakeItem]
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case diagram(WordDiagram)
        case relatedConcept(RelatedConceptItem)
        case relatedTerm(String)

        var id: String {
            switch self {
            case .diagram(let d): return "diagram_\(d.id)"
            case .relatedConcept(let item): return "concept_\(item.id)"
            case .relatedTerm(let t): return "term_\(t)"
            }
        }
    }

    private var current: MistakeItem? {
        guard currentIndex < words.count else { return nil }
        return words[currentIndex]
    }

    private func hasRichContent(for item: MistakeItem) -> Bool {
        let hasDiagram = SailingDiagramService.diagram(for: item.userWord.word.italian) != nil
        let hasConcept = ConceptService.shared.concept(for: item.userWord.word.italian) != nil
        return hasDiagram || hasConcept
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                if words.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.mastered)
                        Text("No mistakes to review!")
                            .font(.theme(.title3, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let word = current {
                    VStack(spacing: 0) {
                        // Header Progress
                        VStack(spacing: 6) {
                            ProgressView(value: Double(currentIndex + 1), total: Double(words.count))
                                .tint(Theme.primary)

                            HStack {
                                Text("Mistake \(currentIndex + 1) of \(words.count)")
                                    .font(.theme(.caption, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if word.cardType == .conjugation {
                                    Text("CONJUGATION")
                                        .font(.theme(.caption2, weight: .bold))
                                        .foregroundStyle(Theme.playfulAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Theme.playfulAccent.opacity(0.12))
                                        .clipShape(Capsule())
                                } else {
                                    Text(word.userWord.word.level.uppercased())
                                        .font(.theme(.caption2, weight: .bold))
                                        .foregroundStyle(Theme.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Theme.chipBackground)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                        // Scrollable Mistake Content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if !hasRichContent(for: word) {
                                    Spacer(minLength: 32)
                                }

                                MistakeCard(
                                    item: word,
                                    hasRichContent: hasRichContent(for: word),
                                    onSelectDiagram: { diag in activeSheet = .diagram(diag) },
                                    onSelectRelatedConcept: { item in activeSheet = .relatedConcept(item) },
                                    onSelectRelatedTerm: { term in activeSheet = .relatedTerm(term) }
                                )

                                if !hasRichContent(for: word) {
                                    Spacer(minLength: 32)
                                } else {
                                    Spacer(minLength: 20)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }

                        // Bottom Navigation Bar
                        VStack(spacing: 0) {
                            Divider().background(Theme.border.opacity(0.6))

                            HStack(spacing: 12) {
                                if words.count > 1 {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            if currentIndex > 0 {
                                                currentIndex -= 1
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "chevron.left")
                                            Text("Previous")
                                        }
                                        .font(.theme(.body, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Theme.surface)
                                        .foregroundStyle(currentIndex > 0 ? Theme.primary : Color.secondary.opacity(0.4))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                                                .stroke(Theme.border, lineWidth: 1)
                                                .allowsHitTesting(false)
                                        )
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                    .disabled(currentIndex == 0)
                                }

                                Button {
                                    if currentIndex + 1 < words.count {
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            currentIndex += 1
                                        }
                                    } else {
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(currentIndex + 1 < words.count ? "Next" : "Done")
                                        if currentIndex + 1 < words.count {
                                            Image(systemName: "chevron.right")
                                        } else {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    .font(.theme(.body, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.primary)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 24)
                            .background(Theme.canvas)
                        }
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .diagram(let diag):
                DiagramPlateSheet(diagram: diag)
            case .relatedConcept(let item):
                RelatedWordSheet(item: item)
            case .relatedTerm(let term):
                RelatedWordSheet(term: term)
            }
        }
    }
}

private struct MistakeCard: View {
    let item: MistakeItem
    var hasRichContent: Bool = false
    var onSelectDiagram: (WordDiagram) -> Void
    var onSelectRelatedConcept: (RelatedConceptItem) -> Void
    var onSelectRelatedTerm: (String) -> Void

    private var diagram: WordDiagram? {
        SailingDiagramService.diagram(for: item.userWord.word.italian)
    }

    private var concept: WordConcept? {
        ConceptService.shared.concept(for: item.userWord.word.italian)
    }

    var body: some View {
        VStack(spacing: 16) {
            // MARK: - Word Definition & Header Card
            if item.cardType == .conjugation,
               let context = item.context,
               let question = context.question,
               let answer = context.answer {
                let completedSentence = question.replacingOccurrences(of: "_____", with: answer)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMPLETED SENTENCE")
                                .font(.theme(.caption2, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .tracking(0.8)

                            Text(completedSentence)
                                .font(Theme.wordPrompt)
                                .foregroundStyle(.primary)
                        }

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            SpeechService.shared.speak(completedSentence, languageCode: "it-IT")
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.theme(.caption, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.primary, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }

                    if let explanation = context.explanation {
                        Divider().background(Theme.border.opacity(0.6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RULE")
                                .font(.theme(.caption2, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.8)

                            Text(explanation)
                                .font(.theme(.subheadline))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().background(Theme.border.opacity(0.6))

                    HStack {
                        Text("Base verb:")
                            .font(.theme(.caption))
                            .foregroundStyle(.secondary)
                        Text(item.userWord.word.italian)
                            .font(.theme(.caption, weight: .bold))
                        Text("(\(item.userWord.word.english))")
                            .font(.theme(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, hasRichContent ? 20 : 36)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .themeCard(cornerRadius: Theme.prominentCardCornerRadius, elevated: true)
            } else {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: hasRichContent ? 14 : 22) {
                        Text(item.userWord.word.italian)
                            .font(Theme.wordDisplay)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 48)

                        if let pos = item.userWord.word.partOfSpeech {
                            Text(pos)
                                .font(.theme(.subheadline))
                                .italic()
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .padding(.horizontal, 24)
                            .opacity(0.6)

                        VStack(spacing: 6) {
                            Text(item.userWord.word.english)
                                .font(Theme.wordPrompt)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)

                            if !item.userWord.word.cleanAlternatives.isEmpty {
                                Text("Also: " + item.userWord.word.cleanAlternatives.joined(separator: ", "))
                                    .font(.theme(.subheadline))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 2)
                            }

                            if let inflections = item.userWord.word.inflections, !inflections.isEmpty {
                                Text(inflections)
                                    .font(.theme(.caption))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.vertical, hasRichContent ? 20 : 36)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: hasRichContent ? nil : 240)

                    // Audio speaker button placed in top-left matching QuizCardView
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        SpeechService.shared.speak(item.userWord.word.italian, languageCode: "it-IT")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.theme(.caption, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.primary, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(18)
                }
                .themeCard(cornerRadius: Theme.prominentCardCornerRadius, elevated: true)
            }

            // MARK: - Technical Manual Diagram Card (if available)
            if let diagram {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Manuale CVC", systemImage: "sailboat.fill")
                            .font(.theme(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.primary)

                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSelectDiagram(diagram)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Tavola intera")
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            .font(.theme(.caption, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Theme.primary.opacity(0.1))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSelectDiagram(diagram)
                    } label: {
                        Image(diagram.revealedImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    .allowsHitTesting(false)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())

                    if let caption = diagram.caption {
                        Text(caption)
                            .font(.theme(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themeCard(cornerRadius: Theme.cardCornerRadius)
            }

            // MARK: - Concept Learning & Spoken Commands (if available)
            if let concept {
                ConceptSectionView(
                    concept: concept,
                    onSelectRelatedItem: { item in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSelectRelatedConcept(item)
                    },
                    onSelectRelatedTerm: { term in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onSelectRelatedTerm(term)
                    }
                )
            }
        }
    }
}
