import Foundation
import XCTest
@testable import DesktopBuddy

@MainActor
final class UserDefaultsPreferencesStoreTests: XCTestCase {
    func testDefaultsToBattery() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.selectedMetric, .battery)
    }

    func testPersistsSelectedMetric() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        store.selectedMetric = .memoryUsage

        XCTAssertEqual(defaults.string(forKey: "selectedStatusMetric"), "memoryPressure")
    }

    func testWelcomeGuideOnlyAppearsForNewInstallAndCanBeReplayed() {
        let freshDefaults = makeDefaults()
        let fresh = UserDefaultsPreferencesStore(defaults: freshDefaults)
        XCTAssertFalse(fresh.onboardingCompleted)

        fresh.onboardingCompleted = true
        XCTAssertTrue(UserDefaultsPreferencesStore(defaults: freshDefaults).onboardingCompleted)
        fresh.onboardingCompleted = false
        XCTAssertFalse(UserDefaultsPreferencesStore(defaults: freshDefaults).onboardingCompleted)

        let existingDefaults = makeDefaults()
        existingDefaults.set("memoryPressure", forKey: "selectedStatusMetric")
        let existing = UserDefaultsPreferencesStore(defaults: existingDefaults)
        XCTAssertTrue(existing.onboardingCompleted)
        existing.onboardingCompleted = false
        XCTAssertFalse(UserDefaultsPreferencesStore(defaults: existingDefaults).onboardingCompleted)
    }

    func testAnimationDefaultsToEnabled() {
        let store = UserDefaultsPreferencesStore(defaults: makeDefaults())

        XCTAssertTrue(store.animationsEnabled)
    }

    func testInteractionModeDefaultsAndPersists() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.interactionMode, .balanced)
        store.interactionMode = .quiet
        XCTAssertEqual(defaults.string(forKey: "interactionMode"), "quiet")
    }

    func testFocusSuppressionDefaultsOnAndPersists() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertTrue(store.focusSuppressionEnabled)
        store.focusSuppressionEnabled = false
        XCTAssertFalse(UserDefaultsPreferencesStore(defaults: defaults).focusSuppressionEnabled)
    }

    func testApplicationActivityRequiresExplicitOptIn() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertFalse(store.applicationActivityEnabled)
        store.applicationActivityEnabled = true
        XCTAssertTrue(UserDefaultsPreferencesStore(defaults: defaults).applicationActivityEnabled)
        store.applicationActivityEnabled = false
        XCTAssertFalse(UserDefaultsPreferencesStore(defaults: defaults).applicationActivityEnabled)
    }

    func testCodexIntegrationRequiresOptIn() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertFalse(store.codexIntegrationEnabled)
        store.codexIntegrationEnabled = true
        XCTAssertTrue(UserDefaultsPreferencesStore(defaults: defaults).codexIntegrationEnabled)
    }

    func testPersistsAnimationPreference() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        store.animationsEnabled = false

        XCTAssertFalse(defaults.bool(forKey: "animationsEnabled"))
    }

    func testDesktopPetAppearanceDefaultsAndPersistence() {
        let defaults = makeDefaults()
        let store = UserDefaultsPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.edgePetScale, 1)
        XCTAssertFalse(store.edgePetVisible)
        XCTAssertEqual(store.edgePetEdge, .right)
        XCTAssertEqual(store.edgePetEdgePosition, 0.08)

        store.edgePetScale = 1.25
        store.edgePetVisible = true
        store.edgePetEdge = .top
        store.edgePetEdgePosition = 0.6

        XCTAssertEqual(defaults.double(forKey: "edgePetScale"), 1.25)
        XCTAssertTrue(UserDefaultsPreferencesStore(defaults: defaults).edgePetVisible)
        XCTAssertEqual(defaults.string(forKey: "edgePetEdge"), "top")
        XCTAssertEqual(defaults.double(forKey: "edgePetEdgePosition"), 0.6)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DesktopBuddyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
