import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ApplicationLaunchPolicy.shouldStartCoordinator(
            environment: ProcessInfo.processInfo.environment
        ) else { return }

        let coordinator = AppCoordinator(container: .live())
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
