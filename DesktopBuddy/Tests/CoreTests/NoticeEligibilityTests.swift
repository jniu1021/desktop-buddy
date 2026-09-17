import XCTest
@testable import DesktopBuddy

final class NoticeEligibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testModesHaveApprovedCooldowns() {
        XCTAssertEqual(InteractionMode.quiet.ordinaryCooldownMinutes, 60)
        XCTAssertEqual(InteractionMode.balanced.ordinaryCooldownMinutes, 45)
        XCTAssertEqual(InteractionMode.lively.ordinaryCooldownMinutes, 20)
        XCTAssertEqual(InteractionMode.quiet.minimumNoticeRelevance, 0.85)
        XCTAssertEqual(InteractionMode.balanced.minimumNoticeRelevance, 0.70)
        XCTAssertEqual(InteractionMode.lively.minimumNoticeRelevance, 0.55)
        XCTAssertEqual(NoticeEligibility.minimumConfidence, 0.80)
    }

    func testRelevantEventIsEligibleWhenAllGatesPass() {
        XCTAssertEqual(NoticeEligibility.evaluate(context(), mode: .balanced, now: now), .eligible)
    }

    func testEverySuppressionGateBlocksAnOrdinaryNotice() {
        XCTAssertEqual(NoticeEligibility.evaluate(context(relevance: 0.69), mode: .balanced, now: now), .irrelevant)
        XCTAssertEqual(NoticeEligibility.evaluate(context(confidence: 0.79), mode: .balanced, now: now), .insufficientConfidence)
        XCTAssertEqual(NoticeEligibility.evaluate(context(isFocusSuppressed: true), mode: .balanced, now: now), .focusSuppressed)
        XCTAssertEqual(NoticeEligibility.evaluate(context(isCategoryEnabled: false), mode: .balanced, now: now), .categoryDisabled)
        XCTAssertEqual(NoticeEligibility.evaluate(context(wasConditionRecentlyHandled: true), mode: .balanced, now: now), .recentlyHandled)
    }

    func testNumericThresholdBoundariesAndModeDifferences() {
        let mediumRelevance = context(relevance: 0.70)
        XCTAssertEqual(NoticeEligibility.evaluate(mediumRelevance, mode: .quiet, now: now), .irrelevant)
        XCTAssertEqual(NoticeEligibility.evaluate(mediumRelevance, mode: .balanced, now: now), .eligible)
        XCTAssertEqual(NoticeEligibility.evaluate(mediumRelevance, mode: .lively, now: now), .eligible)

        XCTAssertEqual(
            NoticeEligibility.evaluate(context(confidence: 0.80), mode: .balanced, now: now),
            .eligible
        )
    }

    func testRealHighMemoryEvidencePassesBalancedButNotQuiet() {
        let evidence = DeviceNoticeEvidence.highMemory(usagePercent: 85)
        let quietCoordinator = NoticeEligibilityCoordinator()
        let balancedCoordinator = NoticeEligibilityCoordinator()

        XCTAssertEqual(
            quietCoordinator.evaluate(
                mode: .quiet,
                now: now,
                evidence: evidence,
                isFocusSuppressed: false
            ),
            .irrelevant
        )
        XCTAssertEqual(
            balancedCoordinator.evaluate(
                mode: .balanced,
                now: now,
                evidence: evidence,
                isFocusSuppressed: false
            ),
            .eligible
        )
    }

    func testEvidenceNormalizesInvalidAndOutOfRangeInputs() {
        XCTAssertEqual(NoticeEvidence(relevance: -1, confidence: 2), NoticeEvidence(relevance: 0, confidence: 1))
        XCTAssertEqual(NoticeEvidence(relevance: .nan, confidence: .infinity), NoticeEvidence(relevance: 0, confidence: 0))
    }

    func testModeCooldownUsesLastActualNoticeAndBoundaryIsEligible() {
        let lastNoticeAt = now.addingTimeInterval(-30 * 60)
        XCTAssertEqual(NoticeEligibility.evaluate(context(lastOrdinaryNoticeAt: lastNoticeAt), mode: .quiet, now: now), .modeCooldown)
        XCTAssertEqual(NoticeEligibility.evaluate(context(lastOrdinaryNoticeAt: lastNoticeAt), mode: .balanced, now: now), .modeCooldown)
        XCTAssertEqual(NoticeEligibility.evaluate(context(lastOrdinaryNoticeAt: lastNoticeAt), mode: .lively, now: now), .eligible)
        XCTAssertEqual(NoticeEligibility.evaluate(context(lastOrdinaryNoticeAt: now.addingTimeInterval(-45 * 60)), mode: .balanced, now: now), .eligible)
    }

    func testCoordinatorMakesModesDifferForTheSameEventStream() {
        let eventTimes = [0, 25, 50].map { now.addingTimeInterval(TimeInterval($0 * 60)) }

        XCTAssertEqual(shownEventCount(mode: .quiet, eventTimes: eventTimes), 1)
        XCTAssertEqual(shownEventCount(mode: .balanced, eventTimes: eventTimes), 2)
        XCTAssertEqual(shownEventCount(mode: .lively, eventTimes: eventTimes), 3)
    }

    func testCoordinatorRecordsOnlyAnActuallyShownOrdinaryNotice() {
        var coordinator = NoticeEligibilityCoordinator()

        XCTAssertEqual(
            coordinator.evaluate(
                mode: .balanced,
                now: now,
                evidence: NoticeEvidence(relevance: 1, confidence: 1),
                isFocusSuppressed: true
            ),
            .focusSuppressed
        )
        XCTAssertNil(coordinator.lastOrdinaryNoticeAt)

        coordinator.recordOrdinaryNoticeShown(at: now)
        XCTAssertEqual(coordinator.lastOrdinaryNoticeAt, now)
    }

    private func shownEventCount(mode: InteractionMode, eventTimes: [Date]) -> Int {
        var coordinator = NoticeEligibilityCoordinator()
        var shown = 0
        for eventTime in eventTimes {
            if coordinator.evaluate(
                mode: mode,
                now: eventTime,
                evidence: NoticeEvidence(relevance: 1, confidence: 1),
                isFocusSuppressed: false
            ) == .eligible {
                shown += 1
                coordinator.recordOrdinaryNoticeShown(at: eventTime)
            }
        }
        return shown
    }

    private func context(
        relevance: Double = 1,
        confidence: Double = 1,
        isFocusSuppressed: Bool = false,
        isCategoryEnabled: Bool = true,
        wasConditionRecentlyHandled: Bool = false,
        lastOrdinaryNoticeAt: Date? = nil
    ) -> NoticeEligibilityContext {
        NoticeEligibilityContext(
            evidence: NoticeEvidence(relevance: relevance, confidence: confidence),
            isFocusSuppressed: isFocusSuppressed,
            isCategoryEnabled: isCategoryEnabled,
            wasConditionRecentlyHandled: wasConditionRecentlyHandled,
            lastOrdinaryNoticeAt: lastOrdinaryNoticeAt
        )
    }
}
