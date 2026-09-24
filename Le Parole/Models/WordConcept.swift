import SwiftUI

public enum ConceptRelationshipType: String, Codable, Sendable {
    case opposite = "opposite"
    case counters = "counters"
    case component = "component"
    case maneuver = "maneuver"
    case wind = "wind"
    case warning = "warning"
    case related = "related"

    public var iconName: String {
        switch self {
        case .opposite: return "arrow.left.arrow.right"
        case .counters: return "shield.lefthalf.filled"
        case .component: return "puzzlepiece.fill"
        case .maneuver: return "steeringwheel"
        case .wind: return "wind"
        case .warning: return "exclamationmark.triangle.fill"
        case .related: return "link"
        }
    }

    public var title: String {
        switch self {
        case .opposite: return "Opposite"
        case .counters: return "Counters"
        case .component: return "Component"
        case .maneuver: return "Maneuver"
        case .wind: return "Wind Angle"
        case .warning: return "Warning"
        case .related: return "Related"
        }
    }

    public var tintColor: Color {
        switch self {
        case .opposite: return Color.orange
        case .counters: return Color.blue
        case .component: return Color.purple
        case .maneuver: return Theme.mastered
        case .wind: return Color.cyan
        case .warning: return Color.red
        case .related: return Theme.primary
        }
    }
}

public struct ConceptPhrase: Codable, Sendable, Identifiable, Equatable {
    public var id: String { phrase }
    public let phrase: String
    public let meaning: String
    public let context: String?
}

public struct RelatedConceptItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String { term.lowercased() }
    public let term: String
    public let relationship: String?
    public let type: ConceptRelationshipType
}

public struct WordConcept: Codable, Sendable, Identifiable, Equatable {
    public var id: String { italian.lowercased() }
    public let italian: String
    public let intuition: String
    public let practicalTip: String?
    public let commonPhrases: [ConceptPhrase]?
    public let relatedConcepts: [RelatedConceptItem]
}
