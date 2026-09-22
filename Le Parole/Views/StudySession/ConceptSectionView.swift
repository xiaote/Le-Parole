import SwiftUI

struct ConceptSectionView: View {
    let concept: WordConcept
    var onSelectRelatedItem: ((RelatedConceptItem) -> Void)? = nil
    var onSelectRelatedTerm: ((String) -> Void)? = nil

    init(
        concept: WordConcept,
        onSelectRelatedItem: ((RelatedConceptItem) -> Void)? = nil,
        onSelectRelatedTerm: ((String) -> Void)? = nil
    ) {
        self.concept = concept
        self.onSelectRelatedItem = onSelectRelatedItem
        self.onSelectRelatedTerm = onSelectRelatedTerm
    }

    init(concept: WordConcept, onSelectRelatedTerm: ((String) -> Void)?) {
        self.concept = concept
        self.onSelectRelatedItem = nil
        self.onSelectRelatedTerm = onSelectRelatedTerm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - The Concept
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text("THE CONCEPT")
                        .font(.theme(.caption, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .tracking(0.8)
                }

                Text(concept.intuition)
                    .font(.theme(.subheadline))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            )

            // MARK: - Real-World Commands & In the Wild
            if let phrases = concept.commonPhrases, !phrases.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.playfulAccent)
                        Text("COMMANDS & IN THE WILD")
                            .font(.theme(.caption, weight: .bold))
                            .foregroundStyle(Theme.playfulAccent)
                            .tracking(0.8)
                    }

                    VStack(spacing: 8) {
                        ForEach(phrases) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    SpeechService.shared.speak(item.phrase, languageCode: "it-IT")
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.primary, in: Circle())
                                        .contentShape(Circle())
                                }
                                .buttonStyle(PressableButtonStyle())
                                .accessibilityLabel("Pronounce \(item.phrase)")

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.phrase)
                                        .font(.theme(.subheadline, weight: .bold))
                                        .foregroundStyle(.primary)

                                    Text(item.meaning)
                                        .font(.theme(.caption))
                                        .foregroundStyle(.secondary)

                                    if let context = item.context {
                                        Text(context)
                                            .font(.system(size: 11, weight: .regular))
                                            .italic()
                                            .foregroundStyle(Color.secondary.opacity(0.8))
                                            .padding(.top, 1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)

                            if item.id != phrases.last?.id {
                                Divider().background(Theme.border.opacity(0.5))
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                )
            }

            // MARK: - In Practice / Rule of Thumb
            if let tip = concept.practicalTip {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "compass.drawing")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.mastered)
                        Text("IN PRACTICE")
                            .font(.theme(.caption, weight: .bold))
                            .foregroundStyle(Theme.mastered)
                            .tracking(0.8)
                    }

                    Text(tip)
                        .font(.theme(.subheadline))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                        .allowsHitTesting(false)
                )
            }

            // MARK: - Connected Concept Clusters
            let related = concept.effectiveRelatedConcepts
            if !related.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("CONNECTED CONCEPTS")
                            .font(.theme(.caption2, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(related) { item in
                                ConnectedConceptPill(item: item) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    if let onSelectRelatedItem {
                                        onSelectRelatedItem(item)
                                    } else {
                                        onSelectRelatedTerm?(item.term)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

private struct ConnectedConceptPill: View {
    let item: RelatedConceptItem
    let action: () -> Void

    private var diagram: WordDiagram? {
        SailingDiagramService.diagram(for: item.term)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let diagram {
                    Image(diagram.revealedImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                .allowsHitTesting(false)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.term)
                            .font(.theme(.subheadline, weight: .bold))
                            .foregroundStyle(.primary)

                        // Distinct Relationship Type Icon Badge
                        HStack(spacing: 3) {
                            Image(systemName: item.effectiveType.iconName)
                                .font(.system(size: 9, weight: .bold))
                            Text(item.effectiveType.title.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.effectiveType.tintColor.opacity(0.14))
                        .foregroundStyle(item.effectiveType.tintColor)
                        .clipShape(Capsule())
                    }

                    if let rel = item.cleanRelationship, !rel.isEmpty {
                        Text(rel)
                            .font(.theme(.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(Theme.chipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
    }
}
