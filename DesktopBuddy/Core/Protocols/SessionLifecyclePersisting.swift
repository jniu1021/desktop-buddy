@MainActor
protocol SessionLifecyclePersisting: AnyObject {
    var isSessionActive: Bool { get set }
}
