import AppKit
@preconcurrency import ScreenCaptureKit
@preconcurrency import SoundAnalysis
import AVFoundation
import SwiftUI

struct AudioCue: Sendable {
    let category: String
    let modelScore: Double
}

enum AudioCueRules {
    static func coarse(_ identifier: String, score: Double) -> String {
        guard score.isFinite, score >= 0.6 else { return "unknown" }
        if ["speech", "conversation", "narration", "monologue"].contains(identifier) { return "speech" }
        if identifier == "music" || identifier.hasSuffix("_music") { return "music" }
        return "other_sound"
    }
}

/// Mutable analyzer is confined to `queue`; callback results cross threads under a lock.
private final class AudioAnalysisSink: NSObject, SCStreamOutput, SNResultsObserving, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.desktopbuddy.audio-analysis", qos: .utility)
    private var analyzer: SNAudioStreamAnalyzer?
    private var offset: AVAudioFramePosition = 0
    private let lock = NSLock()
    private var lastCue: AudioCue?
    private var failed = false

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, count <= 48000,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        pcm.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList) == noErr else { return }
        do {
            if analyzer == nil {
                let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48000)
                request.overlapFactor = 0
                let next = SNAudioStreamAnalyzer(format: format)
                try next.add(request, withObserver: self)
                analyzer = next
            }
            analyzer?.analyze(pcm, atAudioFramePosition: offset)
            offset += AVAudioFramePosition(count)
        } catch { lock.lock(); failed = true; lock.unlock() }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first else { return }
        let cue = AudioCue(category: AudioCueRules.coarse(top.identifier, score: top.confidence), modelScore: top.confidence)
        lock.lock(); lastCue = cue; lock.unlock()
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock(); failed = true; lock.unlock()
    }
    func requestDidComplete(_ request: SNRequest) {}

    func finish() async -> (AudioCue?, Bool) {
        await withCheckedContinuation { continuation in
            queue.async {
                self.analyzer?.completeAnalysis()
                self.analyzer = nil
                self.lock.lock()
                let result = (self.lastCue, self.failed)
                self.lock.unlock()
                continuation.resume(returning: result)
            }
        }
    }
}

@MainActor
final class SystemAudioProbe: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    private(set) var cue: AudioCue?
    private(set) var observedAt: Date?
    @Published private(set) var status = "System audio off"
    private var generation = 0
    private var stream: SCStream?
    private var worker: Task<Void, Never>?

    func enable() {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            status = "System capture permission not granted. Enable in System Settings, then retry; relaunch may be required."
            return
        }
        enabled = true
        status = "Enabled; waits for an active diary sample. No microphone access."
    }
    func disable() { enabled = false; invalidate(); status = "System audio off" }
    func invalidate() {
        generation += 1
        cue = nil; observedAt = nil
        worker?.cancel()
        status = enabled ? "Paused; old audio evidence discarded" : "System audio off"
    }

    func sampleIfNeeded() {
        guard enabled, !busy else { return }
        guard CGPreflightScreenCaptureAccess() else { disable(); status = "Capture permission unavailable"; return }
        let token = generation
        busy = true
        status = "Analyzing a 5-second playback sample locally…"
        worker = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.worker = nil }
            var captured: SCStream?
            let sink = AudioAnalysisSink()
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard self.enabled, token == self.generation, !Task.isCancelled else { return }
                guard let display = content.displays.first else { self.status = "No display capture source"; return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(seconds: 5, preferredTimescale: 1)
                config.queueDepth = 3
                config.capturesAudio = true
                config.sampleRate = 16000; config.channelCount = 1
                config.excludesCurrentProcessAudio = true
                if #available(macOS 15.0, *) { config.captureMicrophone = false }
                let capture = SCStream(filter: filter, configuration: config, delegate: nil)
                captured = capture
                self.stream = capture
                // Only audio output is registered; no screen frames are consumed or saved.
                try capture.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
                try await capture.startCapture()
                try await Task.sleep(for: .seconds(5))
                try await capture.stopCapture()
                captured = nil; self.stream = nil
                let (cue, failed) = await sink.finish()
                guard self.enabled, token == self.generation, !Task.isCancelled else { return }
                if failed { self.cue = nil; self.observedAt = nil; self.status = "Audio analysis unavailable; unknown" }
                else if let cue {
                    self.cue = cue; self.observedAt = Date()
                    self.status = "Last playback cue: \(cue.category). Model score \(String(format: "%.2f", cue.modelScore)); not activity confidence."
                } else { self.cue = nil; self.observedAt = nil; self.status = "No classified audio received; not proof of silence or absence." }
            } catch {
                if let captured { try? await captured.stopCapture() }
                self.stream = nil
                _ = await sink.finish()
                guard self.enabled, token == self.generation else { return }
                self.status = "Playback capture or analysis failed; unknown."
            }
        }
    }
}

struct SystemAudioCard: View {
    @ObservedObject var probe: SystemAudioProbe
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback sound · experimental").font(.caption.bold())
            Text("Optional: analyzes 5 seconds of computer playback at most once per minute, or every 3 minutes in Low Power Mode. Includes audio from other apps; excludes this app. No microphone, transcription, saved audio or uploads. macOS may call this Screen Recording permission because the capture uses ScreenCaptureKit.")
                .font(.caption).foregroundStyle(.secondary)
            if probe.enabled {
                Button("Disable playback analysis") { probe.disable() }
            } else {
                Button("Enable playback analysis…") { confirm = true }
            }
            Text(probe.status).font(.caption)
            Text("Speech can be a video or a call; music may be background listening. These cues do not update confirmed activity totals. Sampling misses sounds between bursts.")
                .font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Allow brief local analysis of all computer playback? No microphone or audio files. Requires the diary to be active.", isPresented: $confirm) {
            Button("Continue to system permission") { probe.enable() }
        }
    }
}
