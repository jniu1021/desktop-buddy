import CoreGraphics
import XCTest
@testable import DesktopBuddy

final class SystemForegroundActivitySensorTests: XCTestCase {
    func testMissingAllInputEventTypeReturnsUnavailableWithoutSampling() {
        var didReadSeconds = false

        let seconds = ForegroundIdleTimeReader.secondsSinceLastInput(
            makeAnyInputEventType: { nil },
            readSeconds: { _ in
                didReadSeconds = true
                return 12
            }
        )

        XCTAssertNil(seconds)
        XCTAssertFalse(didReadSeconds)
    }

    func testIdleSecondsKeepsFiniteValuesAndRejectsInvalidValues() throws {
        let eventType = try XCTUnwrap(CGEventType(rawValue: UInt32.max))

        XCTAssertEqual(ForegroundIdleTimeReader.secondsSinceLastInput(
            makeAnyInputEventType: { eventType },
            readSeconds: { _ in 12.5 }
        ), 12.5)
        XCTAssertNil(ForegroundIdleTimeReader.secondsSinceLastInput(
            makeAnyInputEventType: { eventType },
            readSeconds: { _ in .infinity }
        ))
        XCTAssertNil(ForegroundIdleTimeReader.secondsSinceLastInput(
            makeAnyInputEventType: { eventType },
            readSeconds: { _ in .nan }
        ))
    }
}
