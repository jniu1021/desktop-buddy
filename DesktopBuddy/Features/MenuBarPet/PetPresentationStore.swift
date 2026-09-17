import Combine

@MainActor
final class PetPresentationStore: ObservableObject {
    @Published private(set) var current: PetPresentation = .menuIdle
    private var engine = PetPresentationEngine()

    func handle(_ event: PetPresentationEvent) {
        engine.handle(event)
        current = engine.current
    }
}
