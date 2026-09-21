import Foundation
import IOKit.ps

struct SystemBatterySensor: BatterySensing {
    func currentState() async -> BatteryState {
        guard let snapshot = Self.readSnapshot() else {
            return .unavailable
        }

        return BatteryStateNormalizer.makeState(
            currentCapacity: snapshot.currentCapacity,
            maximumCapacity: snapshot.maximumCapacity,
            isCharging: snapshot.isCharging,
            isPresent: snapshot.isPresent,
            isOnACPower: snapshot.isOnACPower,
            estimatedUsageSeconds: snapshot.estimatedUsageSeconds
        )
    }

    private static func readSnapshot() -> Snapshot? {
        let information = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(information).takeRetainedValue() as Array

        for source in sources {
            guard
                let rawDescription = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue(),
                let description = rawDescription as? [String: Any]
            else {
                continue
            }

            let isPresent = description[kIOPSIsPresentKey] as? Bool ?? true
            guard isPresent else { continue }

            return Snapshot(
                currentCapacity: description[kIOPSCurrentCapacityKey] as? Int,
                maximumCapacity: description[kIOPSMaxCapacityKey] as? Int,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPresent: isPresent,
                isOnACPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                estimatedUsageSeconds: IOPSGetTimeRemainingEstimate()
            )
        }

        return nil
    }

    private struct Snapshot {
        let currentCapacity: Int?
        let maximumCapacity: Int?
        let isCharging: Bool
        let isPresent: Bool
        let isOnACPower: Bool
        let estimatedUsageSeconds: TimeInterval
    }
}
