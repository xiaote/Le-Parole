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

    public init(phrase: String, meaning: String, context: String? = nil) {
        self.phrase = phrase
        self.meaning = meaning
        self.context = context
    }
}

public struct RelatedConceptItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String { term.lowercased() }
    public let term: String
    public let relationship: String?
    public let type: ConceptRelationshipType?
    public let imageName: String?

    public var effectiveType: ConceptRelationshipType {
        if let type { return type }
        return Self.inferType(term: term, relationship: relationship)
    }

    public var cleanRelationship: String? {
        guard let rel = relationship else { return nil }
        var cleaned = rel
        let prefixesToStrip = [
            "Direct structural opposite — ",
            "Direct structural opposite - ",
            "Direct opposite side — ",
            "Direct opposite side - ",
            "Direct opposite — ",
            "Direct opposite - ",
            "Opposite action — ",
            "Opposite action - ",
            "Opposite maneuver — ",
            "Opposite maneuver - ",
            "Opposite turn — ",
            "Opposite turn - ",
            "Opposite steering — ",
            "Opposite steering - ",
            "Opposite command — ",
            "Opposite command - ",
            "Opposite extreme — ",
            "Opposite extreme - ",
            "Opposite — ",
            "Opposite - ",
            "Contrast — ",
            "Contrast - ",
            "Counter-action — ",
            "Counter-action - "
        ]
        for p in prefixesToStrip {
            if cleaned.hasPrefix(p) {
                cleaned = String(cleaned.dropFirst(p.count))
                if let first = cleaned.first {
                    cleaned = first.uppercased() + cleaned.dropFirst()
                }
                break
            }
        }
        return cleaned
    }

    private static func inferType(term: String, relationship: String?) -> ConceptRelationshipType {
        guard let rel = relationship?.lowercased() else { return .related }
        if rel.contains("opposite") || rel.contains("contrast") || rel.contains("counterpart") {
            return .opposite
        }
        if rel.contains("counter") || rel.contains("resist") || rel.contains("balance") || rel.contains("righting") {
            return .counters
        }
        if rel.contains("flutter") || rel.contains("warning") || rel.contains("danger") || rel.contains("capsize") {
            return .warning
        }
        if rel.contains("housing") || rel.contains("cleat") || rel.contains("bollard") || rel.contains("spar") || rel.contains("tiller") || rel.contains("transom") {
            return .component
        }
        if rel.contains("wind") || rel.contains("point of sail") || rel.contains("reach") || rel.contains("beat") || rel.contains("run") || rel.contains("dead zone") || rel.contains("no-go") {
            return .wind
        }
        if rel.contains("turn") || rel.contains("maneuver") || rel.contains("tack") || rel.contains("gybe") || rel.contains("heaving") || rel.contains("coiling") || rel.contains("steering") {
            return .maneuver
        }
        return .related
    }

    public init(
        term: String,
        relationship: String? = nil,
        type: ConceptRelationshipType? = nil,
        imageName: String? = nil
    ) {
        self.term = term
        self.relationship = relationship
        self.type = type
        self.imageName = imageName
    }
}

public struct WordConcept: Codable, Sendable, Identifiable, Equatable {
    public var id: String { italian.lowercased() }
    public let italian: String
    public let category: String?
    public let intuition: String
    public let practicalTip: String?
    public let commonPhrases: [ConceptPhrase]?
    public let relatedTerms: [String]?
    public let relatedConcepts: [RelatedConceptItem]?

    public var effectiveRelatedConcepts: [RelatedConceptItem] {
        if let relatedConcepts, !relatedConcepts.isEmpty {
            return relatedConcepts
        }
        if let relatedTerms {
            return relatedTerms.map { RelatedConceptItem(term: $0) }
        }
        return []
    }

    public init(
        italian: String,
        category: String? = nil,
        intuition: String,
        practicalTip: String? = nil,
        commonPhrases: [ConceptPhrase]? = nil,
        relatedTerms: [String]? = nil,
        relatedConcepts: [RelatedConceptItem]? = nil
    ) {
        self.italian = italian
        self.category = category
        self.intuition = intuition
        self.practicalTip = practicalTip
        self.commonPhrases = commonPhrases
        self.relatedTerms = relatedTerms
        self.relatedConcepts = relatedConcepts
    }
}
