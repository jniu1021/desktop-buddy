import Foundation

enum DeviceNoticeKind: String, Equatable {
    case lowBattery
    case criticalBattery
    case highMemory

    var isOrdinary: Bool {
        self != .criticalBattery
    }
}

struct DeviceNotice: Identifiable, Equatable {
    let id: UUID
    let kind: DeviceNoticeKind
    let title: String
    let message: String
    let evidence: NoticeEvidence
    let createdAt: Date
    let expiresAt: Date

    init(
        kind: DeviceNoticeKind,
        title: String,
        message: String,
        evidence: NoticeEvidence,
        now: Date
    ) {
        self.id = UUID()
        self.kind = kind
        self.title = title
        self.message = message
        self.evidence = evidence
        self.createdAt = now
        self.expiresAt = now.addingTimeInterval(30 * 60)
    }
}

enum DeviceNoticeEvidence {
    static func lowBattery(chargePercent: Int) -> NoticeEvidence {
        let relevance = 1.00 - 0.02 * Double(chargePercent - 10)
        return NoticeEvidence(relevance: relevance, confidence: 1.00)
    }

    static func criticalBattery() -> NoticeEvidence {
        NoticeEvidence(relevance: 1.00, confidence: 1.00)
    }

    static func highMemory(usagePercent: Int) -> NoticeEvidence {
        let relevance = 0.70 + 0.02 * Double(usagePercent - 85)
        return NoticeEvidence(relevance: relevance, confidence: 0.90)
    }
}

struct DeviceNoticeDetector {
    private var previousBatteryKind: DeviceNoticeKind?
    private var wasMemoryHigh = false

    mutating func updateBattery(_ state: BatteryState, now: Date) -> DeviceNotice? {
        let kind: DeviceNoticeKind? = if state.powerSource == .battery && !state.isCharging {
            switch state.condition {
            case .low: .lowBattery
            case .critical: .criticalBattery
            case .normal, .unavailable: nil
            }
        } else {
            nil
        }
        defer { previousBatteryKind = kind }
        guard let kind, kind != previousBatteryKind, let percent = state.chargePercent else {
            return nil
        }
        switch kind {
        case .lowBattery:
            return DeviceNotice(
                kind: kind,
                title: "Battery is getting low",
                message: "Battery is at \(percent)%. Consider charging soon.",
                evidence: DeviceNoticeEvidence.lowBattery(chargePercent: percent),
                now: now
            )
        case .criticalBattery:
            return DeviceNotice(
                kind: kind,
                title: "Battery is very low",
                message: "Battery is at \(percent)%. Plug in when you can.",
                evidence: DeviceNoticeEvidence.criticalBattery(),
                now: now
            )
        case .highMemory:
            return nil
        }
    }

    mutating func updateMemory(
        _ state: MemoryUsageState,
        level: MemoryUsageLevel,
        now: Date
    ) -> DeviceNotice? {
        let isHigh = state.isAvailable && level == .high
        defer { wasMemoryHigh = isHigh }
        guard isHigh && !wasMemoryHigh else { return nil }
        return DeviceNotice(
            kind: .highMemory,
            title: "Memory use is high",
            message: "Memory use is at \(state.usagePercent)%. Check Memory details when convenient.",
            evidence: DeviceNoticeEvidence.highMemory(usagePercent: state.usagePercent),
            now: now
        )
    }
}

struct PendingNoticeQueue {
    private(set) var notices: [DeviceNotice] = []

    mutating func enqueue(_ notice: DeviceNotice, now: Date) -> Bool {
        expire(now: now)
        guard !notices.contains(where: { $0.kind == notice.kind }) else { return false }
        notices.insert(notice, at: 0)
        if notices.count > 3 { notices.removeLast(notices.count - 3) }
        return true
    }

    mutating func dismiss(id: UUID) {
        notices.removeAll(where: { $0.id == id })
    }

    mutating func expire(now: Date) {
        notices.removeAll(where: { $0.expiresAt <= now })
    }
}
