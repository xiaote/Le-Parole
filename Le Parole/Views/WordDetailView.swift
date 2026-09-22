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

    private var stageLabel: String {
        switch userWord.stage {
        case .new:         "Not started"
        case .skipped:     "Skipped"
        case .recognition: "Recognition"
        case .production:  "Production"
        case .mastered:    "Mastered"
        }
    }

    private var stageIcon: String {
        switch userWord.stage {
        case .new:         "circle"
        case .skipped:     "slash.circle"
        case .recognition: "eye"
        case .production:  "pencil"
        case .mastered:    "checkmark.seal.fill"
        }
    }

    private var stageColor: Color {
        switch userWord.stage {
        case .new:         Color(.systemGray3)
        case .skipped:     Color(.systemGray)
        case .recognition: Theme.recognition
        case .production:  Theme.production
        case .mastered:    Theme.mastered
        }
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

                                Button {
                                    SpeechService.shared.speak(userWord.word.italian, languageCode: "it-IT")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.theme(.subheadline, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.primary, in: Circle())
                                }
                                .buttonStyle(.plain)
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
                            Text(userWord.word.level)
                                .font(.theme(.subheadline, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.chipBackground)
                                .clipShape(Capsule())

                            Label(stageLabel, systemImage: stageIcon)
                                .font(.theme(.subheadline, weight: .semibold))
                                .foregroundStyle(stageColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(stageColor.opacity(0.12))
                                .clipShape(Capsule())
                        }

                        if let diagram {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Manuale CVC", systemImage: "sailboat.fill")
                                        .font(.theme(.subheadline, weight: .semibold))
                                        .foregroundStyle(Theme.primary)

                                    Spacer()

                                    Button {
                                        activeSheet = .diagram(diagram)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Tavola intera")
                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        }
                                        .font(.theme(.caption, weight: .semibold))
                                        .foregroundStyle(Theme.primary)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    activeSheet = .diagram(diagram)
                                } label: {
                                    Image(diagram.revealedImageName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 260)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)

                                if let caption = diagram.caption {
                                    Text(caption)
                                        .font(.theme(.subheadline))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .themeCard()
                        }

                        if let concept {
                            ConceptSectionView(concept: concept) { term in
                                activeSheet = .relatedTerm(term)
                            }
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
