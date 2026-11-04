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
