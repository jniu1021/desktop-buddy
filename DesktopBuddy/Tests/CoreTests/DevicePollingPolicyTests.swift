import XCTest
@testable import DesktopBuddy

final class DevicePollingPolicyTests: XCTestCase {
    func testCadenceUsesPowerSourceAndLowPowerMode() {
        XCTAssertEqual(
            DevicePollingPolicy.cadence(powerSource: .adapter, lowPowerModeEnabled: false),
            DevicePollingCadence(deviceRefreshDelay: .seconds(60), memorySampleIntervalSeconds: 10)
        )
        XCTAssertEqual(
            DevicePollingPolicy.cadence(powerSource: .battery, lowPowerModeEnabled: false),
            DevicePollingCadence(deviceRefreshDelay: .seconds(90), memorySampleIntervalSeconds: 20)
        )
        XCTAssertEqual(
            DevicePollingPolicy.cadence(powerSource: .unknown, lowPowerModeEnabled: false),
            DevicePollingCadence(deviceRefreshDelay: .seconds(90), memorySampleIntervalSeconds: 20)
        )
    }

    func testLowPowerModeHasPriorityForEveryPowerSource() {
        for powerSource in [BatteryPowerSource.adapter, .battery, .unknown] {
            XCTAssertEqual(
                DevicePollingPolicy.cadence(
                    powerSource: powerSource,
                    lowPowerModeEnabled: true
                ),
                DevicePollingCadence(
                    deviceRefreshDelay: .seconds(120),
                    memorySampleIntervalSeconds: 30
                )
            )
        }
    }

    func testMemoryIntervalGateOnlyAppliesChanges() {
        var gate = MemorySamplingIntervalGate()

        XCTAssertEqual(gate.intervalToApply(10), 10)
        XCTAssertNil(gate.intervalToApply(10))
        XCTAssertEqual(gate.intervalToApply(20), 20)
        XCTAssertNil(gate.intervalToApply(20))
    }
}
