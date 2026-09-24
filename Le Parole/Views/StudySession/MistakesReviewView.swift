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
                    let diagram = SailingDiagramService.diagram(for: word.userWord.word)
                    let concept = ConceptService.shared.concept(for: word.userWord.word.italian)
                    let hasRichContent = diagram != nil || concept != nil
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
                                if !hasRichContent {
                                    Spacer(minLength: 32)
                                }

                                MistakeCard(
                                    item: word,
                                    diagram: diagram,
                                    concept: concept,
                                    onSelectDiagram: { diag in activeSheet = .diagram(diag) },
                                    onSelectRelatedConcept: { item in activeSheet = .relatedConcept(item) },
                                    onSelectRelatedTerm: { term in activeSheet = .relatedTerm(term) }
                                )

                                if !hasRichContent {
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
                RelatedWordSheet(term: item.term, relatedItem: item)
            case .relatedTerm(let term):
                RelatedWordSheet(term: term)
            }
        }
    }
}

private struct MistakeCard: View {
    let item: MistakeItem
    let diagram: WordDiagram?
    let concept: WordConcept?
    var onSelectDiagram: (WordDiagram) -> Void
    var onSelectRelatedConcept: (RelatedConceptItem) -> Void
    var onSelectRelatedTerm: (String) -> Void

    private var hasRichContent: Bool { diagram != nil || concept != nil }

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

                        SpeakButton(text: completedSentence, size: 30)
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
                    SpeakButton(text: item.userWord.word.italian)
                        .padding(18)
                }
                .themeCard(cornerRadius: Theme.prominentCardCornerRadius, elevated: true)
            }

            // MARK: - Technical Manual Diagram Card (if available)
            if let diagram {
                DiagramCard(diagram: diagram, onOpen: onSelectDiagram)
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
