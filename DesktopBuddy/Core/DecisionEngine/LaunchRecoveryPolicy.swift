enum LaunchRecoveryAction: Equatable {
    case restoreNormally
    case startWithEdgePetHidden
}

enum LaunchRecoveryPolicy {
    static func action(previousSessionWasActive: Bool) -> LaunchRecoveryAction {
        previousSessionWasActive ? .startWithEdgePetHidden : .restoreNormally
    }
}
