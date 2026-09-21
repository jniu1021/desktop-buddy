import XCTest
@testable import DesktopBuddy

final class MenuBarStatusAccessibilityTests: XCTestCase {
    func testPresentationOverlaysStayInsidePigSilhouette() {
        let rows = PixelPigSprite.rows(frameIndex: 0)

        for presentation in PetPresentation.allCases {
            for pixel in MenuBarPetRenderer.presentationOverlayPixels(for: presentation) {
                XCTAssertTrue(rows.indices.contains(pixel.row))
                guard rows.indices.contains(pixel.row) else { continue }
                let row = rows[pixel.row]
                XCTAssertGreaterThanOrEqual(pixel.column, 0)
                XCTAssertLessThan(pixel.column, row.count)
                guard pixel.column >= 0, pixel.column < row.count else { continue }
                let index = row.index(row.startIndex, offsetBy: pixel.column)
                XCTAssertNotEqual(row[index], "0", "\(presentation) overlay escaped the pig")
            }
        }
    }

    func testMemoryAnnouncesUsageAndDisplayedWarning() {
        let memory = MemoryUsageState(
            usedBytes: 85, totalBytes: 100, compressedBytes: 0,
            swapUsedBytes: 0, swapOutBytesPerSecond: 0, systemPressure: .normal
        )
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .memoryUsage, battery: .unavailable, memory: memory,
            memoryLevel: .high, codex: .notConfigured
        ), "Desktop Buddy. Memory 85 percent used, high. Menu idle.")
    }

    func testCodexAnnouncesPrimaryWindowSeverityAndUnavailableState() {
        let codex = CodexAllowanceState(
            availability: .available,
            primary: CodexQuotaWindow(usedPercent: 86, durationMinutes: 300, resetsAt: nil),
            secondary: CodexQuotaWindow(usedPercent: 0, durationMinutes: 10_080, resetsAt: nil),
            updatedAt: nil
        )
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .codexAllowance, battery: .unavailable, memory: .unavailable,
            memoryLevel: .normal, codex: codex
        ), "Desktop Buddy. Codex 5-hour allowance 14 percent left, critical remaining. Menu idle.")
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .codexAllowance, battery: .unavailable, memory: .unavailable,
            memoryLevel: .normal, codex: .notConfigured
        ), "Desktop Buddy. Codex allowance unavailable. Menu idle.")
    }

    func testBatteryAnnouncesCriticalAndUnavailable() {
        let battery = BatteryState(
            chargePercent: 9, isCharging: false, powerSource: .battery, condition: .critical
        )
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .battery, battery: battery, memory: .unavailable,
            memoryLevel: .normal, codex: .notConfigured
        ), "Desktop Buddy. Battery 9 percent, critical. Menu idle.")
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .battery, battery: .unavailable, memory: .unavailable,
            memoryLevel: .normal, codex: .notConfigured
        ), "Desktop Buddy. Battery unavailable. Menu idle.")
    }

    func testBatteryAnnouncesEstimatedUsageLeftWhenAvailable() {
        let battery = BatteryState(
            chargePercent: 53,
            isCharging: false,
            powerSource: .battery,
            condition: .normal,
            estimatedUsageSeconds: 7_500
        )

        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .battery, battery: battery, memory: .unavailable,
            memoryLevel: .normal, codex: .notConfigured
        ), "Desktop Buddy. Battery estimated usage left 2 hours 5 minutes, 53 percent, normal. Menu idle.")
    }

    func testPresentationStateIsIncludedInTheSpokenMenuStatus() {
        XCTAssertEqual(MenuBarStatusAccessibility.label(
            metric: .battery, battery: .unavailable, memory: .unavailable,
            memoryLevel: .normal, codex: .notConfigured, presentation: .speaking
        ), "Desktop Buddy. Battery unavailable. Pet speaking.")
    }
}
