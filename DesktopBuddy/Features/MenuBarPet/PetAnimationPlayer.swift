import AppKit
import Combine

enum PetAnimationPolicy {
    static let restingDelay = Duration.milliseconds(1_800)
    static let earMovementDelay = Duration.milliseconds(160)
    static let warningRestingDelay = Duration.milliseconds(420)
    static let warningEarMovementDelay = Duration.milliseconds(120)

    static func shouldAnimate(
        animationsEnabled: Bool,
        systemReduceMotionEnabled: Bool
    ) -> Bool {
        animationsEnabled && !systemReduceMotionEnabled
    }

    static func nextEarFrame(after frameIndex: Int) -> Int {
        (frameIndex + 1) % 4
    }

    static func delay(after frameIndex: Int, warningActive: Bool = false) -> Duration {
        if warningActive {
            return frameIndex == 0 ? warningRestingDelay : warningEarMovementDelay
        }
        return frameIndex == 0 ? restingDelay : earMovementDelay
    }
}

@MainActor
final class PetAnimationPlayer: NSObject, ObservableObject {
    @Published private(set) var frameIndex = 0
    @Published private(set) var systemReduceMotionEnabled: Bool
    @Published private(set) var warningActive = false
    @Published var animationsEnabled: Bool {
        didSet {
            preferences.animationsEnabled = animationsEnabled
            reconcilePlayback()
        }
    }

    private let preferences: any PreferencesStoring
    private var playbackTask: Task<Void, Never>?

    init(preferences: any PreferencesStoring) {
        self.preferences = preferences
        self.animationsEnabled = preferences.animationsEnabled
        self.systemReduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    func start() {
        reconcilePlayback()
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        frameIndex = 0
    }

    func setWarningActive(_ active: Bool) {
        guard warningActive != active else { return }
        warningActive = active
        frameIndex = 0
        reconcilePlayback()
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        systemReduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reconcilePlayback()
    }

    private func reconcilePlayback() {
        playbackTask?.cancel()
        playbackTask = nil

        guard PetAnimationPolicy.shouldAnimate(
            animationsEnabled: animationsEnabled,
            systemReduceMotionEnabled: systemReduceMotionEnabled
        ) else {
            frameIndex = 0
            return
        }

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let currentFrame = self?.frameIndex else { return }
                guard let warningActive = self?.warningActive else { return }

                do {
                    try await Task.sleep(
                        for: PetAnimationPolicy.delay(
                            after: currentFrame,
                            warningActive: warningActive
                        )
                    )
                } catch {
                    return
                }

                guard let self else { return }
                frameIndex = PetAnimationPolicy.nextEarFrame(after: frameIndex)
            }
        }
    }
}
