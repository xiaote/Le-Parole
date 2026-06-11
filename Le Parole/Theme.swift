import SwiftUI

struct Theme {
    // Primary Emerald Green Accent
    static let primary = Color(red: 0.05, green: 0.55, blue: 0.35)
    static let primaryLight = Color(red: 0.40, green: 0.85, blue: 0.60) // Minty / brighter
    static let primaryDark = Color(red: 0.0, green: 0.25, blue: 0.15) // Deep forest green
    
    // Backgrounds
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let tertiaryBackground = Color(.tertiarySystemBackground)
    
    // Typography with rounded design
    static func font(for style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        return .system(style, design: .rounded).weight(weight)
    }
}

extension Font {
    static func theme(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        return Theme.font(for: style, weight: weight)
    }
}
