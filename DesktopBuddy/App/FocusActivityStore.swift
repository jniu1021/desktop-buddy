import Combine
import Foundation

@MainActor
final class FocusActivityStore: ObservableObject {
    @Published private(set) var isPossiblyFocused = false
    private var tracker = FocusActivityTracker()

    func noteForegroundApplication(_ bundleIdentifier: String?, now: Date = Date()) {
        tracker.noteForegroundApplication(bundleIdentifier, now: now)
        isPossiblyFocused = tracker.isPossiblyFocused
    }

    func update(_ snapshot: ForegroundActivitySnapshot, now: Date = Date()) {
        isPossiblyFocused = tracker.update(snapshot, now: now)
    }

    func reset() {
        tracker.reset()
        isPossiblyFocused = false
    }
}
