@MainActor
protocol AlphaMetricsPersisting: AnyObject {
    func load() -> AlphaMetricsSnapshot
    func save(_ snapshot: AlphaMetricsSnapshot)
    func clear()
}
