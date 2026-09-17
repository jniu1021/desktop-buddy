import Foundation

struct DevicePollingCadence: Equatable {
    let deviceRefreshDelay: Duration
    let memorySampleIntervalSeconds: Int
}

enum DevicePollingPolicy {
    static func cadence(
        powerSource: BatteryPowerSource,
        lowPowerModeEnabled: Bool
    ) -> DevicePollingCadence {
        if lowPowerModeEnabled {
            return DevicePollingCadence(
                deviceRefreshDelay: .seconds(120),
                memorySampleIntervalSeconds: 30
            )
        }

        switch powerSource {
        case .adapter:
            return DevicePollingCadence(
                deviceRefreshDelay: .seconds(60),
                memorySampleIntervalSeconds: 10
            )
        case .battery, .unknown:
            return DevicePollingCadence(
                deviceRefreshDelay: .seconds(90),
                memorySampleIntervalSeconds: 20
            )
        }
    }
}

struct MemorySamplingIntervalGate {
    private var appliedIntervalSeconds: Int?

    mutating func intervalToApply(_ requestedIntervalSeconds: Int) -> Int? {
        guard requestedIntervalSeconds != appliedIntervalSeconds else { return nil }
        appliedIntervalSeconds = requestedIntervalSeconds
        return requestedIntervalSeconds
    }
}
