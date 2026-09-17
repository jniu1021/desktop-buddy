enum InteractionMode: String, CaseIterable, Equatable, Sendable {
    case quiet
    case balanced
    case lively

    var displayName: String {
        rawValue.capitalized
    }

    var ordinaryCooldownMinutes: Int {
        switch self {
        case .quiet: return 60
        case .balanced: return 45
        case .lively: return 20
        }
    }

    var minimumNoticeRelevance: Double {
        switch self {
        case .quiet: return 0.85
        case .balanced: return 0.70
        case .lively: return 0.55
        }
    }
}
