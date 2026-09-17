import XCTest
@testable import DesktopBuddy

final class PetAnimationPolicyTests: XCTestCase {
    func testAnimationRequiresUserAndSystemPermission() {
        XCTAssertTrue(
            PetAnimationPolicy.shouldAnimate(
                animationsEnabled: true,
                systemReduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            PetAnimationPolicy.shouldAnimate(
                animationsEnabled: false,
                systemReduceMotionEnabled: false
            )
        )
        XCTAssertFalse(
            PetAnimationPolicy.shouldAnimate(
                animationsEnabled: true,
                systemReduceMotionEnabled: true
            )
        )
    }

    func testEarAnimationAdvancesThroughFourFrames() {
        XCTAssertEqual(PetAnimationPolicy.nextEarFrame(after: 0), 1)
        XCTAssertEqual(PetAnimationPolicy.nextEarFrame(after: 1), 2)
        XCTAssertEqual(PetAnimationPolicy.nextEarFrame(after: 3), 0)
    }

    func testEarAnimationPausesAtRestingFrame() {
        XCTAssertEqual(PetAnimationPolicy.delay(after: 0), .milliseconds(1_800))
        XCTAssertEqual(PetAnimationPolicy.delay(after: 1), .milliseconds(160))
        XCTAssertEqual(PetAnimationPolicy.delay(after: 3), .milliseconds(160))
    }

    func testCriticalWarningUsesFasterButStillBoundedCadence() {
        XCTAssertEqual(
            PetAnimationPolicy.delay(after: 0, warningActive: true),
            .milliseconds(420)
        )
        XCTAssertEqual(
            PetAnimationPolicy.delay(after: 1, warningActive: true),
            .milliseconds(120)
        )
    }

    func testPixelPigFramesHaveStableDimensionsAndFacialDetails() {
        let restingRows = PixelPigSprite.rows(frameIndex: 0)
        let leftEarRows = PixelPigSprite.rows(frameIndex: 1)
        let loweredEarRows = PixelPigSprite.rows(frameIndex: 2)

        XCTAssertEqual(restingRows.count, PixelPigSprite.height)
        XCTAssertTrue(restingRows.allSatisfy { $0.count == PixelPigSprite.width })
        XCTAssertTrue(restingRows.contains { $0.contains("2") })
        XCTAssertTrue(restingRows.contains { $0.contains("3") })
        XCTAssertTrue(restingRows.contains { $0.contains("4") })
        XCTAssertTrue(restingRows.contains { $0.contains("5") })
        XCTAssertNotEqual(restingRows, leftEarRows)
        XCTAssertNotEqual(leftEarRows, loweredEarRows)
    }

    func testCanvasKeepsGridDimensionsAtStatusAndDesktopSizes() {
        XCTAssertEqual(PixelPigCanvasLayout.size(pixelSize: 7, pixelSpacing: 2),
                       CGSize(width: 142, height: 115))

        for scale in [0.75, 1.0, 1.5] {
            let size = PixelPigCanvasLayout.size(
                pixelSize: EdgePetLayout.pixelSize(scale: scale),
                pixelSpacing: EdgePetLayout.pixelSpacing(scale: scale)
            )
            XCTAssertEqual(size.width + EdgePetLayout.padding * 2,
                           EdgePetLayout.windowSize(scale: scale).width)
            XCTAssertEqual(size.height + EdgePetLayout.padding * 2,
                           EdgePetLayout.windowSize(scale: scale).height)
        }
    }

    func testEdgePetHitRegionIncludesAdjacentGridSpacingButNotTransparentCells() {
        let visibleEar = EdgePetLayout.centerOfPixel(column: 0, row: 0)
        let transparentCenter = EdgePetLayout.centerOfPixel(column: 7, row: 0)
        let bodyPixel = EdgePetLayout.centerOfPixel(column: 0, row: 4)
        let gapBesideBodyPixel = CGPoint(
            x: bodyPixel.x + EdgePetLayout.pixelSize(scale: 1) / 2 + 1,
            y: bodyPixel.y
        )

        XCTAssertTrue(EdgePetLayout.containsInteractivePetRegion(at: visibleEar, frameIndex: 0))
        XCTAssertFalse(EdgePetLayout.containsInteractivePetRegion(at: transparentCenter, frameIndex: 0))
        XCTAssertTrue(EdgePetLayout.containsInteractivePetRegion(at: bodyPixel, frameIndex: 0))
        XCTAssertTrue(EdgePetLayout.containsInteractivePetRegion(at: gapBesideBodyPixel, frameIndex: 0))
        XCTAssertFalse(EdgePetLayout.containsInteractivePetRegion(at: visibleEar, frameIndex: 1))
    }

    func testEdgePetOuterPaddingAndEmptyGridSpacingRemainClickThrough() {
        let size = EdgePetLayout.windowSize(scale: 1)
        let transparentGridGap = CGPoint(
            x: EdgePetLayout.padding + EdgePetLayout.pixelSize(scale: 1) + 1,
            y: size.height - EdgePetLayout.padding - EdgePetLayout.pixelSize(scale: 1) / 2
        )

        XCTAssertFalse(
            EdgePetLayout.containsInteractivePetRegion(
                at: CGPoint(x: 1, y: size.height / 2),
                frameIndex: 0
            )
        )
        XCTAssertFalse(
            EdgePetLayout.containsInteractivePetRegion(
                at: transparentGridGap,
                frameIndex: 2
            )
        )
    }

    func testEdgePetHitRegionScalesWithPet() {
        let largeSnout = EdgePetLayout.centerOfPixel(column: 7, row: 8, scale: 1.5)

        XCTAssertTrue(
            EdgePetLayout.containsInteractivePetRegion(
                at: largeSnout,
                frameIndex: 0,
                scale: 1.5
            )
        )
        XCTAssertEqual(EdgePetLayout.windowSize(scale: 1.5).width, 257)
    }

    func testEdgePetSelectsAndPositionsOnAllFourEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let pet = CGSize(width: 180, height: 150)

        XCTAssertEqual(EdgePetPlacementPolicy.nearestEdge(to: CGPoint(x: 500, y: 790), in: screen), .top)
        XCTAssertEqual(EdgePetPlacementPolicy.nearestEdge(to: CGPoint(x: 990, y: 400), in: screen), .right)
        XCTAssertEqual(EdgePetPlacementPolicy.nearestEdge(to: CGPoint(x: 500, y: 5), in: screen), .bottom)
        XCTAssertEqual(EdgePetPlacementPolicy.nearestEdge(to: CGPoint(x: 4, y: 400), in: screen), .left)

        XCTAssertEqual(
            EdgePetPlacementPolicy.origin(edge: .top, position: 0.5, petSize: pet, in: screen).y,
            638
        )
        XCTAssertEqual(
            EdgePetPlacementPolicy.origin(edge: .left, position: 0.5, petSize: pet, in: screen).x,
            12
        )
    }

    func testEdgePetTransitionsMoveTowardTheirScreenEdge() {
        XCTAssertEqual(EdgePetTransitionPolicy.hiddenOffset(for: .top), CGSize(width: 0, height: -34))
        XCTAssertEqual(EdgePetTransitionPolicy.hiddenOffset(for: .right), CGSize(width: 34, height: 0))
        XCTAssertEqual(EdgePetTransitionPolicy.hiddenOffset(for: .bottom), CGSize(width: 0, height: 34))
        XCTAssertEqual(EdgePetTransitionPolicy.hiddenOffset(for: .left), CGSize(width: -34, height: 0))
    }
}
