import Combine
import Foundation

@MainActor
final class AlphaMetricsTracker: ObservableObject {
    @Published private(set) var snapshot: AlphaMetricsSnapshot

    private let repository: any AlphaMetricsPersisting
    private var sessionStartedAt: Date?
    private var actionableNoticeIDs: Set<UUID> = []

    init(repository: any AlphaMetricsPersisting) {
        self.repository = repository
        self.snapshot = repository.load()
    }

    func startSession(at date: Date = Date()) {
        guard sessionStartedAt == nil else { return }
        sessionStartedAt = date
        snapshot.sessionsStarted += 1
        persist()
    }

    func stopSession(at date: Date = Date()) {
        guard let sessionStartedAt else { return }
        let duration = max(0, date.timeIntervalSince(sessionStartedAt))
        snapshot.completedSessionSeconds += duration
        snapshot.lastCompletedSessionSeconds = duration
        self.sessionStartedAt = nil
        persist()
    }

    func recordNoticeShown(id: UUID) {
        snapshot.noticesShown += 1
        actionableNoticeIDs.insert(id)
        persist()
    }

    func recordNoticeDismissed(id: UUID) {
        snapshot.noticesDismissed += 1
        actionableNoticeIDs.remove(id)
        persist()
    }

    func recordActionForPendingNotices(ids: [UUID]) {
        let actedOn = actionableNoticeIDs.intersection(ids)
        guard !actedOn.isEmpty else { return }
        snapshot.noticesActedOn += actedOn.count
        actionableNoticeIDs.subtract(actedOn)
        persist()
    }

    func recordMetricGlance(_ metric: StatusMetric) {
        switch metric {
        case .battery: snapshot.batteryGlances += 1
        case .memoryUsage: snapshot.memoryGlances += 1
        case .codexAllowance: snapshot.codexGlances += 1
        }
        persist()
    }

    func totalSessionSeconds(at date: Date = Date()) -> TimeInterval {
        let current = sessionStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return snapshot.completedSessionSeconds + current
    }

    func clear(at date: Date = Date()) {
        repository.clear()
        snapshot = .empty
        actionableNoticeIDs.removeAll()
        if sessionStartedAt != nil {
            sessionStartedAt = date
            snapshot.sessionsStarted = 1
            persist()
        }
    }

    private func persist() {
        repository.save(snapshot)
    }
}
