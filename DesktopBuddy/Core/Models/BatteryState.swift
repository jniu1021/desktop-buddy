import Foundation

enum BatteryCondition: String, Equatable, Sendable {
    case normal
    case low
    case critical
    case unavailable

    var severity: DeviceSeverity {
        switch self {
        case .normal:
            return .normal
        case .low:
            return .elevated
        case .critical:
            return .critical
        case .unavailable:
            return .unavailable
        }
    }
}

enum BatteryPowerSource: String, Equatable, Sendable {
    case battery
    case adapter
    case unknown
}

struct BatteryState: Equatable, Sendable {
    let chargePercent: Int?
    let isCharging: Bool
    let powerSource: BatteryPowerSource
    let condition: BatteryCondition
    let estimatedUsageSeconds: TimeInterval?

    init(
        chargePercent: Int?,
        isCharging: Bool,
        powerSource: BatteryPowerSource,
        condition: BatteryCondition,
        estimatedUsageSeconds: TimeInterval? = nil
    ) {
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.condition = condition
        self.estimatedUsageSeconds = estimatedUsageSeconds
    }

    static let unavailable = BatteryState(
        chargePercent: nil,
        isCharging: false,
        powerSource: .unknown,
        condition: .unavailable,
        estimatedUsageSeconds: nil
    )
}

enum BatteryUsageEstimateFormatter {
    static func displayString(seconds: TimeInterval) -> String? {
        guard let parts = durationParts(seconds: seconds) else { return nil }

        if parts.hours == 0 {
            return "\(parts.minutes) min"
        }
        if parts.minutes == 0 {
            return "\(parts.hours) hr"
        }
        return "\(parts.hours) hr \(parts.minutes) min"
    }

    static func accessibilityString(seconds: TimeInterval) -> String? {
        guard let parts = durationParts(seconds: seconds) else { return nil }
        let minuteText = "\(parts.minutes) " + (parts.minutes == 1 ? "minute" : "minutes")

        guard parts.hours > 0 else { return minuteText }

        let hourText = "\(parts.hours) " + (parts.hours == 1 ? "hour" : "hours")
        return parts.minutes == 0 ? hourText : "\(hourText) \(minuteText)"
    }

    private static func durationParts(seconds: TimeInterval) -> (hours: Int, minutes: Int)? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        return (totalMinutes / 60, totalMinutes % 60)
    }
}

enum BatteryStateNormalizer {
    static func makeState(
        currentCapacity: Int?,
        maximumCapacity: Int?,
        isCharging: Bool,
        isPresent: Bool,
        isOnACPower: Bool,
        estimatedUsageSeconds: TimeInterval? = nil
    ) -> BatteryState {
        guard
            isPresent,
            let currentCapacity,
            let maximumCapacity,
            maximumCapacity > 0
        else {
            return .unavailable
        }

        let percentage = min(100, max(0, Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded())))
        let condition: BatteryCondition

        switch percentage {
        case ...10:
            condition = .critical
        case ...20:
            condition = .low
        default:
            condition = .normal
        }

        return BatteryState(
            chargePercent: percentage,
            isCharging: isCharging,
            powerSource: isOnACPower ? .adapter : .battery,
            condition: condition,
            estimatedUsageSeconds: normalizedEstimate(
                estimatedUsageSeconds,
                isCharging: isCharging,
                isOnACPower: isOnACPower
            )
        )
    }

    private static func normalizedEstimate(
        _ seconds: TimeInterval?,
        isCharging: Bool,
        isOnACPower: Bool
    ) -> TimeInterval? {
        guard
            !isCharging,
            !isOnACPower,
            let seconds,
            seconds.isFinite,
            seconds > 0
        else {
            return nil
        }
        return seconds
    }
}
