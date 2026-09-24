import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var verticalPadding: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme(.body, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
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
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.primary
    var verticalPadding: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.theme(.body, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : tint.opacity(0.4))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .themeCard(cornerRadius: Theme.controlCornerRadius)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1.0 : 0.6))
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
