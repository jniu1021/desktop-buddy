import AppKit
import CoreGraphics

final class SystemForegroundActivitySensor: ForegroundActivitySensing {
    func currentSnapshot() -> ForegroundActivitySnapshot {
        return ForegroundActivitySnapshot(
            bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            secondsSinceLastInput: ForegroundIdleTimeReader.secondsSinceLastInput()
        )
    }
}

enum ForegroundIdleTimeReader {
    static func secondsSinceLastInput(
        makeAnyInputEventType: () -> CGEventType? = {
            // The all-input token is not exported to Swift as a named constant.
            CGEventType(rawValue: UInt32.max)
        },
        readSeconds: (CGEventType) -> TimeInterval = {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: $0
            )
        }
    ) -> TimeInterval? {
        guard let anyInput = makeAnyInputEventType() else { return nil }
        let seconds = readSeconds(anyInput)
        return seconds.isFinite ? seconds : nil
    }
}
