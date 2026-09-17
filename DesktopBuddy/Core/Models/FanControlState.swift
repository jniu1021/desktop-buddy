import Foundation

enum FanControlMode: Equatable, Sendable {
    case automatic
    case manual
    case system
    case unknown
}

struct FanReading: Equatable, Sendable {
    let index: Int
    let currentRPM: Double?
    let minimumRPM: Double?
    let maximumRPM: Double?
    let targetRPM: Double?
    let mode: FanControlMode

    var hasValidRange: Bool {
        guard let minimumRPM, let maximumRPM else { return false }
        return minimumRPM.isFinite && maximumRPM.isFinite
            && minimumRPM > 0 && maximumRPM > minimumRPM
    }
}

enum FanReadoutAvailability: Equatable, Sendable {
    case unavailable
    case fanless
    case available
}

struct FanReadoutState: Equatable, Sendable {
    let availability: FanReadoutAvailability
    let fans: [FanReading]
    let observedAt: Date?

    static let unavailable = FanReadoutState(
        availability: .unavailable, fans: [], observedAt: nil
    )
}

enum FanControlCommand: Equatable, Sendable {
    case automatic
    case manual(rpm: Int)
}

enum FanControlBlockReason: Equatable, Sendable {
    case helperUnavailable
    case hardwareUnverified
    case temperatureUnavailable
    case firmwareReferenceUnavailable
    case invalidFanRange
    case belowSafeFloor
    case aboveHardwareMaximum
}

enum FanControlDecision: Equatable, Sendable {
    case apply(FanControlCommand)
    case returnToAutomatic(FanControlBlockReason)
}

struct FanControlSafetyContext: Equatable, Sendable {
    let helperAuthorized: Bool
    let hardwareControlVerified: Bool
    let temperatureSampleFresh: Bool
    let recentAutomaticRPM: Double?
}
