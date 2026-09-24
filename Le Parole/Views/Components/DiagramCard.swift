import SwiftUI

/// "Manuale CVC" card showing a sailing diagram crop; tapping opens the full plate.
struct DiagramCard: View {
    let diagram: WordDiagram
    var imageMaxHeight: CGFloat = 250
    let onOpen: (WordDiagram) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Manuale CVC", systemImage: "sailboat.fill")
                    .font(.theme(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                Spacer()

                Button(action: open) {
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

            Button(action: open) {
                Image(diagram.revealedImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: imageMaxHeight)
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
        .themeCard()
    }

    private func open() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onOpen(diagram)
    }
}
