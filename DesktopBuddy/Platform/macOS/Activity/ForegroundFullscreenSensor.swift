import AppKit
import CoreGraphics

final class ForegroundFullscreenSensor: FullscreenSensing {
    func isForegroundApplicationFullscreen(on display: DisplayGeometry) -> Bool {
        guard let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else { return false }

        var foregroundWindows: [DisplayGeometry] = []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == foregroundPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }

            let geometry = DisplayGeometry(x: x, y: y, width: width, height: height)
            foregroundWindows.append(geometry)
        }
        return FullscreenPresentationPolicy.containsFullscreenWindow(
            foregroundWindows,
            on: display
        )
    }
}
