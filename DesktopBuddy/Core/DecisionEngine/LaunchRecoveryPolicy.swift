enum LaunchRecoveryAction: Equatable {
    case restoreNormally
    case startWithEdgePetHidden
}

enum LaunchRecoveryPolicy {
    static func action(previousSessionWasActive: Bool) -> LaunchRecoveryAction {
        previousSessionWasActive ? .startWithEdgePetHidden : .restoreNormally
    }
}

enum ApplicationLaunchPolicy {
    private static let testEnvironmentKeys = [
        "XCTestConfigurationFilePath",
        "XCTestBundlePath",
        "XCTestSessionIdentifier"
    ]

    static func shouldStartCoordinator(environment: [String: String]) -> Bool {
        !testEnvironmentKeys.contains { environment[$0] != nil }
    }
}

enum RuntimeLifecycleState: Equatable {
    case active
    case suspended
}

enum RuntimeLifecycleEvent: Equatable {
    case systemWillSleep
    case systemDidWake
}

enum RuntimeLifecycleAction: Equatable {
    case suspend
    case resume
}

struct RuntimeLifecycleTransition: Equatable {
    let state: RuntimeLifecycleState
    let action: RuntimeLifecycleAction?
}

enum RuntimeLifecyclePolicy {
    static func transition(
        from state: RuntimeLifecycleState,
        event: RuntimeLifecycleEvent
    ) -> RuntimeLifecycleTransition {
        switch (state, event) {
        case (.active, .systemWillSleep):
            return RuntimeLifecycleTransition(state: .suspended, action: .suspend)
        case (.suspended, .systemDidWake):
            return RuntimeLifecycleTransition(state: .active, action: .resume)
        case (.active, .systemDidWake), (.suspended, .systemWillSleep):
            return RuntimeLifecycleTransition(state: state, action: nil)
        }
    }
}
