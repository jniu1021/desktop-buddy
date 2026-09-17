import Foundation
import XCTest
@testable import DesktopBuddy

@MainActor
final class LaunchRecoveryPolicyTests: XCTestCase {
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
}
