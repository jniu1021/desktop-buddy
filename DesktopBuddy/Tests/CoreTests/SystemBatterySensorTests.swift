import XCTest
@testable import DesktopBuddy

final class SystemBatterySensorTests: XCTestCase {
    func testReadsBatteryFromCurrentMac() async throws {
        let state = await SystemBatterySensor().currentState()
        let percentage = try XCTUnwrap(state.chargePercent)

        XCTAssertTrue((0...100).contains(percentage))
        XCTAssertNotEqual(state.condition, .unavailable)
    }
}
