import SwiftUI

struct RelatedWordSheet: View {
    let term: String
    let relatedItem: RelatedConceptItem?
    @Environment(\.dismiss) private var dismiss
    @State private var currentTerm: String
    @State private var word: Word? = nil
    @State private var isLoading = true

    @State private var presentedPlate: WordDiagram? = nil

    init(term: String, relatedItem: RelatedConceptItem? = nil) {
        self.term = term
        self.relatedItem = relatedItem
        _currentTerm = State(initialValue: term)
    }

    init(item: RelatedConceptItem) {
        self.term = item.term
        self.relatedItem = item
        _currentTerm = State(initialValue: item.term)
    }

    private var concept: WordConcept? {
        ConceptService.shared.concept(for: currentTerm)
    }

    private var diagram: WordDiagram? {
        SailingDiagramService.diagram(for: currentTerm)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Relationship Context Banner (if arrived via a connected concept)
                        if let relatedItem, let rel = relatedItem.cleanRelationship, !rel.isEmpty {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: relatedItem.effectiveType.iconName)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(relatedItem.effectiveType.title.uppercased())
                                        .font(.system(size: 9.5, weight: .bold))
                                        .tracking(0.6)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(relatedItem.effectiveType.tintColor.opacity(0.15))
                                .foregroundStyle(relatedItem.effectiveType.tintColor)
                                .clipShape(Capsule())

                                Text(rel)
                                    .font(.theme(.subheadline, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(relatedItem.effectiveType.tintColor.opacity(0.3), lineWidth: 1)
                                    .allowsHitTesting(false)
                            )
                        }

                        // Word Header Card
                        VStack(spacing: 8) {
                            HStack {
                                Text(currentTerm)
                                    .font(.theme(.title, weight: .bold))
                                    .foregroundStyle(Theme.primary)

                                Spacer()

                                Button {
                                    SpeechService.shared.speak(currentTerm, languageCode: "it-IT")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.theme(.caption, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.primary, in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(PressableButtonStyle())
                            }

                            if let word = word {
                                Text(word.english)
                                    .font(.theme(.headline))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !word.cleanAlternatives.isEmpty {
                                    Text("Also: " + word.cleanAlternatives.joined(separator: ", "))
                                        .font(.theme(.caption))
                                        .italic()
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Loading definition…")
                                        .font(.theme(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            }
                        }
                        .padding(18)
                        .themeCard(cornerRadius: Theme.cardCornerRadius)

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
                                        presentedPlate = diagram
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
                                    presentedPlate = diagram
                                } label: {
                                    Image(diagram.revealedImageName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 220)
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

                        // Concept Deep Dive if available
                        if let concept = concept {
                            ConceptSectionView(concept: concept) { nextTerm in
                                // Nested chip tap: update current term
                                Task {
                                    await loadTerm(nextTerm)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Related Concept")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.theme(.body, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $presentedPlate) { diag in
            DiagramPlateSheet(diagram: diag)
        }
        .task {
            await loadTerm(term)
        }
    }

    private func loadTerm(_ termToLoad: String) async {
        currentTerm = termToLoad
        isLoading = true
        word = await ConceptService.shared.fetchWord(for: termToLoad)
        isLoading = false
    }
}
