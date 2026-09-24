import SwiftUI

/// Capsule badge showing a word's CEFR level or custom category.
struct LevelChip: View {
    let level: String
    var isLarge = false

    var body: some View {
        Text(level)
            .font(.theme(isLarge ? .subheadline : .caption, weight: .semibold))
            .padding(.horizontal, isLarge ? 12 : 6)
            .padding(.vertical, isLarge ? 6 : 2)
            .background(Theme.chipBackground)
            .clipShape(Capsule())
    }
}
