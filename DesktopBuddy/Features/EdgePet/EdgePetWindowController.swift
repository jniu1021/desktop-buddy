import AppKit
import CoreGraphics
import SwiftUI

enum EdgePetPlacementPolicy {
    static let margin: CGFloat = 12

    static func nearestEdge(to point: CGPoint, in frame: CGRect) -> PetScreenEdge {
        let distances: [(PetScreenEdge, CGFloat)] = [
            (.top, abs(frame.maxY - point.y)),
            (.right, abs(frame.maxX - point.x)),
            (.bottom, abs(point.y - frame.minY)),
            (.left, abs(point.x - frame.minX))
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    static func position(
        along edge: PetScreenEdge,
        nearest point: CGPoint,
        petSize: CGSize,
        in frame: CGRect
    ) -> Double {
        let horizontalRange = max(frame.width - petSize.width - margin * 2, 0)
        let verticalRange = max(frame.height - petSize.height - margin * 2, 0)
        let value: CGFloat

        switch edge {
        case .top, .bottom:
            value = horizontalRange > 0
                ? (point.x - petSize.width / 2 - frame.minX - margin) / horizontalRange
                : 0
        case .left, .right:
            value = verticalRange > 0
                ? (point.y - petSize.height / 2 - frame.minY - margin) / verticalRange
                : 0
        }
        return min(max(Double(value), 0), 1)
    }

    static func origin(
        edge: PetScreenEdge,
        position: Double,
        petSize: CGSize,
        in frame: CGRect
    ) -> CGPoint {
        let horizontalRange = max(frame.width - petSize.width - margin * 2, 0)
        let verticalRange = max(frame.height - petSize.height - margin * 2, 0)
        let horizontalPosition = frame.minX + margin + horizontalRange * CGFloat(position)
        let verticalPosition = frame.minY + margin + verticalRange * CGFloat(position)

        switch edge {
        case .top:
            return CGPoint(x: horizontalPosition, y: frame.maxY - petSize.height - margin)
        case .right:
            return CGPoint(x: frame.maxX - petSize.width - margin, y: verticalPosition)
        case .bottom:
            return CGPoint(x: horizontalPosition, y: frame.minY + margin)
        case .left:
            return CGPoint(x: frame.minX + margin, y: verticalPosition)
        }
    }
}

@MainActor
final class EdgePetWindowController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var wantsVisible: Bool
    @Published private(set) var isFullscreenSuppressed = false
    @Published private(set) var isFocusSuppressed = false
    @Published private(set) var scale: Double
    @Published private(set) var edge: PetScreenEdge
    var onPetClick: (() -> Void)?
    var onDisplayChanged: (() -> Void)?
    var visibleFrame: NSRect? { isVisible ? panel.frame : nil }
    var displayGeometry: DisplayGeometry? {
        guard let screen = currentScreen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else { return nil }
        let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        return DisplayGeometry(
            x: Double(bounds.origin.x),
            y: Double(bounds.origin.y),
            width: Double(bounds.width),
            height: Double(bounds.height)
        )
    }

    private let panel: NSPanel
    private let preferences: any PreferencesStoring
    private let presentation: EdgePetPresentationState
    private let petPresentation: PetPresentationStore
    private weak var animationPlayer: PetAnimationPlayer?
    private var edgePosition: Double
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var isDragging = false
    private var isTransitioning = false
    private var hasManualSuppressionOverride = false
    private var visibilityTask: Task<Void, Never>?

    init(
        store: BuddyStateStore,
        animationPlayer: PetAnimationPlayer,
        petPresentation: PetPresentationStore,
        preferences: any PreferencesStoring
    ) {
        let initialScale = min(max(preferences.edgePetScale, 0.75), 1.5)
        let initialPosition = min(max(preferences.edgePetEdgePosition, 0), 1)
        let initialEdge = preferences.edgePetEdge
        let presentation = EdgePetPresentationState(scale: initialScale, edge: initialEdge)

        self.animationPlayer = animationPlayer
        self.petPresentation = petPresentation
        self.preferences = preferences
        self.presentation = presentation
        self.scale = initialScale
        self.wantsVisible = preferences.edgePetVisible
        self.edge = initialEdge
        self.edgePosition = initialPosition
        self.panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: EdgePetLayout.windowSize(scale: initialScale)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(
            rootView: EdgePetView(
                store: store,
                animationPlayer: animationPlayer,
                presentation: presentation,
                petPresentation: petPresentation,
                onPetClick: { [weak self] in self?.onPetClick?() },
                onDragChanged: { [weak self] in self?.updateDrag() },
                onDragEnded: { [weak self] in self?.finishDrag() }
            )
        )
        installMouseMonitors()
    }

    func stop() {
        visibilityTask?.cancel()
        visibilityTask = nil
        hideImmediately()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            summon()
            return
        }
        wantsVisible = visible
        hasManualSuppressionOverride = false
        preferences.edgePetVisible = visible
        reconcileVisibility()
    }

    func summon() {
        wantsVisible = true
        hasManualSuppressionOverride = EdgePetVisibilityPolicy.manualOverrideForSummon(
            isFullscreenSuppressed: isFullscreenSuppressed,
            isFocusSuppressed: isFocusSuppressed
        )
        preferences.edgePetVisible = true
        reconcileVisibility()
    }

    func restoreVisibility() {
        reconcileVisibility()
    }

    func setFullscreenSuppressed(_ suppressed: Bool) {
        guard isFullscreenSuppressed != suppressed else { return }
        isFullscreenSuppressed = suppressed
        clearManualOverrideAfterSuppressionEnds()
        reconcileVisibility()
    }

    func setFocusSuppressed(_ suppressed: Bool) {
        guard isFocusSuppressed != suppressed else { return }
        isFocusSuppressed = suppressed
        clearManualOverrideAfterSuppressionEnds()
        reconcileVisibility()
    }

    private func reconcileVisibility() {
        if EdgePetVisibilityPolicy.shouldBeVisible(
            wantsVisible: wantsVisible,
            isFullscreenSuppressed: isFullscreenSuppressed,
            isFocusSuppressed: isFocusSuppressed,
            hasManualOverride: hasManualSuppressionOverride
        ) {
            if !isVisible { show() }
        } else if isVisible {
            hide()
        } else {
            petPresentation.handle(.edgeHidden(
                focusSuppressed: wantsVisible && isFocusSuppressed
            ))
        }
    }

    private func clearManualOverrideAfterSuppressionEnds() {
        if EdgePetVisibilityPolicy.shouldClearManualOverride(
            isFullscreenSuppressed: isFullscreenSuppressed,
            isFocusSuppressed: isFocusSuppressed
        ) {
            hasManualSuppressionOverride = false
        }
    }

    func setScale(_ newScale: Double) {
        let clampedScale = min(max(newScale, 0.75), 1.5)
        scale = clampedScale
        presentation.scale = clampedScale
        preferences.edgePetScale = clampedScale
        panel.setContentSize(EdgePetLayout.windowSize(scale: clampedScale))
        positionOnCurrentEdge()
        updateMousePassthrough()
    }

    func resetPosition() {
        edge = .right
        presentation.edge = edge
        edgePosition = 0.08
        preferences.edgePetEdge = edge
        preferences.edgePetEdgePosition = edgePosition
        positionOnCurrentEdge()
    }

    func show() {
        visibilityTask?.cancel()
        visibilityTask = nil
        positionOnCurrentEdge()
        let shouldAnimate = shouldAnimateTransition
        presentation.revealProgress = shouldAnimate ? 0 : 1
        panel.orderFrontRegardless()
        isVisible = true
        isTransitioning = shouldAnimate
        petPresentation.handle(.edgeShowStarted)

        guard shouldAnimate else {
            petPresentation.handle(.edgeShowCompleted)
            updateMousePassthrough()
            return
        }

        panel.ignoresMouseEvents = true
        visibilityTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: EdgePetTransitionPolicy.emergeDuration)) {
                self.presentation.revealProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.isTransitioning = false
            self.petPresentation.handle(.edgeShowCompleted)
            self.updateMousePassthrough()
        }
    }

    func hide() {
        visibilityTask?.cancel()
        visibilityTask = nil
        panel.ignoresMouseEvents = true
        isVisible = false
        petPresentation.handle(.edgeHideStarted)

        guard panel.isVisible, shouldAnimateTransition else {
            hideImmediately()
            return
        }

        isTransitioning = true
        withAnimation(.easeIn(duration: EdgePetTransitionPolicy.retreatDuration)) {
            presentation.revealProgress = 0
        }
        visibilityTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, !self.isVisible else { return }
            self.panel.orderOut(nil)
            self.isTransitioning = false
            self.petPresentation.handle(.edgeHidden(
                focusSuppressed: self.wantsVisible && self.isFocusSuppressed
            ))
        }
    }

    private func hideImmediately() {
        panel.orderOut(nil)
        panel.ignoresMouseEvents = true
        presentation.revealProgress = 0
        isVisible = false
        isTransitioning = false
        petPresentation.handle(.edgeHidden(
            focusSuppressed: wantsVisible && isFocusSuppressed
        ))
    }

    private var shouldAnimateTransition: Bool {
        guard let animationPlayer else { return false }
        return PetAnimationPolicy.shouldAnimate(
            animationsEnabled: animationPlayer.animationsEnabled,
            systemReduceMotionEnabled: animationPlayer.systemReduceMotionEnabled
        )
    }

    private func positionOnCurrentEdge() {
        guard let screen = currentScreen else { return }
        panel.setFrameOrigin(EdgePetPlacementPolicy.origin(
            edge: edge,
            position: edgePosition,
            petSize: panel.frame.size,
            in: screen.visibleFrame
        ))
    }

    private func updateDrag() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? currentScreen else { return }

        isDragging = true
        edge = EdgePetPlacementPolicy.nearestEdge(to: mouseLocation, in: screen.visibleFrame)
        presentation.edge = edge
        edgePosition = EdgePetPlacementPolicy.position(
            along: edge,
            nearest: mouseLocation,
            petSize: panel.frame.size,
            in: screen.visibleFrame
        )
        panel.setFrameOrigin(EdgePetPlacementPolicy.origin(
            edge: edge,
            position: edgePosition,
            petSize: panel.frame.size,
            in: screen.visibleFrame
        ))
        panel.ignoresMouseEvents = false
    }

    private func finishDrag() {
        isDragging = false
        preferences.edgePetEdge = edge
        preferences.edgePetEdgePosition = edgePosition
        updateMousePassthrough()
        onDisplayChanged?()
    }

    private var currentScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func installMouseMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.updateMousePassthrough() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor in self?.updateMousePassthrough() }
            return event
        }
    }

    private func updateMousePassthrough() {
        guard isVisible, let animationPlayer else {
            panel.ignoresMouseEvents = true
            return
        }
        guard !isDragging, !isTransitioning else {
            panel.ignoresMouseEvents = false
            return
        }

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !EdgePetLayout.containsInteractivePetRegion(
            at: windowPoint,
            frameIndex: animationPlayer.frameIndex,
            scale: scale
        )
    }
}
