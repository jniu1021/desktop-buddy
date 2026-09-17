import Foundation

enum StatusMetric: String, CaseIterable, Identifiable, Sendable {
    case battery
    case memoryUsage = "memoryPressure"
    case codexAllowance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .battery:
            return "Battery"
        case .memoryUsage:
            return "Memory"
        case .codexAllowance:
            return "Codex"
        }
    }
}
