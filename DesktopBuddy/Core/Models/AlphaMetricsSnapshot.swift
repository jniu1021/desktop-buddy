import Foundation

struct AlphaMetricsSnapshot: Codable, Equatable, Sendable {
    var noticesShown = 0
    var noticesDismissed = 0
    var noticesActedOn = 0
    var batteryGlances = 0
    var memoryGlances = 0
    var codexGlances = 0
    var sessionsStarted = 0
    var completedSessionSeconds: TimeInterval = 0
    var lastCompletedSessionSeconds: TimeInterval = 0

    static let empty = AlphaMetricsSnapshot()

    func glances(for metric: StatusMetric) -> Int {
        switch metric {
        case .battery: batteryGlances
        case .memoryUsage: memoryGlances
        case .codexAllowance: codexGlances
        }
    }
}
