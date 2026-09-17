import Foundation

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
