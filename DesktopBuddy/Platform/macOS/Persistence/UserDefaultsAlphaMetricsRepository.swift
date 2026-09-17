import Foundation

@MainActor
final class UserDefaultsAlphaMetricsRepository: AlphaMetricsPersisting {
    private static let storageKey = "localAlphaMetrics.v1"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AlphaMetricsSnapshot {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snapshot = try? decoder.decode(AlphaMetricsSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    func save(_ snapshot: AlphaMetricsSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
