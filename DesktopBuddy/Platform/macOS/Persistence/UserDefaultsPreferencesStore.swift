import Foundation

@MainActor
final class UserDefaultsPreferencesStore: PreferencesStoring {
    private enum Key {
        static let selectedMetric = "selectedStatusMetric"
        static let onboardingCompleted = "onboardingCompleted"
        static let interactionMode = "interactionMode"
        static let focusSuppressionEnabled = "focusSuppressionEnabled"
        static let applicationActivityEnabled = "applicationActivityEnabled"
        static let codexIntegrationEnabled = "codexIntegrationEnabled"
        static let animationsEnabled = "animationsEnabled"
        static let edgePetScale = "edgePetScale"
        static let edgePetVisible = "edgePetVisible"
        static let edgePetEdge = "edgePetEdge"
        static let edgePetEdgePosition = "edgePetEdgePosition"
        static let legacyEdgePetVerticalPosition = "edgePetVerticalPosition"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedMetric: StatusMetric {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.selectedMetric),
                let metric = StatusMetric(rawValue: rawValue)
            else {
                return .battery
            }

            return metric
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.selectedMetric)
        }
    }

    var onboardingCompleted: Bool {
        get {
            if let completed = defaults.object(forKey: Key.onboardingCompleted) as? Bool {
                return completed
            }
            // Existing alpha users had no onboarding key. Do not interrupt
            // them with a first-run guide after an app update.
            let existingKeys = [
                Key.selectedMetric, Key.interactionMode, Key.focusSuppressionEnabled,
                Key.applicationActivityEnabled, Key.codexIntegrationEnabled,
                Key.animationsEnabled, Key.edgePetScale, Key.edgePetVisible,
                Key.edgePetEdge, Key.edgePetEdgePosition
            ]
            return existingKeys.contains { defaults.object(forKey: $0) != nil }
        }
        set { defaults.set(newValue, forKey: Key.onboardingCompleted) }
    }

    var interactionMode: InteractionMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.interactionMode),
                  let mode = InteractionMode(rawValue: rawValue) else {
                return .balanced
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.interactionMode)
        }
    }

    var focusSuppressionEnabled: Bool {
        get { defaults.object(forKey: Key.focusSuppressionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.focusSuppressionEnabled) }
    }

    var applicationActivityEnabled: Bool {
        get { defaults.object(forKey: Key.applicationActivityEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.applicationActivityEnabled) }
    }

    var codexIntegrationEnabled: Bool {
        get { defaults.object(forKey: Key.codexIntegrationEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.codexIntegrationEnabled) }
    }

    var animationsEnabled: Bool {
        get {
            defaults.object(forKey: Key.animationsEnabled) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Key.animationsEnabled)
        }
    }

    var edgePetScale: Double {
        get {
            defaults.object(forKey: Key.edgePetScale) as? Double ?? 1
        }
        set {
            defaults.set(newValue, forKey: Key.edgePetScale)
        }
    }

    var edgePetVisible: Bool {
        get { defaults.object(forKey: Key.edgePetVisible) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.edgePetVisible) }
    }

    var edgePetEdge: PetScreenEdge {
        get {
            guard let rawValue = defaults.string(forKey: Key.edgePetEdge),
                  let edge = PetScreenEdge(rawValue: rawValue) else {
                return .right
            }
            return edge
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.edgePetEdge)
        }
    }

    var edgePetEdgePosition: Double {
        get {
            if let position = defaults.object(forKey: Key.edgePetEdgePosition) as? Double {
                return position
            }
            return defaults.object(forKey: Key.legacyEdgePetVerticalPosition) as? Double ?? 0.08
        }
        set {
            defaults.set(newValue, forKey: Key.edgePetEdgePosition)
        }
    }
}
