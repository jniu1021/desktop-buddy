import XCTest
@testable import DesktopBuddy

final class FanControlPolicyTests: XCTestCase {
    private let fan = FanReading(
        index: 0,
        currentRPM: 1500,
        minimumRPM: 1350,
        maximumRPM: 5349,
        targetRPM: 1500,
        mode: .automatic
    )

    private let ready = FanControlSafetyContext(
        helperAuthorized: true,
        hardwareControlVerified: true,
        temperatureSampleFresh: true,
        recentAutomaticRPM: 1500
    )

    func testAutomaticIsAlwaysAvailable() {
        let unavailable = FanControlSafetyContext(
            helperAuthorized: false,
            hardwareControlVerified: false,
            temperatureSampleFresh: false,
            recentAutomaticRPM: nil
        )
        XCTAssertEqual(FanControlPolicy.decide(.automatic, for: fan, context: unavailable),
                       .apply(.automatic))
    }

    func testManualCannotRunWithoutHelperVerificationAndFreshTemperature() {
        var context = FanControlSafetyContext(
            helperAuthorized: false,
            hardwareControlVerified: true,
            temperatureSampleFresh: true,
            recentAutomaticRPM: 1500
        )
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 2000), for: fan, context: context),
                       .returnToAutomatic(.helperUnavailable))

        context = FanControlSafetyContext(
            helperAuthorized: true,
            hardwareControlVerified: false,
            temperatureSampleFresh: true,
            recentAutomaticRPM: 1500
        )
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 2000), for: fan, context: context),
                       .returnToAutomatic(.hardwareUnverified))

        context = FanControlSafetyContext(
            helperAuthorized: true,
            hardwareControlVerified: true,
            temperatureSampleFresh: false,
            recentAutomaticRPM: 1500
        )
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 2000), for: fan, context: context),
                       .returnToAutomatic(.temperatureUnavailable))
    }

    func testManualOnlyRaisesSpeedWithinHardwareRange() {
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 1499), for: fan, context: ready),
                       .returnToAutomatic(.belowSafeFloor))
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 1500), for: fan, context: ready),
                       .apply(.manual(rpm: 1500)))
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 5350), for: fan, context: ready),
                       .returnToAutomatic(.aboveHardwareMaximum))
    }

    func testUnknownRangeOrFirmwareReferenceFallsBackToAutomatic() {
        let unknown = FanReading(index: 1, currentRPM: nil, minimumRPM: nil,
                                 maximumRPM: nil, targetRPM: nil, mode: .unknown)
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 2000), for: unknown, context: ready),
                       .returnToAutomatic(.invalidFanRange))

        let missingReference = FanControlSafetyContext(
            helperAuthorized: true,
            hardwareControlVerified: true,
            temperatureSampleFresh: true,
            recentAutomaticRPM: nil
        )
        XCTAssertEqual(FanControlPolicy.decide(.manual(rpm: 2000), for: fan,
                                               context: missingReference),
                       .returnToAutomatic(.firmwareReferenceUnavailable))
    }
}
