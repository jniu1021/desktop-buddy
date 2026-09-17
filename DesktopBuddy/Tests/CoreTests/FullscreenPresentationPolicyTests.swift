import XCTest
@testable import DesktopBuddy

final class FullscreenPresentationPolicyTests: XCTestCase {
    func testFullscreenFallbackPollingUsesSlowCadence() {
        XCTAssertEqual(FullscreenPollingPolicy.refreshInterval, .seconds(15))
    }

    func testWindowMustFillDisplayRatherThanOnlyVisibleWorkArea() {
        let display = DisplayGeometry(x: 0, y: 0, width: 1728, height: 1117)
        XCTAssertTrue(FullscreenPresentationPolicy.windowFillsDisplay(display, display: display))
        XCTAssertFalse(FullscreenPresentationPolicy.windowFillsDisplay(
            DisplayGeometry(x: 0, y: 33, width: 1728, height: 1013),
            display: display
        ))
    }

    func testDifferentDisplayOriginsAndSmallRoundingTolerance() {
        let display = DisplayGeometry(x: 1728, y: -120, width: 1440, height: 900)
        XCTAssertTrue(FullscreenPresentationPolicy.windowFillsDisplay(
            DisplayGeometry(x: 1729, y: -119, width: 1439, height: 899),
            display: display
        ))
        XCTAssertFalse(FullscreenPresentationPolicy.windowFillsDisplay(
            DisplayGeometry(x: 0, y: 0, width: 1440, height: 900),
            display: display
        ))
    }

    func testFullscreenWindowOnAnotherDisplayDoesNotSuppressTargetDisplay() {
        let petDisplay = DisplayGeometry(x: 0, y: 0, width: 1728, height: 1117)
        let otherDisplay = DisplayGeometry(x: 1728, y: -120, width: 1440, height: 900)

        XCTAssertFalse(FullscreenPresentationPolicy.containsFullscreenWindow(
            [otherDisplay],
            on: petDisplay
        ))
        XCTAssertTrue(FullscreenPresentationPolicy.containsFullscreenWindow(
            [otherDisplay, petDisplay],
            on: petDisplay
        ))
    }

    func testFullScreenOrFocusedStateSuppressesProactiveBubble() {
        XCTAssertTrue(FullscreenPresentationPolicy.shouldShowBubble(isFullscreen: false, isFocused: false))
        XCTAssertFalse(FullscreenPresentationPolicy.shouldShowBubble(isFullscreen: true, isFocused: false))
        XCTAssertFalse(FullscreenPresentationPolicy.shouldShowBubble(isFullscreen: false, isFocused: true))
    }

    func testManualSummonOverridesPetSuppressionWithoutChangingBubblePolicy() {
        XCTAssertTrue(EdgePetVisibilityPolicy.shouldBeVisible(
            wantsVisible: true,
            isFullscreenSuppressed: true,
            isFocusSuppressed: true,
            hasManualOverride: true
        ))
        XCTAssertFalse(FullscreenPresentationPolicy.shouldShowBubble(
            isFullscreen: true,
            isFocused: true
        ))
    }

    func testPetStillHidesWithoutManualOverrideOrVisibleIntent() {
        XCTAssertFalse(EdgePetVisibilityPolicy.shouldBeVisible(
            wantsVisible: true,
            isFullscreenSuppressed: true,
            isFocusSuppressed: false,
            hasManualOverride: false
        ))
        XCTAssertFalse(EdgePetVisibilityPolicy.shouldBeVisible(
            wantsVisible: false,
            isFullscreenSuppressed: false,
            isFocusSuppressed: false,
            hasManualOverride: true
        ))
    }

    func testManualOverrideClearsOnlyAfterEverySuppressionEnds() {
        XCTAssertFalse(EdgePetVisibilityPolicy.manualOverrideForSummon(
            isFullscreenSuppressed: false,
            isFocusSuppressed: false
        ))
        XCTAssertTrue(EdgePetVisibilityPolicy.manualOverrideForSummon(
            isFullscreenSuppressed: true,
            isFocusSuppressed: false
        ))
        XCTAssertFalse(EdgePetVisibilityPolicy.shouldClearManualOverride(
            isFullscreenSuppressed: false,
            isFocusSuppressed: true
        ))
        XCTAssertTrue(EdgePetVisibilityPolicy.shouldClearManualOverride(
            isFullscreenSuppressed: false,
            isFocusSuppressed: false
        ))
    }
}
