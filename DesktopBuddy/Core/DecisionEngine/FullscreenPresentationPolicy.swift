import Foundation

enum FullscreenPollingPolicy {
    static let refreshInterval: Duration = .seconds(15)
}

struct DisplayGeometry: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum FullscreenPresentationPolicy {
    static func containsFullscreenWindow(
        _ windows: [DisplayGeometry],
        on display: DisplayGeometry
    ) -> Bool {
        windows.contains { windowFillsDisplay($0, display: display) }
    }

    static func windowFillsDisplay(
        _ window: DisplayGeometry,
        display: DisplayGeometry,
        tolerance: Double = 4
    ) -> Bool {
        guard window.width > 0, window.height > 0 else { return false }
        return abs(window.x - display.x) <= tolerance
            && abs(window.y - display.y) <= tolerance
            && abs(window.width - display.width) <= tolerance
            && abs(window.height - display.height) <= tolerance
    }

    static func shouldShowBubble(isFullscreen: Bool, isFocused: Bool) -> Bool {
        !isFullscreen && !isFocused
    }
}

enum EdgePetVisibilityPolicy {
    static func manualOverrideForSummon(
        isFullscreenSuppressed: Bool,
        isFocusSuppressed: Bool
    ) -> Bool {
        isFullscreenSuppressed || isFocusSuppressed
    }

    static func shouldBeVisible(
        wantsVisible: Bool,
        isFullscreenSuppressed: Bool,
        isFocusSuppressed: Bool,
        hasManualOverride: Bool,
        automaticRestoreSuppressed: Bool = false
    ) -> Bool {
        guard wantsVisible else { return false }
        guard !automaticRestoreSuppressed else { return false }
        return hasManualOverride || (!isFullscreenSuppressed && !isFocusSuppressed)
    }

    static func shouldClearManualOverride(
        isFullscreenSuppressed: Bool,
        isFocusSuppressed: Bool
    ) -> Bool {
        !isFullscreenSuppressed && !isFocusSuppressed
    }
}
