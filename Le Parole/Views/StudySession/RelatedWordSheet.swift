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
                        if let relatedItem, let rel = relatedItem.relationship, !rel.isEmpty {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: relatedItem.type.iconName)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(relatedItem.type.title.uppercased())
                                        .font(.system(size: 9.5, weight: .bold))
                                        .tracking(0.6)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(relatedItem.type.tintColor.opacity(0.15))
                                .foregroundStyle(relatedItem.type.tintColor)
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
                                    .stroke(relatedItem.type.tintColor.opacity(0.3), lineWidth: 1)
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

                                SpeakButton(text: currentTerm)
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
                            DiagramCard(diagram: diagram, imageMaxHeight: 220) { presentedPlate = $0 }
                        }

                        // Concept Deep Dive if available
                        if let concept = concept {
                            ConceptSectionView(concept: concept, onSelectRelatedTerm: { nextTerm in
                                // Nested chip tap: update current term
                                Task {
                                    await loadTerm(nextTerm)
                                }
                            })
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
        word = await Word.fetch(italian: termToLoad)
        isLoading = false
    }
}
