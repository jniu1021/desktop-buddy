import Foundation

enum CodexAllowanceAvailability: Equatable, Sendable {
    case notConfigured
    case loading
    case available
    case executableMissing
    case unavailable
}

enum CodexAllowanceCondition: Equatable, Sendable {
    case normal
    case low
    case exhausted
    case unavailable

    var severity: DeviceSeverity {
        switch self {
        case .normal: .normal
        case .low: .caution
        case .exhausted: .critical
        case .unavailable: .unavailable
        }
    }
}

struct CodexQuotaWindow: Equatable, Sendable {
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        Int((100 - min(max(usedPercent, 0), 100)).rounded())
    }

    var label: String {
        switch durationMinutes {
        case 300: "5-hour"
        case 10_080: "Weekly"
        case let minutes?: "\(minutes)-minute"
        case nil: "Current"
        }
    }
}

struct CodexAllowanceState: Equatable, Sendable {
    let availability: CodexAllowanceAvailability
    let primary: CodexQuotaWindow?
    let secondary: CodexQuotaWindow?
    let updatedAt: Date?

    static let notConfigured = CodexAllowanceState(
        availability: .notConfigured,
        primary: nil,
        secondary: nil,
        updatedAt: nil
    )

    static let loading = CodexAllowanceState(
        availability: .loading,
        primary: nil,
        secondary: nil,
        updatedAt: nil
    )

    static func unavailable(_ reason: CodexAllowanceAvailability) -> CodexAllowanceState {
        CodexAllowanceState(availability: reason, primary: nil, secondary: nil, updatedAt: nil)
    }

    var condition: CodexAllowanceCondition {
        guard availability == .available, let primary else { return .unavailable }
        // The selected pet color follows the primary (5-hour) window only.
        // Use the unrounded value so the strict boundaries remain exact.
        let remaining = 100 - min(max(primary.usedPercent, 0), 100)
        if remaining < 15 { return .exhausted }
        if remaining < 40 { return .low }
        return .normal
    }
}
