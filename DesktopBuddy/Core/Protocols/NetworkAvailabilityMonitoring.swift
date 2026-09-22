import Foundation

enum NetworkAvailability: Equatable, Sendable {
    case unavailable
    case available
}

protocol NetworkAvailabilityMonitoring: Sendable {
    func availabilityUpdates() -> AsyncStream<NetworkAvailability>
}

struct NetworkRecoveryDetector: Equatable, Sendable {
    private(set) var previousAvailability: NetworkAvailability?

    mutating func update(_ availability: NetworkAvailability) -> Bool {
        defer { previousAvailability = availability }
        return previousAvailability == .unavailable && availability == .available
    }
}
