import XCTest
import Combine
@testable import DesktopBuddy

final class DeviceNoticeEngineTests: XCTestCase {
    func testStatusPanelTimeLabelsDoNotRequireALiveTimeline() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            StatusPanelTimeLabel.noticeExpiry(
                expiresAt: now.addingTimeInterval(29 * 60 + 1),
                now: now
            ),
            "Expires in 30 min"
        )
        XCTAssertEqual(
            StatusPanelTimeLabel.noticeExpiry(expiresAt: now, now: now),
            "Expires in 1 min"
        )
        XCTAssertEqual(
            StatusPanelTimeLabel.lastUpdated(at: now.addingTimeInterval(-59), now: now),
            "Updated just now"
        )
        XCTAssertEqual(
            StatusPanelTimeLabel.lastUpdated(at: now.addingTimeInterval(-125), now: now),
            "Updated 2 min ago"
        )
        XCTAssertEqual(
            StatusPanelTimeLabel.lastUpdated(at: now.addingTimeInterval(-7_200), now: now),
            "Updated 2 hr ago"
        )
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testBatteryNoticeOnlyOnUnpluggedEntryAndCriticalEscalation() {
        var detector = DeviceNoticeDetector()
        XCTAssertNil(detector.updateBattery(battery(20, charging: true), now: now))
        XCTAssertEqual(detector.updateBattery(battery(20), now: now)?.kind, .lowBattery)
        XCTAssertNil(detector.updateBattery(battery(18), now: now))
        XCTAssertEqual(detector.updateBattery(battery(10), now: now)?.kind, .criticalBattery)
        XCTAssertNil(detector.updateBattery(battery(9), now: now))
        XCTAssertNil(detector.updateBattery(battery(9, charging: true), now: now))
        XCTAssertEqual(detector.updateBattery(battery(9), now: now)?.kind, .criticalBattery)
    }

    func testMemoryNoticeOnlyOnHighEntry() {
        var detector = DeviceNoticeDetector()
        let state = memory(0.87)
        XCTAssertNil(detector.updateMemory(state, level: .elevated, now: now))
        XCTAssertEqual(detector.updateMemory(state, level: .high, now: now)?.kind, .highMemory)
        XCTAssertNil(detector.updateMemory(state, level: .high, now: now))
        XCTAssertNil(detector.updateMemory(state, level: .normal, now: now))
        XCTAssertEqual(detector.updateMemory(state, level: .high, now: now)?.kind, .highMemory)
    }

    func testOnlyCriticalBatteryBypassesOrdinaryMessageCooldown() {
        XCTAssertTrue(DeviceNoticeKind.lowBattery.isOrdinary)
        XCTAssertTrue(DeviceNoticeKind.highMemory.isOrdinary)
        XCTAssertFalse(DeviceNoticeKind.criticalBattery.isOrdinary)
    }

    func testDeviceEvidenceUsesApprovedNumericDefinitions() throws {
        var batteryDetector = DeviceNoticeDetector()
        let lowAtTwenty = try XCTUnwrap(batteryDetector.updateBattery(battery(20), now: now))
        XCTAssertEqual(lowAtTwenty.evidence.relevance, 0.80, accuracy: 0.0001)
        XCTAssertEqual(lowAtTwenty.evidence.confidence, 1.00, accuracy: 0.0001)

        var lowerBatteryDetector = DeviceNoticeDetector()
        let lowAtEleven = try XCTUnwrap(lowerBatteryDetector.updateBattery(battery(11), now: now))
        XCTAssertEqual(lowAtEleven.evidence.relevance, 0.98, accuracy: 0.0001)

        var memoryDetector = DeviceNoticeDetector()
        let memoryAtEightyFive = try XCTUnwrap(
            memoryDetector.updateMemory(memory(0.85), level: .high, now: now)
        )
        XCTAssertEqual(memoryAtEightyFive.evidence.relevance, 0.70, accuracy: 0.0001)
        XCTAssertEqual(memoryAtEightyFive.evidence.confidence, 0.90, accuracy: 0.0001)

        var higherMemoryDetector = DeviceNoticeDetector()
        let memoryAtNinetyFive = try XCTUnwrap(
            higherMemoryDetector.updateMemory(memory(0.95), level: .high, now: now)
        )
        XCTAssertEqual(memoryAtNinetyFive.evidence.relevance, 0.90, accuracy: 0.0001)
    }

    func testQueueMergesKindsCapsAtThreeAndExpires() {
        var queue = PendingNoticeQueue()
        let low = notice(.lowBattery)
        XCTAssertTrue(queue.enqueue(low, now: now))
        XCTAssertFalse(queue.enqueue(notice(.lowBattery), now: now))
        XCTAssertEqual(queue.notices.count, 1)
        XCTAssertTrue(queue.enqueue(notice(.criticalBattery), now: now))
        XCTAssertTrue(queue.enqueue(notice(.highMemory), now: now))
        XCTAssertEqual(queue.notices.count, 3)
        queue.dismiss(id: low.id)
        XCTAssertEqual(queue.notices.count, 2)
        queue.expire(now: now.addingTimeInterval(30 * 60))
        XCTAssertTrue(queue.notices.isEmpty)
    }

    @MainActor
    func testStoreSchedulesDefaultThirtyMinuteExpiryWithoutPanelInteraction() async {
        let clock = AdvancingNoticeClock(now: now)
        let store = PendingNoticeStore(
            now: { clock.currentDate() },
            sleep: { seconds in try await clock.sleep(seconds: seconds) }
        )
        let expired = expectation(description: "Notice expires automatically")
        var sawNotice = false
        let subscription = store.$notices.sink { notices in
            if notices.isEmpty, sawNotice {
                expired.fulfill()
            } else if !notices.isEmpty {
                sawNotice = true
            }
        }

        XCTAssertTrue(store.enqueue(notice(.lowBattery)))
        await fulfillment(of: [expired], timeout: 1)

        XCTAssertTrue(store.notices.isEmpty)
        XCTAssertEqual(clock.requestedDelays(), [30 * 60])
        withExtendedLifetime(subscription) {}
    }

    private func battery(_ percent: Int, charging: Bool = false) -> BatteryState {
        BatteryState(
            chargePercent: percent,
            isCharging: charging,
            powerSource: charging ? .adapter : .battery,
            condition: percent <= 10 ? .critical : .low
        )
    }

    private func memory(_ fraction: Double) -> MemoryUsageState {
        MemoryUsageState(
            usedBytes: UInt64((fraction * 1000).rounded()),
            totalBytes: 1000,
            compressedBytes: 0,
            swapUsedBytes: 0,
            swapOutBytesPerSecond: 0,
            systemPressure: .normal
        )
    }

    private func notice(_ kind: DeviceNoticeKind) -> DeviceNotice {
        DeviceNotice(
            kind: kind,
            title: "Test",
            message: "Test",
            evidence: NoticeEvidence(relevance: 1, confidence: 1),
            now: now
        )
    }
}

private final class AdvancingNoticeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    private var delays: [TimeInterval] = []

    init(now: Date) {
        date = now
    }

    func currentDate() -> Date {
        lock.withLock { date }
    }

    func requestedDelays() -> [TimeInterval] {
        lock.withLock { delays }
    }

    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        lock.withLock {
            delays.append(seconds)
            date = date.addingTimeInterval(seconds)
        }
        await Task.yield()
        try Task.checkCancellation()
    }
}
