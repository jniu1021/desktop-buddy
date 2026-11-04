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
        guard let end = intervals.last?.end else { return }
        label(endingAt: end, activity: activity)
    }

    @discardableResult
    mutating func label(endingAt end: Date, activity: DiaryActivity) -> Bool {
        guard let index = intervals.firstIndex(where: { $0.start < end && $0.end >= end }) else { return false }
        let original = intervals[index]
        let cut = max(original.start, end.addingTimeInterval(-10))
        var replacement: [DiaryInterval] = []
        if original.start < cut {
            replacement.append(DiaryInterval(start: original.start, end: cut, activity: original.activity, source: original.source))
        }
        replacement.append(DiaryInterval(start: cut, end: end, activity: activity.rawValue, source: "self_report"))
        if end < original.end {
            replacement.append(DiaryInterval(start: end, end: original.end, activity: original.activity, source: original.source))
        }
        intervals.replaceSubrange(index...index, with: replacement)
        return true
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

struct DiaryReview: Codable, Equatable {
    let end: Date
    let prediction: String
    let audioCue: String
    var answer: String?
}

enum ActivityEvidenceFusion {
    static func predict(screen: String?, screenAge: Double?, audio: String?, audioAge: Double?, sameApp: Bool) -> String {
        guard sameApp, let screenAge, (0...45).contains(screenAge),
              let screen, ["coding", "video", "meeting"].contains(screen) else { return "unknown" }
        // Sound can corroborate, but never turns speech into a meeting on its own.
        if screen == "meeting" {
            guard let audioAge, (0...75).contains(audioAge), audio == "speech" else { return "unknown" }
        }
        return screen
    }
}

@MainActor
final class ActivityDiaryStore: ObservableObject {
    @Published var recordTentativeEstimates = false
    @Published private(set) var review: DiaryReview?
    @Published private(set) var feedbackCount = 0
    @Published private(set) var enabled = false
    @Published private(set) var cue = "Disabled"
    @Published private(set) var totals: [String: Double] = [:]
    @Published private(set) var lastIntervalEnd: Date?
    let screenProbe = ScreenActivityProbe()
    let audioProbe = SystemAudioProbe()
    private var lastAudioAttempt: Date?
    private var lastScreenAttempt: Date?
    private let sensor: any ForegroundActivitySensing
    private let defaults: UserDefaults
    private var ledger: ActivityDiaryLedger
    private var previous: Date?
    private var previousActivity = "unknown"
    private var previousSource = "metadata"
    private var latestReviewable: DiaryReview?
    private var feedback: [DiaryReview] = []
    private static let feedbackKey = "activityDiary.feedback.v1"
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
        feedback = defaults.data(forKey: Self.feedbackKey).flatMap { try? JSONDecoder().decode([DiaryReview].self, from: $0) } ?? []
        feedback = Array(feedback.filter { $0.end >= Date().addingTimeInterval(-7 * 86400) }.suffix(1000))
        feedbackCount = feedback.count
        // Persist pruning even if no new session is started.
        if decoded.count != recent.count { persist() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        task?.cancel(); task = nil; previous = nil
        if !value { screenProbe.invalidate(); audioProbe.invalidate(); cue = "Disabled"; persist(); return }
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
            audioProbe.invalidate()
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
        if !own {
            let interval: TimeInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 180 : 60
            if lastAudioAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true {
                lastAudioAttempt = now
                audioProbe.sampleIfNeeded()
            }
        }
        let predicted = ActivityEvidenceFusion.predict(
            screen: screenProbe.evidence?.activity,
            screenAge: screenProbe.observedAt.map { now.timeIntervalSince($0) },
            audio: audioProbe.cue?.category,
            audioAge: audioProbe.observedAt.map { now.timeIntervalSince($0) },
            sameApp: screenProbe.observedPID == NSWorkspace.shared.frontmostApplication?.processIdentifier)
        let estimate = recordTentativeEstimates && predicted != "unknown" ? "tentative_" + predicted : "unknown"
        let activity = own ? "feedback_ui" : (possiblyAway ? "possibly_away" : estimate)
        cue = own ? "Desktop Buddy is in front" : "\(category) · \(possiblyAway ? "possibly away" : "activity unknown")"
        let source = activity.hasPrefix("tentative_") ? "screen_audio_heuristic_v1" : "metadata"
        if let previous {
            // A transition interval remains unknown rather than backfilling a new state.
            ledger.append(start: previous, end: now,
                activity: previousActivity == activity && previousSource == source ? activity : "unknown", source: previousSource == source ? source : "metadata")
            lastIntervalEnd = now
            if !own, now.timeIntervalSince(previous) > 0, now.timeIntervalSince(previous) <= 20 {
                latestReviewable = DiaryReview(end: now, prediction: predicted,
                    audioCue: audioProbe.observedAt.map { now.timeIntervalSince($0) <= 75 } == true ? (audioProbe.cue?.category ?? "unknown") : "unknown")
            }
        }
        previous = now; previousActivity = activity; previousSource = source
        totals = ledger.totals(on: now)
        samplesSinceSave += 1
        if samplesSinceSave >= 6 { persist(); samplesSinceSave = 0 }
    }

    func beginReview() { review = latestReviewable }

    func correct(_ activity: DiaryActivity) {
        guard var target = review, ledger.label(endingAt: target.end, activity: activity) else { return }
        target.answer = activity.rawValue
        feedback.removeAll { $0.end == target.end }
        feedback.append(target)
        feedback = Array(feedback.filter { $0.end >= Date().addingTimeInterval(-7 * 86400) }.suffix(1000))
        feedbackCount = feedback.count
        review = nil
        totals = ledger.totals(on: Date())
        persist()
    }

    func clear() {
        ledger = ActivityDiaryLedger(); totals = [:]; lastIntervalEnd = nil; previous = nil
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.feedbackKey)
        feedback = []; feedbackCount = 0; review = nil; latestReviewable = nil
    }

    func stop() { screenProbe.disable(); audioProbe.disable(); task?.cancel(); task = nil; previous = nil; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(ledger.intervals) { defaults.set(data, forKey: Self.key) }
        if let data = try? JSONEncoder().encode(feedback) { defaults.set(data, forKey: Self.feedbackKey) }
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
                SystemAudioCard(probe: diary.audioProbe)
                Toggle("Record tentative activity estimates", isOn: $diary.recordTentativeEstimates)
                Text("Optional heuristic estimates stay separate from confirmed activity. Meeting requires fresh speech and screen cues. No-input time remains possibly away.").font(.caption)
                Button("Review recent task interval") { diary.beginReview(); submitted = false }
                Text("Saved feedback: \(diary.feedbackCount)").font(.caption)
                if let target = diary.review {
                    let end = target.end
                    Text("What were you doing in the recorded interval ending at \(end.formatted(date: .omitted, time: .standard))? This interval is frozen while you answer; labels at most its final 10 seconds.")
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
            Text("Unknown and possibly-away time are not verified focus or verified absence. Tentative estimates are heuristic, not verified activity or focus. Feedback does not automatically retrain a model.").font(.caption).foregroundStyle(.secondary)
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
