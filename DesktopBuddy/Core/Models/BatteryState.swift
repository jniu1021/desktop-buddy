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

    static let unavailable = BatteryState(
        chargePercent: nil,
        isCharging: false,
        powerSource: .unknown,
        condition: .unavailable
    )
}

enum BatteryStateNormalizer {
    static func makeState(
        currentCapacity: Int?,
        maximumCapacity: Int?,
        isCharging: Bool,
        isPresent: Bool,
        isOnACPower: Bool
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
            condition: condition
        )
    }
}
