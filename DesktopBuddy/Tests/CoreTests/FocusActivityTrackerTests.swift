import XCTest
@testable import DesktopBuddy

final class FocusActivityTrackerTests: XCTestCase {
    func testKnownCategoryStillNeedsSustainedActivity() {
        var tracker = FocusActivityTracker()
        for second in stride(from: 0, through: 300, by: 10) {
            let focused = tracker.update(snapshot("com.apple.dt.Xcode", idle: 5), now: time(second))
            XCTAssertEqual(focused, second == 300)
        }
        XCTAssertFalse(tracker.update(snapshot("com.apple.dt.Xcode", idle: 60), now: time(310)))
    }

    func testSingleRecentInputAfterLongIdleIsNotEnough() {
        var tracker = FocusActivityTracker()
        XCTAssertFalse(tracker.update(snapshot("com.apple.dt.Xcode", idle: 5), now: time(0)))
        XCTAssertFalse(tracker.update(snapshot("com.apple.dt.Xcode", idle: 5), now: time(300)))
    }

    func testRapidSwitchingBetweenKnownWorkAppsBlocksFocus() {
        var tracker = FocusActivityTracker()
        for second in stride(from: 0, through: 410, by: 10) {
            let bundleID: String
            switch second {
            case 100:
                bundleID = "com.openai.codex"
            case 150:
                bundleID = "com.apple.dt.Xcode"
            case 200:
                bundleID = "com.openai.codex"
            default:
                bundleID = second < 100 || (150..<200).contains(second)
                    ? "com.apple.dt.Xcode" : "com.openai.codex"
            }
            let focused = tracker.update(snapshot(bundleID, idle: 5), now: time(second))
            if second == 310 { XCTAssertFalse(focused) }
            if second == 410 { XCTAssertTrue(focused) }
        }
    }

    func testUnknownApplicationNeverProvesFocus() {
        var tracker = FocusActivityTracker()
        for second in stride(from: 0, through: 360, by: 10) {
            XCTAssertFalse(tracker.update(snapshot("com.google.Chrome", idle: 5), now: time(second)))
        }
        XCTAssertTrue(WorkApplicationCategory.isKnownWorkApplication("com.jetbrains.intellij"))
        XCTAssertFalse(WorkApplicationCategory.isKnownWorkApplication("com.google.Chrome"))
    }

    func testClassifierCoversMultipleWorkFamiliesWithoutAssumingBrowsersOrChat() {
        XCTAssertEqual(WorkApplicationCategory.category(for: "dev.zed.Zed"), .development)
        XCTAssertEqual(WorkApplicationCategory.category(for: "com.apple.Terminal"), .terminal)
        XCTAssertEqual(WorkApplicationCategory.category(for: "md.obsidian"), .writing)
        XCTAssertEqual(WorkApplicationCategory.category(for: "com.figma.Desktop"), .design)
        XCTAssertEqual(WorkApplicationCategory.category(for: "com.microsoft.Excel"), .office)
        XCTAssertNil(WorkApplicationCategory.category(for: "com.google.Chrome"))
        XCTAssertNil(WorkApplicationCategory.category(for: "com.tinyspeck.slackmacgap"))
    }

    func testJetBrainsPrefixRequiresTheBundleComponentBoundary() {
        XCTAssertEqual(
            WorkApplicationCategory.category(for: "com.jetbrains.intellij"),
            .development
        )
        XCTAssertNil(WorkApplicationCategory.category(for: "com.jetbrainsfake.editor"))
    }

    func testRecognizedWritingApplicationCanProveFocus() {
        var tracker = FocusActivityTracker()
        for second in stride(from: 0, through: 300, by: 10) {
            tracker.update(snapshot("md.obsidian", idle: 5), now: time(second))
        }
        XCTAssertTrue(tracker.isPossiblyFocused)
    }

    func testRevokingActivityConsentClearsRollingFocusEvidence() {
        var tracker = FocusActivityTracker()
        for second in stride(from: 0, through: 300, by: 10) {
            tracker.update(snapshot("com.apple.dt.Xcode", idle: 5), now: time(second))
        }
        XCTAssertTrue(tracker.isPossiblyFocused)

        tracker.reset()

        XCTAssertFalse(tracker.isPossiblyFocused)
        XCTAssertFalse(tracker.update(snapshot("com.apple.dt.Xcode", idle: 5), now: time(310)))
    }

    private func snapshot(_ bundleID: String, idle: TimeInterval) -> ForegroundActivitySnapshot {
        ForegroundActivitySnapshot(bundleIdentifier: bundleID, secondsSinceLastInput: idle)
    }

    private func time(_ second: Int) -> Date {
        Date(timeIntervalSince1970: 1_000_000 + Double(second))
    }
}
