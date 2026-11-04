import AppKit
@preconcurrency import ScreenCaptureKit
import Vision
import SwiftUI

struct ScreenActivityEvidence: Sendable {
    let activity: String
    let reason: String
    let textRegionCount: Int
    let elapsedMS: Double
}

enum ScreenActivityRules {
    static func infer(lines: [String]) -> (String, String) {
        let text = lines.joined(separator: "\n").lowercased()
        // Independent cue groups, deliberately conservative and not probabilities.
        let code = ["func ", "import ", "def ", "class ", "const ", "let ", "#include"].filter { text.contains($0) }.count
        let meeting = ["unmute", "participants", "leave meeting", "共享屏幕", "参会者"].filter { text.contains($0) }.count
        let video = ["playback", "subtitles", "播放速度", "字幕", "autoplay"].filter { text.contains($0) }.count
        let hits = [("coding", code >= 2), ("meeting", meeting >= 2), ("video", video >= 2)].filter { $0.1 }
        guard hits.count == 1 else { return ("unknown", hits.isEmpty ? "insufficient_screen_cues" : "conflicting_screen_cues") }
        return (hits[0].0, "experimental_text_cues")
    }
}

@MainActor
final class ScreenActivityProbe: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var status = "Screen analysis off"
    @Published private(set) var evidence: ScreenActivityEvidence?
    @Published private(set) var busy = false
    private var worker: Task<Void, Never>?
    private var generation = 0

    func enable() {
        guard #available(macOS 14.0, *) else { status = "Requires macOS 14 or later"; return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            status = "Screen permission not granted. Enable it in System Settings, then retry; a relaunch may be needed."
            return
        }
        enabled = true
        status = "Enabled. Samples only while diary is active; no images or recognized text are saved."
    }

    func disable() {
        enabled = false; generation += 1
        // Allow an in-flight OS capture to finish, but discard its result.
        evidence = nil; status = "Screen analysis off"
    }

    func invalidate() { generation += 1; evidence = nil }

    func sampleIfNeeded() {
        guard enabled, !busy else { return }
        guard #available(macOS 14.0, *) else { return }
        guard CGPreflightScreenCaptureAccess() else { disable(); status = "Screen permission unavailable"; return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = app.processIdentifier
        let token = generation
        busy = true
        worker = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.worker = nil }
            do {
                let start = ProcessInfo.processInfo.systemUptime
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard self.enabled, token == self.generation else { return }
                // Largest visible normal window of the current app. Not a semantic focused-window API.
                guard let window = content.windows.filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 })
                    .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                    self.evidence = nil; self.status = "No eligible window; activity unknown"; return
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let scale = min(1, 1280 / max(window.frame.width, window.frame.height))
                config.width = max(1, Int(window.frame.width * scale))
                config.height = max(1, Int(window.frame.height * scale))
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let result = try await Task.detached(priority: .utility) {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .fast
                    request.usesLanguageCorrection = false
                    // English-only fast baseline; multilingual accuracy is not established.
                    request.recognitionLanguages = ["en-US"]
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    let inferred = ScreenActivityRules.infer(lines: lines)
                    return ScreenActivityEvidence(activity: inferred.0, reason: inferred.1,
                        textRegionCount: lines.count, elapsedMS: (ProcessInfo.processInfo.systemUptime - start) * 1000)
                }.value
                guard self.enabled, token == self.generation,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.evidence = result
                self.status = "Tentative: \(result.activity) · \(Int(result.elapsedMS)) ms · \(result.reason)"
            } catch {
                guard self.enabled, token == self.generation else { return }
                self.evidence = nil
                // Do not expose an OS error that could include a window name.
                self.status = "Capture or analysis failed; activity unknown. No retry until next scheduled sample."
            }
        }
    }
}

struct ScreenActivityCard: View {
    @ObservedObject var probe: ScreenActivityProbe
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen evidence · experimental").font(.caption.bold())
            Text("Optional: briefly captures the largest visible window of the foreground app and reads on-screen text locally. May include sensitive content. Images and recognized text stay in memory, are not saved or uploaded. Fast English text rules are unvalidated; results do not update activity totals.")
                .font(.caption).foregroundStyle(.secondary)
            if probe.enabled {
                Button("Disable screen analysis") { probe.disable() }
            } else {
                Button("Enable screen analysis…") { confirm = true }
            }
            Text(probe.status).font(.caption)
            Text("At most one analysis at a time. 30-second sampling; 120 seconds in Low Power Mode. Requires the local diary to be enabled. No microphone or audio capture.")
                .font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Allow local window capture and text analysis? macOS will request Screen Recording access. No capture starts until the diary is enabled.", isPresented: $confirm) {
            Button("Continue to system permission") { probe.enable() }
        }
    }
}
