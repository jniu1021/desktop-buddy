import Foundation
import XCTest
@testable import DesktopBuddy

@MainActor
final class CodexAllowanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private final class DiagnosticRecorder: LocalDiagnosticRecording, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedEvents: [LocalDiagnosticEvent] = []

        var events: [LocalDiagnosticEvent] {
            lock.withLock { recordedEvents }
        }

        func record(_ event: LocalDiagnosticEvent) {
            lock.withLock { recordedEvents.append(event) }
        }
    }

    func testDecoderPrefersCodexBucketAndKeepsBothWindows() {
        let payload = """
        {
          "rateLimits": { "primary": { "usedPercent": 99 } },
          "rateLimitsByLimitId": {
            "codex": {
              "primary": { "usedPercent": 26, "windowDurationMins": 300, "resetsAt": 1789493907 },
              "secondary": { "usedPercent": 41, "windowDurationMins": 10080, "resetsAt": 1789831036 }
            }
          }
        }
        """
        let state = CodexAllowanceDecoder.decodeResult(Data(payload.utf8), now: now)

        XCTAssertEqual(state?.availability, .available)
        XCTAssertEqual(state?.primary?.remainingPercent, 74)
        XCTAssertEqual(state?.secondary?.remainingPercent, 59)
        XCTAssertEqual(state?.primary?.label, "5-hour")
        XCTAssertEqual(state?.secondary?.label, "Weekly")
        XCTAssertEqual(state?.condition, .normal)
    }

    func testFiveHourRemainingStrictColorThresholdsAndWeeklyIndependence() {
        func state(used: Double, weeklyUsed: Double = 0) -> CodexAllowanceState? {
            CodexAllowanceDecoder.decodeResult(
                Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(used)},\"secondary\":{\"usedPercent\":\(weeklyUsed)}}}".utf8),
                now: now
            )
        }

        XCTAssertEqual(state(used: 60, weeklyUsed: 100)?.condition, .normal)
        XCTAssertEqual(state(used: 60.01)?.condition, .low)
        XCTAssertEqual(state(used: 85)?.condition, .low)
        XCTAssertEqual(state(used: 85.01)?.condition, .exhausted)
        XCTAssertEqual(state(used: 100)?.condition, .exhausted)
        XCTAssertEqual(state(used: 60.01)?.condition.severity, .caution)
        XCTAssertEqual(state(used: 85.01)?.condition.severity, .critical)

        let low = CodexAllowanceDecoder.decodeResult(
            Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":80}}}".utf8),
            now: now
        )
        XCTAssertEqual(low?.condition, .low)
        XCTAssertEqual(low?.primary?.remainingPercent, 20)
    }

    func testMissingPercentIsUnavailableNotZeroUsage() {
        XCTAssertNil(CodexAllowanceDecoder.decodeResult(
            Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":null}}}".utf8),
            now: now
        ))
        XCTAssertNil(CodexAllowanceDecoder.decodeResult(Data("{}".utf8), now: now))
    }

    func testAppServerMessagesDeclareJSONRPCVersion() {
        let request = CodexAppServerProtocol.request(
            method: "initialize",
            id: 1,
            params: ["clientInfo": ["name": "desktop_buddy"]]
        )
        let notification = CodexAppServerProtocol.notification(
            method: "initialized",
            params: [:]
        )

        XCTAssertEqual(request["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(request["method"] as? String, "initialize")
        XCTAssertEqual(request["id"] as? Int, 1)
        XCTAssertEqual(notification["jsonrpc"] as? String, "2.0")
        XCTAssertNil(notification["id"])
    }

    func testHandshakeDetectsServerVersionAndPlatform() {
        let profile = CodexAppServerProtocol.serverProfile(from: [
            "userAgent": "Codex Desktop/0.154.0-alpha.6.2 (Mac OS; arm64)",
            "platformFamily": "unix",
            "platformOs": "macos"
        ])

        XCTAssertEqual(profile?.version, "0.154.0-alpha.6.2")
        XCTAssertEqual(profile?.platformFamily, "unix")
        XCTAssertEqual(profile?.platformOS, "macos")
        XCTAssertNil(CodexAppServerProtocol.serverProfile(from: [
            "userAgent": "Codex Desktop/0.154.0",
            "platformFamily": "unix"
        ]))
    }

    func testRateLimitCapabilityRequiresExpectedResultShape() {
        XCTAssertTrue(CodexAppServerProtocol.supportsRateLimits(in: [
            "id": 2,
            "result": ["rateLimits": ["primary": ["usedPercent": 10]]]
        ]))
        XCTAssertFalse(CodexAppServerProtocol.supportsRateLimits(in: [
            "id": 2,
            "error": ["code": -32601, "message": "Method not found"]
        ]))
        XCTAssertFalse(CodexAppServerProtocol.supportsRateLimits(in: [
            "id": 2,
            "result": [:]
        ]))
    }

    func testAdapterEscalatesPastSIGTERMAndHonorsOuterTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("ignore-term.sh")
        try """
        #!/bin/sh
        trap '' TERM
        while read ignored; do :; done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let diagnostics = DiagnosticRecorder()
        let sensor = CodexAppServerAllowanceSensor(
            executableURL: executable,
            diagnostics: diagnostics,
            timeout: 0.1,
            terminationGrace: 0.05
        )
        let startedAt = Date()
        let state = await sensor.currentAllowance()

        XCTAssertEqual(state.availability, .unavailable)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
        XCTAssertEqual(diagnostics.events.count, 1)
        guard case let .sensorFailure(sensor, _) = try XCTUnwrap(diagnostics.events.first) else {
            return XCTFail("Expected a bounded sensor failure event")
        }
        XCTAssertEqual(sensor, .codexAllowance)
    }

    func testMissingExecutableRecordsPrivacyBoundedFailure() async {
        let diagnostics = DiagnosticRecorder()
        let sensor = CodexAppServerAllowanceSensor(
            executableURL: nil,
            diagnostics: diagnostics
        )

        let state = await sensor.currentAllowance()

        XCTAssertEqual(state.availability, .executableMissing)
        XCTAssertEqual(diagnostics.events, [
            .sensorFailure(sensor: .codexAllowance, reason: .executableMissing)
        ])
    }

    func testLiveAdapterOnlyWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["DESKTOP_BUDDY_LIVE_CODEX_TEST"] == "1" else {
            throw XCTSkip("Live Codex account read is opt-in")
        }
        guard let executableURL = CodexExecutableLocator.locate() else {
            throw XCTSkip("Codex CLI not installed")
        }
        let sensor = CodexAppServerAllowanceSensor(
            executableURL: executableURL,
            diagnostics: DiagnosticRecorder()
        )
        let state = await sensor.currentAllowance()
        XCTAssertEqual(state.availability, .available)
        XCTAssertNotNil(state.primary)
    }
}
