import XCTest
@testable import DesktopBuddy

final class BatteryStateTests: XCTestCase {
    func testNormalizesCapacityToPercentage() {
        let state = BatteryStateNormalizer.makeState(
            currentCapacity: 42,
            maximumCapacity: 80,
            isCharging: false,
            isPresent: true,
            isOnACPower: false
        )

        XCTAssertEqual(state.chargePercent, 53)
        XCTAssertEqual(state.condition, .normal)
        XCTAssertEqual(state.powerSource, .battery)
    }

    func testCriticalThresholdIncludesTenPercent() {
        let state = BatteryStateNormalizer.makeState(
            currentCapacity: 10,
            maximumCapacity: 100,
            isCharging: false,
            isPresent: true,
            isOnACPower: false
        )

        XCTAssertEqual(state.condition, .critical)
    }

    func testLowThresholdIncludesTwentyPercent() {
        let state = BatteryStateNormalizer.makeState(
            currentCapacity: 20,
            maximumCapacity: 100,
            isCharging: false,
            isPresent: true,
            isOnACPower: false
        )

        XCTAssertEqual(state.condition, .low)
    }

    func testMissingBatteryIsUnavailable() {
        let state = BatteryStateNormalizer.makeState(
            currentCapacity: nil,
            maximumCapacity: nil,
            isCharging: false,
            isPresent: false,
            isOnACPower: true
        )

        XCTAssertEqual(state, .unavailable)
    }
}
