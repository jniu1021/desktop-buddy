import AppKit
import Combine
import SwiftUI

/// Activities are self-reports; metadata alone never establishes semantic activity.
enum DiaryActivity: String, CaseIterable, Codable {
    case coding, reading, video, meeting, chatting, gaming, other, uncertain, away
    var title: String {
        switch self {
        case .coding: "Coding"
        case .reading: "Reading / research"
        case .video: "Watching video"
        case .meeting: "Meeting / call"
        case .chatting: "Chatting"
        case .gaming: "Gaming"
        case .other: "Other"
        case .uncertain: "Not sure"
        case .away: "Away from computer"
        }
    }
}

struct DiaryInterval: Codable, Equatable {
    var start: Date
    var end: Date
    var activity: String
    var source: String
    var seconds: Double { max(0, end.timeIntervalSince(start)) }
}

struct ActivityDiaryLedger {
    private(set) var intervals: [DiaryInterval] = []

    init(intervals: [DiaryInterval] = []) { self.intervals = intervals }

    mutating func append(start: Date, end: Date, activity: String, source: String) {
        let duration = end.timeIntervalSince(start)
        // Never account for sleep, a stalled timer or a negative clock adjustment.
        guard duration > 0, duration <= 20 else { return }
        if let last = intervals.last, last.end == start,
           last.activity == activity, last.source == source {
            intervals[intervals.count - 1].end = end
        } else {
            intervals.append(DiaryInterval(start: start, end: end, activity: activity, source: source))
        }
        intervals.removeAll { $0.end < end.addingTimeInterval(-7 * 86400) }
    }

    mutating func labelLastInterval(_ activity: DiaryActivity) {
        guard let last = intervals.popLast() else { return }
        // Only label the last ten seconds, not a whole merged multi-hour interval.
        let cut = max(last.start, last.end.addingTimeInterval(-10))
        if cut > last.start {
            intervals.append(DiaryInterval(start: last.start, end: cut, activity: last.activity, source: last.source))
        }
        intervals.append(DiaryInterval(start: cut, end: last.end, activity: activity.rawValue, source: "self_report"))
    }

    func totals(on date: Date, calendar: Calendar = .current) -> [String: Double] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [:] }
        var totals: [String: Double] = [:]
        for interval in intervals {
            let seconds = min(end, interval.end).timeIntervalSince(max(start, interval.start))
            if seconds > 0 { totals[interval.activity, default: 0] += seconds }
        }
        return totals
    }
}

@MainActor
final class ActivityDiaryStore: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var cue = "Disabled"
    @Published private(set) var totals: [String: Double] = [:]
    @Published private(set) var lastIntervalEnd: Date?
    let screenProbe = ScreenActivityProbe()
    private var lastScreenAttempt: Date?
    private let sensor: any ForegroundActivitySensing
    private let defaults: UserDefaults
    private var ledger: ActivityDiaryLedger
    private var previous: Date?
    private var previousActivity = "unknown"
    private var task: Task<Void, Never>?
    private var samplesSinceSave = 0
    private var suspended = false
    private static let key = "activityDiary.intervals.v1"

    init(sensor: any ForegroundActivitySensing, defaults: UserDefaults = .standard) {
        self.sensor = sensor
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        let decoded = data.flatMap { try? JSONDecoder().decode([DiaryInterval].self, from: $0) } ?? []
        let recent = decoded.filter { $0.end >= Date().addingTimeInterval(-7 * 86400) }
        ledger = ActivityDiaryLedger(intervals: recent)
        totals = ledger.totals(on: Date())
        // Persist pruning even if no new session is started.
        if decoded.count != recent.count { persist() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        task?.cancel(); task = nil; previous = nil
        if !value { screenProbe.invalidate(); cue = "Disabled"; persist(); return }
        guard !suspended else { return }
        cue = "Metadata only — semantic activity unknown"
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        if value {
            screenProbe.invalidate()
            task?.cancel(); task = nil; previous = nil; persist()
            cue = "Paused while session is inactive"
        } else if enabled { setEnabled(true) }
    }

    func sample(now: Date = Date()) {
        guard enabled, !suspended else { return }
        let snapshot = sensor.currentSnapshot()
        let own = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let category = WorkApplicationCategory.category(for: snapshot.bundleIdentifier)?.rawValue ?? "unclassified app"
        let possiblyAway = snapshot.secondsSinceLastInput.map { $0.isFinite && $0 >= 120 } ?? false
        if !own, !possiblyAway {
            let interval: TimeInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 120 : 30
            if lastScreenAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true {
                lastScreenAttempt = now
                screenProbe.sampleIfNeeded()
            }
        }
        let activity = own ? "feedback_ui" : (possiblyAway ? "possibly_away" : "unknown")
        cue = own ? "Desktop Buddy is in front" : "\(category) · \(possiblyAway ? "possibly away" : "activity unknown")"
        if let previous {
            // A transition interval remains unknown rather than backfilling a new state.
            ledger.append(start: previous, end: now,
                activity: previousActivity == activity ? activity : "unknown", source: "metadata")
            lastIntervalEnd = now
        }
        previous = now; previousActivity = activity
        totals = ledger.totals(on: now)
        samplesSinceSave += 1
        if samplesSinceSave >= 6 { persist(); samplesSinceSave = 0 }
    }

    func correct(_ activity: DiaryActivity) {
        guard enabled, lastIntervalEnd != nil else { return }
        ledger.labelLastInterval(activity)
        totals = ledger.totals(on: Date())
        persist()
    }

    func clear() {
        ledger = ActivityDiaryLedger(); totals = [:]; lastIntervalEnd = nil; previous = nil
        defaults.removeObject(forKey: Self.key)
    }

    func stop() { screenProbe.disable(); task?.cancel(); task = nil; previous = nil; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(ledger.intervals) { defaults.set(data, forKey: Self.key) }
    }
}

struct ActivityDiaryCard: View {
    @ObservedObject var diary: ActivityDiaryStore
    @State private var selected: DiaryActivity = .uncertain
    @State private var submitted = false
    @State private var confirmingClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity diary · experimental").font(.subheadline.bold())
            Toggle("Enable local activity diary", isOn: Binding(get: { diary.enabled }, set: { diary.setEnabled($0) }))
            Text("Optional. Stores time intervals and your answers locally for up to 7 days. No screenshots, audio, titles or app identifiers are saved. Pauses on sleep or inactive session. Re-enable after restarting the app.")
                .font(.caption).foregroundStyle(.secondary)
            if diary.enabled {
                Text(diary.cue).font(.caption)
                ScreenActivityCard(probe: diary.screenProbe)
                if let end = diary.lastIntervalEnd {
                    Text("What were you doing in the recorded interval ending at \(end.formatted(date: .omitted, time: .standard))? Your answer labels at most its final 10 seconds.")
                        .font(.caption)
                    Picker("Activity", selection: $selected) {
                        ForEach(DiaryActivity.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Button("Save answer") { diary.correct(selected); submitted = true }
                    if submitted { Text("Saved as self-report.").font(.caption) }
                }
            }
            Text("Today · recorded time").font(.caption.bold())
            ForEach(diary.totals.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(DiaryActivity(rawValue: key)?.title ?? key.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    Text("\(Int(diary.totals[key, default: 0] / 60)) min")
                }.font(.caption)
            }
            Text("Unknown and possibly-away time are not verified focus or verified absence. Screen evidence is a separate unvalidated preview; system audio is not connected yet.").font(.caption).foregroundStyle(.secondary)
            Button("Clear diary…", role: .destructive) { confirmingClear = true }
                .confirmationDialog("Delete all local activity diary intervals?", isPresented: $confirmingClear) {
                    Button("Delete diary", role: .destructive) { diary.clear() }
                }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: selected) { _ in submitted = false }
    }
}
