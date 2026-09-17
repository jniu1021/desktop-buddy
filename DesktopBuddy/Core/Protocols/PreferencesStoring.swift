@MainActor
protocol PreferencesStoring: AnyObject {
    var selectedMetric: StatusMetric { get set }
    var onboardingCompleted: Bool { get set }
    var interactionMode: InteractionMode { get set }
    var focusSuppressionEnabled: Bool { get set }
    var applicationActivityEnabled: Bool { get set }
    var codexIntegrationEnabled: Bool { get set }
    var animationsEnabled: Bool { get set }
    var edgePetScale: Double { get set }
    var edgePetVisible: Bool { get set }
    var edgePetEdge: PetScreenEdge { get set }
    var edgePetEdgePosition: Double { get set }
}
