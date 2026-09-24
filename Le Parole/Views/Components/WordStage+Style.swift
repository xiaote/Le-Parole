import SwiftUI

extension WordStage {
    var title: String {
        switch self {
        case .new:         "Not started"
        case .skipped:     "Skipped"
        case .recognition: "Recognition"
        case .production:  "Production"
        case .mastered:    "Mastered"
        }
    }

    var iconName: String {
        switch self {
        case .new:         "circle"
        case .skipped:     "slash.circle"
        case .recognition: "eye"
        case .production:  "pencil"
        case .mastered:    "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .new:         Color(.systemGray3)
        case .skipped:     Color(.systemGray)
        case .recognition: Theme.recognition
        case .production:  Theme.production
        case .mastered:    Theme.mastered
        }
    }
}
