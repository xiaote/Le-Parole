import SwiftUI

struct WordDetailView: View {
    let userWord: UserWord
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case diagram(WordDiagram)
        case relatedTerm(String)

        var id: String {
            switch self {
            case .diagram(let d): return "diagram_\(d.id)"
            case .relatedTerm(let t): return "term_\(t)"
            }
        }
    }

    private var diagram: WordDiagram? {
        SailingDiagramService.diagram(for: userWord.word.italian)
    }

    private var concept: WordConcept? {
        ConceptService.shared.concept(for: userWord.word.italian)
    }

    private var accuracy: String {
        guard userWord.totalAttempts > 0 else { return "—" }
        let pct = Int((Double(userWord.totalCorrect) / Double(userWord.totalAttempts)) * 100)
        return "\(pct)%"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text(userWord.word.italian)
                                    .font(Theme.wordDisplay)
                                    .multilineTextAlignment(.center)

                                SpeakButton(
                                    text: userWord.word.italian,
                                    iconFont: .theme(.subheadline, weight: .semibold)
                                )
                            }

                            if let pos = userWord.word.partOfSpeech {
                                Text(pos)
                                    .font(.theme(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }

                            Text(userWord.word.english)
                                .font(.theme(.title3))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            if !userWord.word.cleanAlternatives.isEmpty {
                                Text(userWord.word.cleanAlternatives.joined(separator: ", "))
                                    .font(.theme(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 8)

                        HStack(spacing: 12) {
                            LevelChip(level: userWord.word.level, isLarge: true)

                            Label(userWord.stage.title, systemImage: userWord.stage.iconName)
                                .font(.theme(.subheadline, weight: .semibold))
                                .foregroundStyle(userWord.stage.color)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(userWord.stage.color.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if let diagram {
                            DiagramCard(diagram: diagram, imageMaxHeight: 260) { activeSheet = .diagram($0) }
                        }

                        if let concept {
                            ConceptSectionView(concept: concept, onSelectRelatedTerm: { term in
                                activeSheet = .relatedTerm(term)
                            })
                        }

                        if userWord.totalAttempts > 0 {
                            VStack(spacing: 0) {
                                statRow("Accuracy", value: accuracy)
                                Divider().padding(.leading, 16)
                                statRow("Total attempts", value: "\(userWord.totalAttempts)")
                                if userWord.stage != .new && userWord.stage != .skipped {
                                    Divider().padding(.leading, 16)
                                    statRow("Next review", value: userWord.nextReviewDate.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .themeCard()
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Word Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .diagram(let diag):
                    DiagramPlateSheet(diagram: diag)
                case .relatedTerm(let term):
                    RelatedWordSheet(term: term)
                }
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.theme(.body, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
