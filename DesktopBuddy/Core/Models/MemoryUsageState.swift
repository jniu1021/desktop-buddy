import Foundation

enum SystemMemoryPressure: String, Equatable, Sendable {
    case normal
    case elevated
    case high

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }
}

enum MemoryUsageLevel: String, Equatable, Sendable {
    case normal
    case elevated
    case high

    var severity: DeviceSeverity {
        switch self {
        case .normal: return .normal
        case .elevated: return .elevated
        case .high: return .critical
        }
    }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }
}

struct MemoryUsageState: Equatable, Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let compressedBytes: UInt64
    let swapUsedBytes: UInt64
    let swapOutBytesPerSecond: UInt64
    let systemPressure: SystemMemoryPressure

    static let unavailable = MemoryUsageState(
        usedBytes: 0,
        totalBytes: 0,
        compressedBytes: 0,
        swapUsedBytes: 0,
        swapOutBytesPerSecond: 0,
        systemPressure: .normal
    )

    var usageFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    var usagePercent: Int {
        Int((usageFraction * 100).rounded())
    }

    var isAvailable: Bool {
        totalBytes > 0
    }
}

struct MemoryUsageLevelClassifier: Sendable {
    private(set) var displayedLevel: MemoryUsageLevel?
    private var escalationCandidate: MemoryUsageLevel?
    private var escalationCount = 0
    private var recoveryStartedAt: Date?

    mutating func update(usageFraction: Double, now: Date) -> MemoryUsageLevel {
        let measuredLevel = Self.measuredLevel(for: usageFraction)

        guard let displayedLevel else {
            self.displayedLevel = measuredLevel
            return measuredLevel
        }

        if measuredLevel.rank > displayedLevel.rank {
            recoveryStartedAt = nil

            if escalationCandidate == measuredLevel {
                escalationCount += 1
            } else {
                escalationCandidate = measuredLevel
                escalationCount = 1
            }

            if escalationCount >= 2 {
                self.displayedLevel = measuredLevel
                resetPendingTransition()
                return measuredLevel
            }

            return displayedLevel
        }

        escalationCandidate = nil
        escalationCount = 0

        guard shouldBeginRecovery(from: displayedLevel, usageFraction: usageFraction) else {
            recoveryStartedAt = nil
            return displayedLevel
        }

        if let recoveryStartedAt, now.timeIntervalSince(recoveryStartedAt) >= 60 {
            self.displayedLevel = measuredLevel
            self.recoveryStartedAt = nil
            return measuredLevel
        }

        recoveryStartedAt = recoveryStartedAt ?? now
        return displayedLevel
    }

    private static func measuredLevel(for usageFraction: Double) -> MemoryUsageLevel {
        switch usageFraction {
        case 0.85...: return .high
        case 0.70...: return .elevated
        default: return .normal
        }
    }

    private func shouldBeginRecovery(
        from displayedLevel: MemoryUsageLevel,
        usageFraction: Double
    ) -> Bool {
        switch displayedLevel {
        case .high: return usageFraction < 0.80
        case .elevated: return usageFraction < 0.65
        case .normal: return false
        }
    }

    private mutating func resetPendingTransition() {
        escalationCandidate = nil
        escalationCount = 0
        recoveryStartedAt = nil
    }
}

private extension MemoryUsageLevel {
    var rank: Int {
        switch self {
        case .normal: return 0
        case .elevated: return 1
        case .high: return 2
        }
    }
}
