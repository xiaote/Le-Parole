import SwiftUI

typealias VisualQuizData = (target: WordDiagram, options: [WordDiagram])

struct VisualChoiceGridView: View {
    let quiz: VisualQuizData
    let selectedOptionId: String?
    let isRevealed: Bool
    let interactionLocked: Bool
    let onSelect: (WordDiagram, WordDiagram) -> Void
    let onZoom: (WordDiagram) -> Void

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(quiz.options) { option in
                VisualOptionTile(
                    option: option,
                    isSelected: selectedOptionId == option.id,
                    isTarget: option.id == quiz.target.id,
                    showFeedback: isRevealed || selectedOptionId != nil,
                    isDisabled: interactionLocked || isRevealed,
                    onZoom: {
                        onZoom(option)
                    }
                ) {
                    onSelect(option, quiz.target)
                }
            }
        }
        .padding(.horizontal, 20)
        .layoutPriority(1)
    }
}

struct VisualOptionTile: View {
    let option: WordDiagram
    let isSelected: Bool
    let isTarget: Bool
    let showFeedback: Bool
    let isDisabled: Bool
    let onZoom: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    Image(option.promptImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 175)
                        .padding(6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 185)
                .background(Color.white)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)

                // Magnifying zoom button in top-left
                VStack {
                    HStack {
                        Button {
                            onZoom()
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.primary)
                                .padding(7)
                                .background(Color.white.opacity(0.92), in: Circle())
                                .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                        Spacer()
                    }
                    Spacer()
                }

                if showFeedback {
                    if isTarget {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.green)
                            .background(Circle().fill(Color.white))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.red)
                            .background(Circle().fill(Color.white))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .compositingGroup()
        .scaleEffect(isSelected ? 0.98 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showFeedback)
    }

    private var borderColor: Color {
        if showFeedback {
            if isTarget {
                return Color.green
            } else if isSelected {
                return Color.red
            }
        }
        return Theme.border
    }

    private var borderWidth: CGFloat {
        if showFeedback && (isTarget || isSelected) {
            return 2.5
        }
        return 1.0
    }
}
