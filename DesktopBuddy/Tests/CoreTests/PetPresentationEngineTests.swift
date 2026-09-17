import XCTest
@testable import DesktopBuddy

final class PetPresentationEngineTests: XCTestCase {
    func testEveryApprovedPresentationStateIsReachable() {
        var engine = PetPresentationEngine()
        var reached: Set<PetPresentation> = [engine.current]

        for event in [
            PetPresentationEvent.edgeShowStarted,
            .edgeShowCompleted,
            .edgeHideStarted,
            .edgeHidden(focusSuppressed: true),
            .deviceNoticeStarted,
            .speakingStarted,
            .noticeEnded,
            .edgeHidden(focusSuppressed: false)
        ] {
            engine.handle(event)
            reached.insert(engine.current)
        }

        XCTAssertEqual(reached, Set(PetPresentation.allCases))
    }

    func testNoticeOverlayRestoresLatestUnderlyingTransitionState() {
        var engine = PetPresentationEngine()
        engine.handle(.edgeShowStarted)
        engine.handle(.deviceNoticeStarted)
        engine.handle(.speakingStarted)
        engine.handle(.edgeShowCompleted)

        XCTAssertEqual(engine.current, .speaking)
        engine.handle(.noticeEnded)
        XCTAssertEqual(engine.current, .edgeIdle)

        engine.handle(.deviceNoticeStarted)
        engine.handle(.edgeHideStarted)
        engine.handle(.edgeHidden(focusSuppressed: true))
        engine.handle(.noticeEnded)
        XCTAssertEqual(engine.current, .focusHidden)
    }

    func testSpeakingRequiresAnActiveNotice() {
        var engine = PetPresentationEngine()
        engine.handle(.speakingStarted)
        XCTAssertEqual(engine.current, .menuIdle)
    }

    func testEveryStateHasADistinctIntentionalAccessibilityPath() {
        let names = PetPresentation.allCases.map(\.accessibilityName)
        XCTAssertEqual(Set(names).count, PetPresentation.allCases.count)
    }
}
