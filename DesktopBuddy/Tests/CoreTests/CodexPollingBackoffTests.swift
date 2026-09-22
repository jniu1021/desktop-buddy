import XCTest
@testable import DesktopBuddy

final class CodexPollingBackoffTests: XCTestCase {
    func testLifecycleRefreshesAtStartupAndAfterAnIndependentScreenWake() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertTrue(CodexRefreshPolicy.shouldRefresh(
            for: .startupOrResume,
            lastRefreshStartedAt: now,
            now: now
        ))
        XCTAssertTrue(CodexRefreshPolicy.shouldRefresh(
            for: .screenWake,
            lastRefreshStartedAt: now.addingTimeInterval(-6),
            now: now
        ))
    }

    func testScreenWakeCoalescesWithAJustStartedResumeRefresh() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(CodexRefreshPolicy.shouldRefresh(
            for: .screenWake,
            lastRefreshStartedAt: now.addingTimeInterval(-4.9),
            now: now
        ))
        XCTAssertTrue(CodexRefreshPolicy.shouldRefresh(
            for: .screenWake,
            lastRefreshStartedAt: now.addingTimeInterval(-5),
            now: now
        ))
        XCTAssertTrue(CodexRefreshPolicy.shouldRefresh(
            for: .manual,
            lastRefreshStartedAt: now,
            now: now
        ))
    }

    func testNetworkRecoveryCoalescesWithRecentLifecycleRefresh() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(CodexRefreshPolicy.shouldRefresh(
            for: .networkRecovery,
            lastRefreshStartedAt: now.addingTimeInterval(-4.9),
            now: now
        ))
        XCTAssertTrue(CodexRefreshPolicy.shouldRefresh(
            for: .networkRecovery,
            lastRefreshStartedAt: now.addingTimeInterval(-5),
            now: now
        ))
    }

    func testNetworkRecoveryRequiresUnavailableToAvailableTransition() {
        var detector = NetworkRecoveryDetector()

        XCTAssertFalse(detector.update(.available), "Initial connectivity is only a baseline")
        XCTAssertFalse(detector.update(.available), "Duplicate connectivity must not refresh")
        XCTAssertFalse(detector.update(.unavailable))
        XCTAssertFalse(detector.update(.unavailable))
        XCTAssertTrue(detector.update(.available))
        XCTAssertFalse(detector.update(.available))
    }

    func testRepeatedFailuresBackOffAndSuccessRestoresNormalCadence() {
        var backoff = CodexPollingBackoff()

        XCTAssertEqual(backoff.nextDelay(after: .available), .seconds(5 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(5 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(15 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .executableMissing), .seconds(30 * 60))
        XCTAssertEqual(backoff.nextDelay(after: .unavailable), .seconds(30 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 3)

        XCTAssertEqual(backoff.nextDelay(after: .available), .seconds(5 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 0)
    }

    func testLoadingDoesNotCountAsACompletedSuccessfulRead() {
        var backoff = CodexPollingBackoff()
        XCTAssertEqual(backoff.nextDelay(after: .loading), .seconds(5 * 60))
        XCTAssertEqual(backoff.consecutiveFailures, 1)
    }
}
