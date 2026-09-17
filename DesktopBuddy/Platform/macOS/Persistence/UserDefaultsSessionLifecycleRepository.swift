import Foundation

@MainActor
final class UserDefaultsSessionLifecycleRepository: SessionLifecyclePersisting {
    private static let activeSessionKey = "sessionLifecycle.isActive"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isSessionActive: Bool {
        get { defaults.bool(forKey: Self.activeSessionKey) }
        set { defaults.set(newValue, forKey: Self.activeSessionKey) }
    }
}
