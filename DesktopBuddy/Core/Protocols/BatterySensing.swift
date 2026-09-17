protocol BatterySensing: Sendable {
    func currentState() async -> BatteryState
}
