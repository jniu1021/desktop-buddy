import Foundation
import XCTest
@testable import DesktopBuddy

@MainActor
final class LaunchRecoveryPolicyTests: XCTestCase {
    func testApplicationCoordinatorDoesNotStartInsideXCTestHost() {
        XCTAssertTrue(ApplicationLaunchPolicy.shouldStartCoordinator(environment: [:]))
        XCTAssertFalse(ApplicationLaunchPolicy.shouldStartCoordinator(environment: [
            "XCTestConfigurationFilePath": "/tmp/DesktopBuddy.xctestconfiguration"
        ]))
        XCTAssertFalse(ApplicationLaunchPolicy.shouldStartCoordinator(environment: [
            "XCTestBundlePath": "/tmp/DesktopBuddyTests.xctest"
        ]))
    }

    func testFirstLaunchAndCleanRestartRestoreNormally() {
        XCTAssertEqual(
            LaunchRecoveryPolicy.action(previousSessionWasActive: false),
            .restoreNormally
        )
    }

    func testUncleanExitStartsWithEdgePetHidden() {
        XCTAssertEqual(
            LaunchRecoveryPolicy.action(previousSessionWasActive: true),
            .startWithEdgePetHidden
        )
        XCTAssertFalse(EdgePetVisibilityPolicy.shouldBeVisible(
            wantsVisible: true,
            isFullscreenSuppressed: false,
            isFocusSuppressed: false,
            hasManualOverride: false,
            automaticRestoreSuppressed: true
        ))
    }

    func testLifecycleMarkerPersistsStartAndCleanStop() {
        let suiteName = "LaunchRecoveryPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let repository = UserDefaultsSessionLifecycleRepository(defaults: defaults)

        XCTAssertFalse(repository.isSessionActive)
        repository.isSessionActive = true
        XCTAssertTrue(UserDefaultsSessionLifecycleRepository(defaults: defaults).isSessionActive)
        repository.isSessionActive = false
        XCTAssertFalse(UserDefaultsSessionLifecycleRepository(defaults: defaults).isSessionActive)
    }

    func testRuntimeLifecycleSuspendsAndResumesOnlyOnStateChanges() {
        let suspended = RuntimeLifecyclePolicy.transition(
            from: .active,
            event: .systemWillSleep
        )
        XCTAssertEqual(suspended, RuntimeLifecycleTransition(state: .suspended, action: .suspend))

        XCTAssertEqual(
            RuntimeLifecyclePolicy.transition(
                from: suspended.state,
                event: .systemWillSleep
            ),
            RuntimeLifecycleTransition(state: .suspended, action: nil)
        )

        let resumed = RuntimeLifecyclePolicy.transition(
            from: suspended.state,
            event: .systemDidWake
        )
        XCTAssertEqual(resumed, RuntimeLifecycleTransition(state: .active, action: .resume))

        XCTAssertEqual(
            RuntimeLifecyclePolicy.transition(
                from: resumed.state,
                event: .systemDidWake
            ),
            RuntimeLifecycleTransition(state: .active, action: nil)
        )
    }
}
