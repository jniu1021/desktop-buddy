import AppKit
import Darwin
import Foundation

@MainActor
enum CodexExecutableLocator {
    static func locate() -> URL? {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        return candidateURLs(appURL: appURL)
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    static func candidateURLs(appURL: URL?) -> [URL] {
        var candidates = appURL.map { appURL in
            [
                appURL.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"),
                appURL.appendingPathComponent("Contents/Resources/codex")
            ]
        } ?? []
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ])
        return candidates
    }
}

struct CodexAppServerAllowanceSensor: CodexAllowanceSensing {
    let executableURL: URL?
    let diagnostics: any LocalDiagnosticRecording
    let timeout: TimeInterval
    let terminationGrace: TimeInterval

    init(
        executableURL: URL?,
        diagnostics: any LocalDiagnosticRecording,
        timeout: TimeInterval = 8,
        terminationGrace: TimeInterval = 0.25
    ) {
        self.executableURL = executableURL
        self.diagnostics = diagnostics
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    func currentAllowance() async -> CodexAllowanceState {
        guard let executableURL else {
            diagnostics.record(.sensorFailure(
                sensor: .codexAllowance,
                reason: .executableMissing
            ))
            return .unavailable(.executableMissing)
        }
        return await Task.detached(priority: .utility) {
            Self.readAllowance(
                executableURL: executableURL,
                diagnostics: diagnostics,
                timeout: timeout,
                terminationGrace: terminationGrace
            )
        }.value
    }

    private static func readAllowance(
        executableURL: URL,
        diagnostics: any LocalDiagnosticRecording,
        timeout: TimeInterval,
        terminationGrace: TimeInterval
    ) -> CodexAllowanceState {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        // A failed child write must return EPIPE instead of terminating the pet.
        func unavailable(_ reason: LocalDiagnosticFailure) -> CodexAllowanceState {
            diagnostics.record(.sensorFailure(sensor: .codexAllowance, reason: reason))
            return .unavailable(.unavailable)
        }

        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            return unavailable(.processSetupFailed)
        }

        do {
            try process.run()
        } catch {
            return unavailable(.processLaunchFailed)
        }

        let stopper = TimedCodexProcess(process, terminationGrace: terminationGrace)
        let timeoutWorkItem = DispatchWorkItem {
            stopper.stop()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + max(0, timeout),
            execute: timeoutWorkItem
        )
        defer {
            timeoutWorkItem.cancel()
            stopper.stop()
        }

        func send(_ object: [String: Any]) -> Bool {
            guard let payload = try? JSONSerialization.data(withJSONObject: object) else { return false }
            do {
                try input.fileHandleForWriting.write(contentsOf: payload + Data([0x0A]))
                return true
            } catch {
                return false
            }
        }

        guard send(CodexAppServerProtocol.request(
            method: "initialize",
            id: 1,
            params: ["clientInfo": [
                "name": "desktop_buddy",
                "title": "Desktop Buddy",
                "version": "0.1.0"
            ]]
        )) else { return unavailable(.requestWriteFailed) }

        var buffer = Data()
        let outputDescriptor = output.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 4096)
        let deadline = DispatchTime.now().uptimeNanoseconds
            &+ UInt64(max(0, timeout) * 1_000_000_000)
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return unavailable(.timedOut) }
            let remainingMilliseconds = Int32(min(
                UInt64(Int32.max),
                max(1, (deadline - now) / 1_000_000)
            ))
            var descriptor = pollfd(
                fd: outputDescriptor,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            )
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)
            if pollResult < 0 && errno == EINTR { continue }
            if pollResult == 0 { return unavailable(.timedOut) }
            guard pollResult > 0 else { return unavailable(.connectionClosed) }

            let count = bytes.withUnsafeMutableBytes { storage in
                Darwin.read(outputDescriptor, storage.baseAddress, storage.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return unavailable(.connectionClosed) }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 1_000_000 else { return unavailable(.responseTooLarge) }

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = (message["id"] as? NSNumber)?.intValue else { continue }

                if id == 1 {
                    guard let result = message["result"],
                          CodexAppServerProtocol.serverProfile(from: result) != nil
                    else { return unavailable(.invalidHandshake) }
                    guard send(CodexAppServerProtocol.notification(
                            method: "initialized",
                            params: [:]
                          )),
                          send(CodexAppServerProtocol.request(
                            method: "account/rateLimits/read",
                            id: 2
                          ))
                    else { return unavailable(.requestWriteFailed) }
                } else if id == 2 {
                    guard CodexAppServerProtocol.supportsRateLimits(in: message)
                    else { return unavailable(.unsupportedCapability) }
                    guard let result = message["result"],
                          let data = try? JSONSerialization.data(withJSONObject: result),
                          let allowance = CodexAllowanceDecoder.decodeResult(data, now: Date())
                    else { return unavailable(.invalidPayload) }
                    return allowance
                }
            }
        }
    }
}

enum CodexAppServerProtocol {
    struct ServerProfile: Equatable {
        let userAgent: String
        let version: String?
        let platformFamily: String
        let platformOS: String
    }

    static func request(
        method: String,
        id: Int,
        params: [String: Any]? = nil
    ) -> [String: Any] {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": id
        ]
        if let params { message["params"] = params }
        return message
    }

    static func notification(method: String, params: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
    }

    static func serverProfile(from result: Any) -> ServerProfile? {
        guard let result = result as? [String: Any],
              let userAgent = nonemptyString(result["userAgent"]),
              let platformFamily = nonemptyString(result["platformFamily"]),
              let platformOS = nonemptyString(result["platformOs"])
        else { return nil }

        let version = userAgent.split(whereSeparator: \Character.isWhitespace)
            .compactMap { component -> String? in
                let pieces = component.split(separator: "/", maxSplits: 1)
                guard pieces.count == 2, !pieces[1].isEmpty else { return nil }
                return String(pieces[1])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }
            .first

        return ServerProfile(
            userAgent: userAgent,
            version: version,
            platformFamily: platformFamily,
            platformOS: platformOS
        )
    }

    static func supportsRateLimits(in response: [String: Any]) -> Bool {
        guard response["error"] == nil,
              let result = response["result"] as? [String: Any]
        else { return false }
        return result["rateLimits"] != nil || result["rateLimitsByLimitId"] != nil
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }
}

private final class TimedCodexProcess: @unchecked Sendable {
    private let process: Process
    private let terminationGrace: TimeInterval
    private let condition = NSCondition()
    private var isStopping = false
    private var isStopped = false

    init(_ process: Process, terminationGrace: TimeInterval) {
        self.process = process
        self.terminationGrace = terminationGrace
    }

    func stop() {
        condition.lock()
        while isStopping && !isStopped { condition.wait() }
        guard !isStopped else {
            condition.unlock()
            return
        }
        isStopping = true
        condition.unlock()

        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(max(0, terminationGrace))
            while process.isRunning && Date() < deadline {
                usleep(10_000)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }

        condition.lock()
        isStopped = true
        isStopping = false
        condition.broadcast()
        condition.unlock()
    }
}
