import Foundation
import XCTest
@testable import DesktopBuddy

final class MemoryUsageStateTests: XCTestCase {
    func testCalculatesUsagePercentage() {
        let state = makeState(used: 85, total: 100)

        XCTAssertEqual(state.usagePercent, 85)
    }

    func testInitialSampleUsesCurrentLevelImmediately() {
        var classifier = MemoryUsageLevelClassifier()

        let level = classifier.update(usageFraction: 0.85, now: Date())

        XCTAssertEqual(level, .high)
    }

    func testEscalationRequiresTwoConsecutiveSamples() {
        var classifier = MemoryUsageLevelClassifier()
        let start = Date()
        _ = classifier.update(usageFraction: 0.50, now: start)

        XCTAssertEqual(
            classifier.update(usageFraction: 0.75, now: start.addingTimeInterval(10)),
            .normal
        )
        XCTAssertEqual(
            classifier.update(usageFraction: 0.75, now: start.addingTimeInterval(20)),
            .elevated
        )
    }

    func testHighLevelNeedsSixtySecondsBelowRecoveryThreshold() {
        var classifier = MemoryUsageLevelClassifier()
        let start = Date()
        _ = classifier.update(usageFraction: 0.90, now: start)

        XCTAssertEqual(
            classifier.update(usageFraction: 0.75, now: start.addingTimeInterval(10)),
            .high
        )
        XCTAssertEqual(
            classifier.update(usageFraction: 0.75, now: start.addingTimeInterval(69)),
            .high
        )
        XCTAssertEqual(
            classifier.update(usageFraction: 0.75, now: start.addingTimeInterval(70)),
            .elevated
        )
    }

    private func makeState(used: UInt64, total: UInt64) -> MemoryUsageState {
        MemoryUsageState(
            usedBytes: used,
            totalBytes: total,
            compressedBytes: 0,
            swapUsedBytes: 0,
            swapOutBytesPerSecond: 0,
            systemPressure: .normal
        )
    }
}
