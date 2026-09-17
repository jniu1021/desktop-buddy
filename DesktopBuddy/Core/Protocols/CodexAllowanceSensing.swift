protocol CodexAllowanceSensing: Sendable {
    func currentAllowance() async -> CodexAllowanceState
}
