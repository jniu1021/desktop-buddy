import Foundation

enum CodexRefreshTrigger: Equatable, Sendable {
    case startupOrResume
    case screenWake
    case networkRecovery
    case scheduled
    case manual
}

enum CodexRefreshPolicy {
    static let lifecycleCoalescingInterval: TimeInterval = 5

    static func shouldRefresh(
        for trigger: CodexRefreshTrigger,
        lastRefreshStartedAt: Date?,
        now: Date
    ) -> Bool {
        let shouldCoalesce = trigger == .screenWake || trigger == .networkRecovery
        guard shouldCoalesce, let lastRefreshStartedAt else { return true }
        return now.timeIntervalSince(lastRefreshStartedAt) >= lifecycleCoalescingInterval
    }
}

struct CodexPollingBackoff: Equatable, Sendable {
    private(set) var consecutiveFailures = 0

    mutating func nextDelay(after availability: CodexAllowanceAvailability) -> Duration {
        if availability == .available {
            consecutiveFailures = 0
        } else {
            consecutiveFailures = min(consecutiveFailures + 1, 3)
        }

        switch consecutiveFailures {
        case 0, 1: return .seconds(5 * 60)
        case 2: return .seconds(15 * 60)
        default: return .seconds(30 * 60)
        }
    }
}
