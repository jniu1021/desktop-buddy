import AppKit
import SwiftUI
import Foundation

struct ResearchSample: Codable {
    let t: Double
    let category: String
    let idleSeconds: Double?
    let fullscreen: Bool?
    let switchCount: Int
    let stableSeconds: Double
    let sensingMS: Double
}

struct ResearchEvent: Codable {
    let schema: Int
    let kind: String
    let t: Double
    var sample: ResearchSample? = nil
    var candidateID: String? = nil
    var priority: String? = nil
    var noticeID: String? = nil
    var noticeText: String? = nil
    var activity: String? = nil
    var preference: String? = nil
    var useful: Bool? = nil
    var maxDelay: Double? = nil
}

@MainActor
final class ResearchSession: ObservableObject {
    @Published var running = false
    @Published var status = "尚未采集"
    @Published var sampleCount = 0
    @Published var latest: ResearchSample?
    @Published var candidate: String?
    @Published var candidateTime: Double?
    @Published var scenario = "coding"
    @Published var activity = "unknown"
    @Published var preference = "delay"
    @Published var useful = true
    @Published var maxDelay = 60.0
    @Published var priority = "ordinary"
    @Published var consent = false
    @Published var pending = false
    @Published var candidateDelay = 30.0
    @Published var candidateNotice: String?
    @Published var candidatePriority: String?
    @Published var labeledCount = 0
    @Published var fileURL: URL?
    private let sensor = SystemForegroundActivitySensor()
    private let fullscreenSensor = ForegroundFullscreenSensor()
    private var timer: Timer?
    private var pendingTask: Task<Void, Never>?
    private var handle: FileHandle?
    private var origin = ProcessInfo.processInfo.systemUptime
    private var lastApp: String?
    private var switches: [Double] = []
    private var stableSince = 0.0
    private var sessionDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["BUDDY_RESEARCH_DATA"] ?? NSTemporaryDirectory())
    }
    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - origin }

    func start() {
        guard consent, !running else { return }
        do {
            let directory = sessionDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Only delete our UUID-named session files, never unrelated files.
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
                guard url.lastPathComponent.hasPrefix("session-"), url.pathExtension == "jsonl",
                      UUID(uuidString: String(url.deletingPathExtension().lastPathComponent.dropFirst(8))) != nil else { continue }
                if let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   date.timeIntervalSinceNow < -7 * 86400 { try FileManager.default.removeItem(at: url) }
            }
            let url = directory.appendingPathComponent("session-\(UUID().uuidString).jsonl")
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: url)
            fileURL = url
            origin = ProcessInfo.processInfo.systemUptime
            switches = []; lastApp = nil; stableSince = 0; sampleCount = 0
            latest = nil; candidate = nil; candidateTime = nil
            candidateNotice = nil; candidatePriority = nil; labeledCount = 0
            running = true
            append(ResearchEvent(schema: 1, kind: "session_start", t: 0, activity: scenario))
            guard running else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.capture() }
            }
            status = "正在本地采集，每 2 秒一次。切回任务应用后开始实验。"
        } catch { status = "无法开始：\(error.localizedDescription)"; stop() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        pendingTask?.cancel(); pendingTask = nil; pending = false
        if running { append(ResearchEvent(schema: 1, kind: "session_end", t: elapsed)) }
        running = false
        try? handle?.close(); handle = nil
        latest = nil; lastApp = nil; switches = []
        if fileURL != nil { status = "已停止，记录保存在本地。" }
    }

    private func append(_ event: ResearchEvent) {
        do {
            var data = try JSONEncoder().encode(event); data.append(10)
            try handle?.write(contentsOf: data)
        } catch {
            timer?.invalidate(); timer = nil
            pendingTask?.cancel(); pendingTask = nil; pending = false
            running = false
            try? handle?.close(); handle = nil
            status = "写入失败，采集已停止：\(error.localizedDescription)"
        }
    }

    private func capture() {
        guard running else { return }
        let begin = ProcessInfo.processInfo.systemUptime
        let snapshot = sensor.currentSnapshot()
        let t = elapsed
        let own = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let app = own ? nil : snapshot.bundleIdentifier
        if app != lastApp {
            if app != nil && lastApp != nil { switches.append(t) }
            stableSince = t; lastApp = app
        }
        switches.removeAll { t - $0 >= 60 }
        let category: String
        if own { category = "research_console" }
        else if let work = WorkApplicationCategory.category(for: app) { category = work.rawValue }
        else if ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "company.thebrowser.Browser"].contains(app ?? "") { category = "browser" }
        else { category = "unknown" }
        // Geometry is an observation, not evidence of video playback.
        let full: Bool? = own ? nil : NSScreen.main.map { screen in
            let f = screen.frame
            let top = NSScreen.screens.first?.frame.maxY ?? f.maxY
            return fullscreenSensor.isForegroundApplicationFullscreen(on: DisplayGeometry(x: f.minX, y: top - f.maxY, width: f.width, height: f.height))
        }
        let idle = snapshot.secondsSinceLastInput.flatMap { $0 >= 0 && $0.isFinite ? min($0.rounded(), 3600) : nil }
        let sample = ResearchSample(t: t, category: category, idleSeconds: own ? nil : idle,
            fullscreen: full, switchCount: switches.count, stableSeconds: t - stableSince,
            sensingMS: (ProcessInfo.processInfo.systemUptime - begin) * 1000)
        latest = sample; sampleCount += 1
        append(ResearchEvent(schema: 1, kind: "sample", t: t, sample: sample))
    }

    func scheduleCandidate() {
        guard running, !pending, candidate == nil, candidateDelay.isFinite, (5...180).contains(candidateDelay) else { return }
        pending = true
        let selectedPriority = priority
        let delay = candidateDelay
        let noticeID = selectedPriority == "urgent" ? "simulated_critical_battery" : "optional_break"
        let noticeText = selectedPriority == "urgent"
            ? "Simulated critical battery: your battery is nearly empty. Please connect power."
            : "You have been working for a while. Would you like to take a short break?"
        status = "\(Int(delay)) 秒后记录候选，请切回任务。不会显示实际提醒。"
        pendingTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.running else { return }
            self.capture()
            guard self.running else { return }
            let id = UUID().uuidString
            self.candidate = id; self.candidateTime = self.elapsed
            self.candidateNotice = noticeText; self.candidatePriority = selectedPriority
            self.append(ResearchEvent(schema: 1, kind: "candidate", t: self.elapsed,
                candidateID: id, priority: selectedPriority, noticeID: noticeID, noticeText: noticeText))
            self.pending = false
            self.status = "候选已记录。任务段结束后，回到控制台标注刚才的时刻。"
        }
    }

    func label() {
        guard running, let id = candidate, maxDelay.isFinite, (0...3600).contains(maxDelay) else { return }
        append(ResearchEvent(schema: 1, kind: "label", t: elapsed, candidateID: id,
            activity: activity, preference: preference, useful: useful, maxDelay: maxDelay))
        labeledCount += 1
        candidate = nil; candidateTime = nil; candidateNotice = nil; candidatePriority = nil
        status = "标注已保存；活动和提醒偏好是你的自述，不是系统推断。"
    }

    func skipLabel() {
        guard running, let id = candidate else { return }
        append(ResearchEvent(schema: 1, kind: "label_skipped", t: elapsed, candidateID: id))
        candidate = nil; candidateTime = nil; candidateNotice = nil; candidatePriority = nil
        status = "已跳过。该候选保留，但不纳入有标签指标。"
    }

    func deleteCurrent() {
        stop()
        guard let url = fileURL else { return }
        do { try FileManager.default.removeItem(at: url); fileURL = nil; status = "本次记录已删除。" }
        catch { status = "删除失败：\(error.localizedDescription)" }
    }
}

struct ResearchView: View {
    @ObservedObject var session: ResearchSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Desktop Buddy · 研究控制台").font(.title2.bold())
                Text("评估轻量上下文与时间历史对提醒时机的影响。当前为影子模式，不向任务窗口投递提醒。")
                Text("只保存相对时间、粗应用类别、输入空闲秒数、窗口几何全屏判断及实验标签。无截图、标题、输入内容或云传输。原始应用 ID 仅用于内存中的切换判断。记录在下次启动采集时清理超过 7 天的实验文件；可立即删除。")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("我同意本次本地实验采集", isOn: $session.consent).disabled(session.running)
                Picker("本段计划场景（不是实际活动标签）", selection: $session.scenario) {
                    ForEach(["coding", "watching_video", "browsing", "idle_or_away", "rapid_switching", "ambiguous"], id: \.self) { Text($0) }
                }.disabled(session.running)
                HStack {
                    Button("开始采集") { session.start() }.disabled(!session.consent || session.running)
                    Button("停止") { session.stop() }.disabled(!session.running)
                    Button("查看记录") { if let url = session.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }.disabled(session.fileURL == nil)
                    Button("删除本次记录", role: .destructive) { session.deleteCurrent() }.disabled(session.fileURL == nil)
                }
                Text(session.status).foregroundStyle(.blue)
                Text("样本：\(session.sampleCount)；已标注：\(session.labeledCount)；当前：\(session.latest?.category ?? "unknown")")
                Text("控制台在前台时记为 research_console，政策按未知处理。全屏值是几何启发式；false 也可能受系统元数据可用性影响。无输入不等于离席，浏览器不等于看视频。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Picker("模拟通知优先级", selection: $session.priority) {
                    Text("普通").tag("ordinary"); Text("紧急").tag("urgent")
                }
                Text(session.priority == "urgent" ? "模拟提醒：电池即将耗尽，请连接电源（不是设备真实告警）。" : "模拟提醒：你已经工作了一段时间，要不要短暂休息？")
                    .font(.callout)
                Picker("记录候选前的等待时间", selection: $session.candidateDelay) {
                    Text("5 秒（调试）").tag(5.0)
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                    Text("180 秒（观察稳定任务）").tag(180.0)
                }.disabled(session.pending)
                Button(session.pending ? "等待候选记录…" : "预约一个测试候选") { session.scheduleCandidate() }
                    .disabled(!session.running || session.pending || session.candidate != nil)
                if let time = session.candidateTime {
                    Text("请标注会话第 \(Int(time)) 秒的候选时刻。若无法回忆，跳过本次标注。")
                    Text(session.candidateNotice ?? "").font(.callout.bold())
                    Text("优先级：\(session.candidatePriority ?? "unknown")")
                }
                Picker("当时实际活动", selection: $session.activity) {
                    ForEach(["unknown", "coding", "watching_video", "browsing", "idle_or_away"], id: \.self) { Text($0) }
                }
                Picker("当时希望怎样处理这个提醒", selection: $session.preference) {
                    Text("立即收到").tag("notify_now")
                    Text("延迟收到").tag("delay")
                    Text("不需要此提醒").tag("suppress")
                }
                Toggle("这个提醒对我有用", isOn: $session.useful)
                HStack {
                    Text("最长可接受延迟（秒）")
                    TextField("秒", value: $session.maxDelay, format: .number).frame(width: 80)
                }
                Button("保存该候选的标注") { session.label() }
                    .disabled(!session.running || session.candidate == nil || !session.maxDelay.isFinite || session.maxDelay < 0 || session.maxDelay > 3600)
                Button("无法回忆，跳过该候选") { session.skipLabel() }
                    .disabled(!session.running || session.candidate == nil)
                Text("停止前先保存或跳过待标注候选。此版本只测政策建议与模拟送达；不能据此宣称改善了真实中断体验。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(width: 680, height: 760)
    }
}

@main
struct ResearchConsole: App {
    @StateObject private var session = ResearchSession()
    var body: some Scene {
        WindowGroup { ResearchView(session: session).onDisappear { session.stop() } }
    }
}
