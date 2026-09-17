import Foundation
import XCTest
@testable import DesktopBuddy

@MainActor
final class AlphaMetricsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testLocalMetricsRecordOnlyExplicitAlphaCounters() {
        let repository = InMemoryAlphaMetricsRepository()
        let tracker = AlphaMetricsTracker(repository: repository)
        let shownID = UUID()
        let suppressedID = UUID()

        tracker.startSession(at: start)
        tracker.recordNoticeShown(id: shownID)
        tracker.recordActionForPendingNotices(ids: [shownID, suppressedID])
        tracker.recordActionForPendingNotices(ids: [shownID])
        tracker.recordNoticeDismissed(id: suppressedID)
        tracker.recordMetricGlance(.battery)
        tracker.recordMetricGlance(.memoryUsage)
        tracker.recordMetricGlance(.memoryUsage)
        tracker.stopSession(at: start.addingTimeInterval(125))

        let snapshot = tracker.snapshot
        XCTAssertEqual(snapshot.noticesShown, 1)
        XCTAssertEqual(snapshot.noticesActedOn, 1)
        XCTAssertEqual(snapshot.noticesDismissed, 1)
        XCTAssertEqual(snapshot.glances(for: .battery), 1)
        XCTAssertEqual(snapshot.glances(for: .memoryUsage), 2)
        XCTAssertEqual(snapshot.glances(for: .codexAllowance), 0)
        XCTAssertEqual(snapshot.sessionsStarted, 1)
        XCTAssertEqual(snapshot.completedSessionSeconds, 125)
        XCTAssertEqual(repository.load(), snapshot)
    }

    func testCurrentSessionContributesToReadableTotalAndClearIsLocal() {
        let repository = InMemoryAlphaMetricsRepository()
        let tracker = AlphaMetricsTracker(repository: repository)
        tracker.startSession(at: start)

        XCTAssertEqual(
            tracker.totalSessionSeconds(at: start.addingTimeInterval(90)),
            90
        )

        tracker.clear(at: start.addingTimeInterval(90))
        XCTAssertEqual(tracker.snapshot.noticesShown, 0)
        XCTAssertEqual(tracker.snapshot.sessionsStarted, 1)
        XCTAssertEqual(repository.clearCount, 1)
        XCTAssertEqual(
            tracker.totalSessionSeconds(at: start.addingTimeInterval(120)),
            30
        )
    }

    func testUserDefaultsRepositoryPersistsAndClears() throws {
        let suiteName = "AlphaMetricsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = UserDefaultsAlphaMetricsRepository(defaults: defaults)
        var snapshot = AlphaMetricsSnapshot.empty
        snapshot.noticesShown = 3
        snapshot.completedSessionSeconds = 42

        repository.save(snapshot)

        XCTAssertEqual(
            UserDefaultsAlphaMetricsRepository(defaults: defaults).load(),
            snapshot
        )

        repository.clear()
        XCTAssertEqual(repository.load(), .empty)
    }
}

@MainActor
private final class InMemoryAlphaMetricsRepository: AlphaMetricsPersisting {
    private var value: AlphaMetricsSnapshot = .empty
    private(set) var clearCount = 0

    func load() -> AlphaMetricsSnapshot { value }
    func save(_ snapshot: AlphaMetricsSnapshot) { value = snapshot }
    func clear() {
        clearCount += 1
        value = .empty
    }
}
