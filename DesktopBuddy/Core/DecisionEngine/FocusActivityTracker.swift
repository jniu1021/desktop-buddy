import Foundation

enum WorkApplicationCategory: String, CaseIterable, Hashable {
    case development
    case terminal
    case writing
    case design
    case office

    private static let identifiersByCategory: [WorkApplicationCategory: Set<String>] = [
        .development: [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.openai.codex",
            "com.google.android.studio",
            "com.panic.Nova",
            "com.sublimetext.4",
            "dev.zed.Zed"
        ],
        .terminal: [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable"
        ],
        .writing: [
            "com.apple.iWork.Pages",
            "com.microsoft.Word",
            "md.obsidian",
            "notion.id"
        ],
        .design: [
            "com.bohemiancoding.sketch3",
            "com.figma.Desktop"
        ],
        .office: [
            "com.apple.iWork.Keynote",
            "com.apple.iWork.Numbers",
            "com.microsoft.Excel",
            "com.microsoft.Powerpoint"
        ]
    ]

    static func category(for bundleIdentifier: String?) -> WorkApplicationCategory? {
        guard let bundleIdentifier else { return nil }
        if bundleIdentifier.hasPrefix("com.jetbrains.") {
            return .development
        }
        return identifiersByCategory.first { $0.value.contains(bundleIdentifier) }?.key
    }

    static func isKnownWorkApplication(_ bundleIdentifier: String?) -> Bool {
        category(for: bundleIdentifier) != nil
    }
}

struct FocusActivityTracker {
    private(set) var isPossiblyFocused = false
    private var foregroundBundleIdentifier: String?
    private var workSessionSince: Date?
    private var switchTimes: [Date] = []
    private var activeSampleTimes: [Date] = []

    mutating func reset() {
        self = FocusActivityTracker()
    }

    mutating func noteForegroundApplication(_ bundleIdentifier: String?, now: Date) {
        guard bundleIdentifier != foregroundBundleIdentifier else { return }
        let continuesKnownWork = WorkApplicationCategory.isKnownWorkApplication(foregroundBundleIdentifier)
            && WorkApplicationCategory.isKnownWorkApplication(bundleIdentifier)
        if foregroundBundleIdentifier != nil, bundleIdentifier != nil {
            switchTimes.append(now)
        }
        foregroundBundleIdentifier = bundleIdentifier
        if !continuesKnownWork {
            workSessionSince = WorkApplicationCategory.isKnownWorkApplication(bundleIdentifier) ? now : nil
            activeSampleTimes.removeAll()
        }
        isPossiblyFocused = false
        trimHistory(now: now)
    }

    @discardableResult
    mutating func update(_ snapshot: ForegroundActivitySnapshot, now: Date) -> Bool {
        noteForegroundApplication(snapshot.bundleIdentifier, now: now)
        trimHistory(now: now)

        let isRecentlyActive = snapshot.secondsSinceLastInput.map {
            $0.isFinite && $0 >= 0 && $0 <= 45
        } ?? false
        if isRecentlyActive,
           activeSampleTimes.last.map({ now.timeIntervalSince($0) >= 8 }) ?? true {
            activeSampleTimes.append(now)
        }

        isPossiblyFocused = WorkApplicationCategory.isKnownWorkApplication(foregroundBundleIdentifier)
            && workSessionSince.map { now.timeIntervalSince($0) >= 5 * 60 } == true
            && isRecentlyActive
            && activeSampleTimes.count >= 8
            && switchTimes.count <= 2
        return isPossiblyFocused
    }

    private mutating func trimHistory(now: Date) {
        switchTimes.removeAll(where: { now.timeIntervalSince($0) >= 5 * 60 })
        activeSampleTimes.removeAll(where: { now.timeIntervalSince($0) >= 5 * 60 })
    }
}
