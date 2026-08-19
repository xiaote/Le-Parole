import SwiftUI
import UIKit

enum Theme {
    // MARK: - Semantic colors

    /// Safe for white text and for text/icons on the active system surfaces.
    static let primary = adaptiveColor(
        light: UIColor(red: 0.03, green: 0.49, blue: 0.29, alpha: 1),
        dark: UIColor(red: 0.05, green: 0.526, blue: 0.34, alpha: 1)
    )

    /// Decorative accents for gradients and non-semantic artwork only.
    static let primaryLight = Color(red: 0.40, green: 0.85, blue: 0.60)
    static let primaryDark = Color(red: 0.0, green: 0.25, blue: 0.15)
    static let playfulAccent = adaptiveColor(
        light: UIColor(red: 0.86, green: 0.36, blue: 0.22, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.55, blue: 0.37, alpha: 1)
    )

    /// Stage colors adapt to the surrounding appearance so they remain legible
    /// when used for text, symbols, and chart marks.
    static let recognition = adaptiveColor(
        light: UIColor(red: 0.09, green: 0.39, blue: 0.24, alpha: 1),
        dark: UIColor(red: 0.46, green: 0.88, blue: 0.64, alpha: 1)
    )
    static let production = primary
    static let mastered = adaptiveColor(
        light: UIColor(red: 0.0, green: 0.25, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.57, green: 0.91, blue: 0.69, alpha: 1)
    )

    /// Data visualizations use a darker mastered segment so the learning
    /// progression reads from light recognition to deep mastery.
    static let masteredBar = adaptiveColor(
        light: UIColor(red: 0.0, green: 0.25, blue: 0.15, alpha: 1),
        dark: UIColor(red: 0.0, green: 0.33, blue: 0.20, alpha: 1)
    )

    // MARK: - Surfaces

    static let canvas = adaptiveColor(
        light: UIColor(red: 0.95, green: 0.98, blue: 0.96, alpha: 1),
        dark: UIColor(red: 0.035, green: 0.06, blue: 0.045, alpha: 1)
    )
    static let background = Color(.systemBackground)
    static let surface = adaptiveColor(
        light: UIColor(red: 0.995, green: 0.999, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.075, green: 0.10, blue: 0.085, alpha: 1)
    )
    static let inputBackground = adaptiveColor(
        light: UIColor(red: 0.91, green: 0.95, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.12, green: 0.16, blue: 0.135, alpha: 1)
    )
    static let chipBackground = adaptiveColor(
        light: UIColor(red: 0.88, green: 0.93, blue: 0.89, alpha: 1),
        dark: UIColor(red: 0.15, green: 0.20, blue: 0.17, alpha: 1)
    )
    static let border = adaptiveColor(
        light: UIColor(red: 0.08, green: 0.20, blue: 0.12, alpha: 0.12),
        dark: UIColor(red: 0.77, green: 0.92, blue: 0.82, alpha: 0.16)
    )
    static let cardShadow = adaptiveColor(
        light: UIColor(red: 0.02, green: 0.12, blue: 0.07, alpha: 0.08),
        dark: UIColor.black.withAlphaComponent(0.22)
    )

    // MARK: - Layout tokens

    static let smallCornerRadius: CGFloat = 10
    static let barCornerRadius: CGFloat = 4
    static let controlCornerRadius: CGFloat = 14
    static let cardCornerRadius: CGFloat = 18
    static let prominentCardCornerRadius: CGFloat = 24
    static let studyCardCornerRadius: CGFloat = 28

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func font(for style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default).weight(weight)
    }

    /// The only serif role: the word or phrase being learned.
    static let wordDisplay = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let wordPrompt = Font.system(.title2, design: .serif).weight(.bold)
    static let wordList = Font.system(.body, design: .serif).weight(.semibold)

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Font {
    static func theme(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Theme.font(for: style, weight: weight)
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = Theme.cardCornerRadius, elevated: Bool = false) -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: elevated ? Theme.cardShadow : .clear, radius: elevated ? 14 : 0, y: elevated ? 7 : 0)
    }
}
