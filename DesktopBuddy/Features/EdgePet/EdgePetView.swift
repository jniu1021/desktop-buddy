import SwiftUI

@MainActor
final class EdgePetPresentationState: ObservableObject {
    @Published var scale: Double
    @Published var edge: PetScreenEdge
    @Published var revealProgress: Double

    init(scale: Double, edge: PetScreenEdge, revealProgress: Double = 0) {
        self.scale = scale
        self.edge = edge
        self.revealProgress = revealProgress
    }
}

enum EdgePetTransitionPolicy {
    static let emergeDuration = 0.28
    static let retreatDuration = 0.22
    static let hiddenDistance: CGFloat = 34

    static func hiddenOffset(for edge: PetScreenEdge) -> CGSize {
        switch edge {
        case .top: return CGSize(width: 0, height: -hiddenDistance)
        case .right: return CGSize(width: hiddenDistance, height: 0)
        case .bottom: return CGSize(width: 0, height: hiddenDistance)
        case .left: return CGSize(width: -hiddenDistance, height: 0)
        }
    }
}

enum EdgePetLayout {
    static let basePixelSize: CGFloat = 8
    static let basePixelSpacing: CGFloat = 2
    static let padding: CGFloat = 10

    static func pixelSize(scale: Double) -> CGFloat {
        basePixelSize * CGFloat(scale)
    }

    static func pixelSpacing(scale: Double) -> CGFloat {
        basePixelSpacing * CGFloat(scale)
    }

    static func windowSize(scale: Double) -> CGSize {
        let pixelSize = pixelSize(scale: scale)
        let spacing = pixelSpacing(scale: scale)
        return CGSize(
            width: CGFloat(PixelPigSprite.width) * pixelSize
                + CGFloat(PixelPigSprite.width - 1) * spacing
                + padding * 2,
            height: CGFloat(PixelPigSprite.height) * pixelSize
                + CGFloat(PixelPigSprite.height - 1) * spacing
                + padding * 2
        )
    }

    /// The interactive silhouette includes rendered pixels plus the narrow grid
    /// spacing immediately beside them. Empty sprite cells and outer padding
    /// remain click-through so the transparent window does not block the desktop.
    static func containsInteractivePetRegion(
        at windowPoint: CGPoint,
        frameIndex: Int,
        scale: Double = 1
    ) -> Bool {
        let rows = PixelPigSprite.rows(frameIndex: frameIndex)
        let pixelSize = pixelSize(scale: scale)
        let spacing = pixelSpacing(scale: scale)
        let stride = pixelSize + spacing
        let size = windowSize(scale: scale)
        let localX = windowPoint.x - padding
        let localY = (size.height - windowPoint.y) - padding

        guard localX >= 0, localY >= 0 else { return false }

        let column = Int(localX / stride)
        let row = Int(localY / stride)
        guard column < PixelPigSprite.width, row < PixelPigSprite.height else { return false }

        var candidateColumns = [column]
        var candidateRows = [row]
        if localX.truncatingRemainder(dividingBy: stride) >= pixelSize,
           column + 1 < PixelPigSprite.width {
            candidateColumns.append(column + 1)
        }
        if localY.truncatingRemainder(dividingBy: stride) >= pixelSize,
           row + 1 < PixelPigSprite.height {
            candidateRows.append(row + 1)
        }

        return candidateRows.contains { candidateRow in
            candidateColumns.contains { candidateColumn in
                let spriteRow = rows[candidateRow]
                let index = spriteRow.index(spriteRow.startIndex, offsetBy: candidateColumn)
                return spriteRow[index] != "0"
            }
        }
    }

    static func centerOfPixel(column: Int, row: Int, scale: Double = 1) -> CGPoint {
        let pixelSize = pixelSize(scale: scale)
        let stride = pixelSize + pixelSpacing(scale: scale)
        let size = windowSize(scale: scale)
        return CGPoint(
            x: padding + CGFloat(column) * stride + pixelSize / 2,
            y: size.height - padding - CGFloat(row) * stride - pixelSize / 2
        )
    }
}

struct EdgePetView: View {
    @ObservedObject var store: BuddyStateStore
    @ObservedObject var animationPlayer: PetAnimationPlayer
    @ObservedObject var presentation: EdgePetPresentationState
    @ObservedObject var petPresentation: PetPresentationStore
    let onPetClick: () -> Void
    let onDragChanged: () -> Void
    let onDragEnded: () -> Void

    var body: some View {
        let hiddenOffset = EdgePetTransitionPolicy.hiddenOffset(for: presentation.edge)
        let hiddenAmount = CGFloat(1 - presentation.revealProgress)

        PixelPigView(
            severity: selectedSeverity,
            frameIndex: animationPlayer.frameIndex,
            pixelSize: EdgePetLayout.pixelSize(scale: presentation.scale),
            pixelSpacing: EdgePetLayout.pixelSpacing(scale: presentation.scale),
            palette: .desktop
        )
        .overlay(alignment: .topTrailing) {
            if petPresentation.current == .deviceNotice || animationPlayer.warningActive {
                PixelWarningMark()
                    .opacity(warningMarkOpacity)
                    .offset(x: 6, y: -8)
                    .accessibilityHidden(true)
            } else if petPresentation.current == .speaking {
                PixelSpeakingMark()
                    .offset(x: 9, y: -8)
                    .accessibilityHidden(true)
            }
        }
        .padding(EdgePetLayout.padding)
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .offset(
            x: hiddenOffset.width * hiddenAmount,
            y: hiddenOffset.height * hiddenAmount
        )
        .scaleEffect(CGFloat(0.92 + presentation.revealProgress * 0.08))
        .opacity(presentation.revealProgress)
        .onTapGesture(perform: onPetClick)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in onDragChanged() }
                .onEnded { _ in onDragEnded() }
        )
        .accessibilityLabel("Desktop pixel pig")
        .accessibilityValue(petPresentation.current.accessibilityName)
        .accessibilityHint("Click to open status, or drag toward any screen edge to move")
    }

    private var selectedSeverity: DeviceSeverity {
        switch store.selectedMetric {
        case .battery:
            return store.batteryState.condition.severity
        case .memoryUsage:
            return store.memoryUsageLevel.severity
        case .codexAllowance:
            return store.codexAllowanceState.condition.severity
        }
    }

    private var warningMarkOpacity: Double {
        let shouldAnimate = PetAnimationPolicy.shouldAnimate(
            animationsEnabled: animationPlayer.animationsEnabled,
            systemReduceMotionEnabled: animationPlayer.systemReduceMotionEnabled
        )
        guard shouldAnimate else { return 1 }
        return animationPlayer.frameIndex.isMultiple(of: 2) ? 1 : 0.32
    }
}

private struct PixelSpeakingMark: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .frame(width: 5, height: 5)
            }
        }
        .foregroundStyle(.primary)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct PixelWarningMark: View {
    var body: some View {
        VStack(spacing: 3) {
            Rectangle()
                .frame(width: 6, height: 19)
            Rectangle()
                .frame(width: 6, height: 6)
        }
        .foregroundStyle(.red)
        .shadow(color: .white.opacity(0.8), radius: 1)
    }
}
