protocol FanSensing: Sendable {
    func currentState() async -> FanReadoutState
}
