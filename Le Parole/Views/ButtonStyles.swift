import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme(.body, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isEnabled ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Color(.systemGray4)))
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlCornerRadius, style: .continuous)
                    .stroke(.white.opacity(isEnabled ? 0.16 : 0), lineWidth: 1)
            )
            .shadow(color: isEnabled ? Theme.primary.opacity(0.22) : .clear, radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = Theme.primary) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme(.body, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .themeCard(cornerRadius: Theme.controlCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
