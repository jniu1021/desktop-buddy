import Foundation

struct NoticeEvidence: Equatable, Sendable {
    let relevance: Double
    let confidence: Double

    init(relevance: Double, confidence: Double) {
        self.relevance = Self.normalized(relevance)
        self.confidence = Self.normalized(confidence)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

struct NoticeEligibilityContext: Equatable {
    let evidence: NoticeEvidence
    let isFocusSuppressed: Bool
    let isCategoryEnabled: Bool
    let wasConditionRecentlyHandled: Bool
    let lastOrdinaryNoticeAt: Date?
}

enum NoticeEligibilityResult: Equatable {
    case eligible
    case irrelevant
    case insufficientConfidence
    case focusSuppressed
    case categoryDisabled
    case recentlyHandled
    case modeCooldown
}

enum NoticeEligibility {
    static let minimumConfidence = 0.80

    static func evaluate(
        _ context: NoticeEligibilityContext,
        mode: InteractionMode,
        now: Date
    ) -> NoticeEligibilityResult {
        guard context.evidence.relevance >= mode.minimumNoticeRelevance else {
            return .irrelevant
        }
        guard context.evidence.confidence >= minimumConfidence else {
            return .insufficientConfidence
        }
        guard !context.isFocusSuppressed else { return .focusSuppressed }
        guard context.isCategoryEnabled else { return .categoryDisabled }
        guard !context.wasConditionRecentlyHandled else { return .recentlyHandled }

        if let lastNoticeAt = context.lastOrdinaryNoticeAt,
           now.timeIntervalSince(lastNoticeAt) < TimeInterval(mode.ordinaryCooldownMinutes * 60) {
            return .modeCooldown
        }

        return .eligible
    }
}

/// Owns the session-scoped cooldown used by the app coordinator.
/// A notice is recorded only after it is actually presented, not merely queued.
struct NoticeEligibilityCoordinator {
    private(set) var lastOrdinaryNoticeAt: Date?

    init(lastOrdinaryNoticeAt: Date? = nil) {
        self.lastOrdinaryNoticeAt = lastOrdinaryNoticeAt
    }

    func evaluate(
        mode: InteractionMode,
        now: Date,
        evidence: NoticeEvidence,
        isFocusSuppressed: Bool,
        isCategoryEnabled: Bool = true,
        wasConditionRecentlyHandled: Bool = false
    ) -> NoticeEligibilityResult {
        NoticeEligibility.evaluate(
            NoticeEligibilityContext(
                evidence: evidence,
                isFocusSuppressed: isFocusSuppressed,
                isCategoryEnabled: isCategoryEnabled,
                wasConditionRecentlyHandled: wasConditionRecentlyHandled,
                lastOrdinaryNoticeAt: lastOrdinaryNoticeAt
            ),
            mode: mode,
            now: now
        )
    }

    mutating func recordOrdinaryNoticeShown(at date: Date) {
        lastOrdinaryNoticeAt = date
    }
}
