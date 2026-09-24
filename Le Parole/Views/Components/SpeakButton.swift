import SwiftUI

/// Round primary-colored button that pronounces Italian text.
struct SpeakButton: View {
    let text: String
    var size: CGFloat = 32
    var iconFont: Font = .theme(.caption, weight: .semibold)

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            SpeechService.shared.speak(text, languageCode: "it-IT")
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(iconFont)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.primary, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Pronounce \(text)")
    }
}
