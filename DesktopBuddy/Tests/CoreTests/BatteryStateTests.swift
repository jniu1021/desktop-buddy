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

    func testKeepsPositiveUsageEstimateOnlyWhileDischarging() {
        let state = BatteryStateNormalizer.makeState(
            currentCapacity: 60,
            maximumCapacity: 100,
            isCharging: false,
            isPresent: true,
            isOnACPower: false,
            estimatedUsageSeconds: 7_500
        )

        XCTAssertEqual(state.estimatedUsageSeconds, 7_500)
    }

    func testDropsUsageEstimateWhenConnectedToPowerOrInvalid() {
        let connected = BatteryStateNormalizer.makeState(
            currentCapacity: 60,
            maximumCapacity: 100,
            isCharging: false,
            isPresent: true,
            isOnACPower: true,
            estimatedUsageSeconds: 7_500
        )
        let unknown = BatteryStateNormalizer.makeState(
            currentCapacity: 60,
            maximumCapacity: 100,
            isCharging: false,
            isPresent: true,
            isOnACPower: false,
            estimatedUsageSeconds: -1
        )

        XCTAssertNil(connected.estimatedUsageSeconds)
        XCTAssertNil(unknown.estimatedUsageSeconds)
    }

    func testFormatsUsageEstimateForDisplayAndAccessibility() {
        XCTAssertEqual(BatteryUsageEstimateFormatter.displayString(seconds: 7_500), "2 hr 5 min")
        XCTAssertEqual(BatteryUsageEstimateFormatter.displayString(seconds: 3_600), "1 hr")
        XCTAssertEqual(BatteryUsageEstimateFormatter.displayString(seconds: 45), "1 min")
        XCTAssertNil(BatteryUsageEstimateFormatter.displayString(seconds: -1))

        XCTAssertEqual(
            BatteryUsageEstimateFormatter.accessibilityString(seconds: 7_500),
            "2 hours 5 minutes"
        )
    }
}
