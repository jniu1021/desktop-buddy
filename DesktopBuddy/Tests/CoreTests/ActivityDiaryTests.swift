import XCTest
@testable import DesktopBuddy

final class ActivityDiaryTests: XCTestCase {
    func testSleepGapIsNotCounted() {
        var ledger = ActivityDiaryLedger()
        ledger.append(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 3600), activity: "unknown", source: "metadata")
        XCTAssertTrue(ledger.intervals.isEmpty)
    }

    func testCorrectionOnlyLabelsLastTenSeconds() {
        var ledger = ActivityDiaryLedger()
        for t in stride(from: 0, to: 120, by: 10) {
            ledger.append(start: Date(timeIntervalSince1970: Double(t)), end: Date(timeIntervalSince1970: Double(t + 10)), activity: "unknown", source: "metadata")
        }
        ledger.labelLastInterval(.reading)
        XCTAssertEqual(ledger.intervals.count, 2)
        XCTAssertEqual(ledger.intervals[0].seconds, 110)
        XCTAssertEqual(ledger.intervals[1].seconds, 10)
        XCTAssertEqual(ledger.intervals[1].source, "self_report")
        XCTAssertEqual(ledger.intervals.reduce(0) { $0 + $1.seconds }, 120)
    }

    func testDailyTotalsSplitMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 86400)
        var ledger = ActivityDiaryLedger()
        ledger.append(start: midnight.addingTimeInterval(-5), end: midnight.addingTimeInterval(5), activity: "unknown", source: "metadata")
        XCTAssertEqual(ledger.totals(on: midnight, calendar: calendar)["unknown"], 5)
        XCTAssertEqual(ledger.totals(on: midnight.addingTimeInterval(-1), calendar: calendar)["unknown"], 5)
    }

    func testRepeatedCorrectionDoesNotDuplicateTime() {
        var ledger = ActivityDiaryLedger()
        ledger.append(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10), activity: "unknown", source: "metadata")
        ledger.labelLastInterval(.coding)
        ledger.labelLastInterval(.video)
        XCTAssertEqual(ledger.intervals.count, 1)
        XCTAssertEqual(ledger.intervals.first?.activity, "video")
        XCTAssertEqual(ledger.intervals.first?.seconds, 10)
    }
}

final class ScreenActivityRulesTests: XCTestCase {
    func testSingleGenericWordIsNotCoding() {
        XCTAssertEqual(ScreenActivityRules.infer(lines: ["import settings"]).0, "unknown")
    }
    func testMultipleCodeCuesAreTentativeCoding() {
        XCTAssertEqual(ScreenActivityRules.infer(lines: ["import Foundation", "func example() {"]).0, "coding")
    }
    func testConflictingActivityCuesRemainUnknown() {
        let result = ScreenActivityRules.infer(lines: ["func test()", "import Foundation", "unmute", "participants"])
        XCTAssertEqual(result.0, "unknown")
        XCTAssertEqual(result.1, "conflicting_screen_cues")
    }
    func testEmptyScreenRemainsUnknown() {
        XCTAssertEqual(ScreenActivityRules.infer(lines: []).0, "unknown")
    }
}

final class AudioCueRulesTests: XCTestCase {
    func testLowOrInvalidScoreRemainsUnknown() {
        XCTAssertEqual(AudioCueRules.coarse("speech", score: 0.2), "unknown")
        XCTAssertEqual(AudioCueRules.coarse("music", score: .nan), "unknown")
    }
    func testSpeechIsNotMeeting() {
        XCTAssertEqual(AudioCueRules.coarse("speech", score: 0.9), "speech")
        XCTAssertEqual(AudioCueRules.coarse("conversation", score: 0.8), "speech")
    }
    func testMusicIsNotVideo() {
        XCTAssertEqual(AudioCueRules.coarse("background_music", score: 0.8), "music")
    }
    func testOtherSoundsDoNotEstablishAbsence() {
        XCTAssertEqual(AudioCueRules.coarse("silence", score: 0.95), "other_sound")
    }
}

final class ActivityFusionAndFeedbackTests: XCTestCase {
    func testFrozenCorrectionDoesNotMoveToNewestInterval() {
        var ledger = ActivityDiaryLedger()
        for t in stride(from: 0, to: 40, by: 10) {
            ledger.append(start: Date(timeIntervalSince1970: Double(t)), end: Date(timeIntervalSince1970: Double(t + 10)), activity: "unknown", source: "metadata")
        }
        XCTAssertTrue(ledger.label(endingAt: Date(timeIntervalSince1970: 20), activity: .reading))
        XCTAssertEqual(ledger.intervals.last?.activity, "unknown")
        XCTAssertEqual(ledger.intervals.first(where: { $0.activity == "reading" })?.end, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(ledger.intervals.reduce(0) { $0 + $1.seconds }, 40)
    }
    func testSpeechAloneDoesNotEstablishMeeting() {
        XCTAssertEqual(ActivityEvidenceFusion.predict(screen: nil, screenAge: nil, audio: "speech", audioAge: 0, sameApp: true), "unknown")
    }
    func testMeetingRequiresFreshCorroboration() {
        XCTAssertEqual(ActivityEvidenceFusion.predict(screen: "meeting", screenAge: 2, audio: "speech", audioAge: 4, sameApp: true), "meeting")
        XCTAssertEqual(ActivityEvidenceFusion.predict(screen: "meeting", screenAge: 2, audio: "speech", audioAge: 100, sameApp: true), "unknown")
    }
    func testStaleOrDifferentAppScreenIsDiscarded() {
        XCTAssertEqual(ActivityEvidenceFusion.predict(screen: "coding", screenAge: 46, audio: nil, audioAge: nil, sameApp: true), "unknown")
        XCTAssertEqual(ActivityEvidenceFusion.predict(screen: "coding", screenAge: 2, audio: nil, audioAge: nil, sameApp: false), "unknown")
    }
}

private final class DiaryCountingSensor: ForegroundActivitySensing {
    var calls = 0
    func currentSnapshot() -> ForegroundActivitySnapshot {
        calls += 1
        return ForegroundActivitySnapshot(bundleIdentifier: nil, secondsSinceLastInput: nil)
    }
}

final class DiaryLifecycleTests: XCTestCase {
    @MainActor
    func testOptInSuspendResumeAndDisableGateSampling() {
        let suite = "diary-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sensor = DiaryCountingSensor()
        let store = ActivityDiaryStore(sensor: sensor, defaults: defaults)
        defer { store.stop() }
        store.sample()
        XCTAssertEqual(sensor.calls, 0)
        store.setEnabled(true)
        XCTAssertEqual(sensor.calls, 1)
        store.setSuspended(true)
        store.sample()
        XCTAssertEqual(sensor.calls, 1)
        store.setSuspended(false)
        XCTAssertEqual(sensor.calls, 2)
        store.setEnabled(false)
        store.sample()
        XCTAssertEqual(sensor.calls, 2)
        XCTAssertNil(store.review)
    }

    @MainActor
    func testClearRemovesBothLocalDataStores() throws {
        let suite = "diary-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([DiaryReview(end: Date(), prediction: "unknown", audioCue: "unknown", answer: "reading")]), forKey: "activityDiary.feedback.v1")
        let store = ActivityDiaryStore(sensor: DiaryCountingSensor(), defaults: defaults)
        XCTAssertEqual(store.feedbackCount, 1)
        store.clear()
        XCTAssertEqual(store.feedbackCount, 0)
        XCTAssertNil(defaults.data(forKey: "activityDiary.feedback.v1"))
        XCTAssertNil(defaults.data(forKey: "activityDiary.intervals.v1"))
    }
}

final class DiaryRetentionTests: XCTestCase {
    func testLongMergedIntervalIsTrimmedAtRetentionBoundary() {
        let end = Date(timeIntervalSince1970: 10 * 86400)
        var ledger = ActivityDiaryLedger(intervals: [DiaryInterval(start: Date(timeIntervalSince1970: 0), end: end.addingTimeInterval(-10), activity: "unknown", source: "metadata")])
        ledger.append(start: end.addingTimeInterval(-10), end: end, activity: "unknown", source: "metadata")
        XCTAssertEqual(ledger.intervals.count, 1)
        XCTAssertEqual(ledger.intervals[0].seconds, 7 * 86400)
    }
}
