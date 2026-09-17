protocol MemoryUsageSensing: Sendable {
    func currentState() async -> MemoryUsageState
    func stateUpdates() -> AsyncStream<MemoryUsageState>
    func setSamplingInterval(seconds: Int)
}
