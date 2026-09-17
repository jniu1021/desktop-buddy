import Foundation

enum CodexAllowanceDecoder {
    private struct Result: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
    }

    private struct Bucket: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Int?
        let resetsAt: Double?

        var model: CodexQuotaWindow? {
            guard let usedPercent, usedPercent.isFinite, usedPercent >= 0 else { return nil }
            return CodexQuotaWindow(
                usedPercent: usedPercent,
                durationMinutes: windowDurationMins,
                resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    static func decodeResult(_ data: Data, now: Date) -> CodexAllowanceState? {
        guard let result = try? JSONDecoder().decode(Result.self, from: data),
              let bucket = result.rateLimitsByLimitId?["codex"] ?? result.rateLimits,
              let primary = bucket.primary?.model else { return nil }
        return CodexAllowanceState(
            availability: .available,
            primary: primary,
            secondary: bucket.secondary?.model,
            updatedAt: now
        )
    }
}
