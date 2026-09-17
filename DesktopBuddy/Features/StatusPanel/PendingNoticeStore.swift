import Combine
import Foundation

@MainActor
final class PendingNoticeStore: ObservableObject {
    @Published private(set) var notices: [DeviceNotice] = []
    private var queue = PendingNoticeQueue()
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var expiryTask: Task<Void, Never>?

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            let milliseconds = Int64((max(0, seconds) * 1_000).rounded(.up))
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    deinit {
        expiryTask?.cancel()
    }

    @discardableResult
    func enqueue(_ notice: DeviceNotice, now explicitNow: Date? = nil) -> Bool {
        let added = queue.enqueue(notice, now: explicitNow ?? now())
        publishAndSchedule()
        return added
    }

    func dismiss(id: UUID) {
        queue.dismiss(id: id)
        publishAndSchedule()
    }

    func expire(now explicitNow: Date? = nil) {
        queue.expire(now: explicitNow ?? now())
        publishAndSchedule()
    }

    private func publishAndSchedule() {
        notices = queue.notices
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard let nextExpiry = queue.notices.map(\.expiresAt).min() else { return }

        let delay = max(0, nextExpiry.timeIntervalSince(now()))
        let sleep = self.sleep
        expiryTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.expire()
        }
    }
}
