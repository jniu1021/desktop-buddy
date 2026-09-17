import Foundation

enum FanControlPolicy {
    static func decide(
        _ command: FanControlCommand,
        for fan: FanReading,
        context: FanControlSafetyContext
    ) -> FanControlDecision {
        if command == .automatic { return .apply(.automatic) }

        guard context.helperAuthorized else {
            return .returnToAutomatic(.helperUnavailable)
        }
        guard context.hardwareControlVerified else {
            return .returnToAutomatic(.hardwareUnverified)
        }
        guard context.temperatureSampleFresh else {
            return .returnToAutomatic(.temperatureUnavailable)
        }
        guard fan.hasValidRange, let minimum = fan.minimumRPM,
              let maximum = fan.maximumRPM else {
            return .returnToAutomatic(.invalidFanRange)
        }
        guard let reference = context.recentAutomaticRPM,
              reference.isFinite, reference >= 0 else {
            return .returnToAutomatic(.firmwareReferenceUnavailable)
        }
        guard case let .manual(rpm) = command else {
            return .apply(.automatic)
        }

        // The hardware minimum is not a thermal safety floor. Manual control
        // may only raise speed above a recent firmware-controlled reference.
        if Double(rpm) < max(minimum, reference) {
            return .returnToAutomatic(.belowSafeFloor)
        }
        if Double(rpm) > maximum {
            return .returnToAutomatic(.aboveHardwareMaximum)
        }
        return .apply(.manual(rpm: rpm))
    }
}
