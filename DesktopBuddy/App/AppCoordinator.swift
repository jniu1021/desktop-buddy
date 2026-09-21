import AppKit
import Combine
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSPopoverDelegate {
    private let stateStore: BuddyStateStore
    private let fullscreenSensor: any FullscreenSensing
    private let foregroundActivitySensor: any ForegroundActivitySensing
    private let focusActivity = FocusActivityStore()
    private let animationPlayer: PetAnimationPlayer
    private let petPresentation: PetPresentationStore
    private let alphaMetrics: AlphaMetricsTracker
    private let diagnostics: any LocalDiagnosticRecording
    private let sessionLifecycle: any SessionLifecyclePersisting
    private let launchRecoveryAction: LaunchRecoveryAction
    private let edgePetController: EdgePetWindowController
    private let pendingNotices = PendingNoticeStore()
    private let noticeBubble = NoticeBubbleWindowController()
    private var noticeDetector = DeviceNoticeDetector()
    private var noticeEligibilityCoordinator = NoticeEligibilityCoordinator()
    private var isForegroundFullscreen = false
    private var focusTask: Task<Void, Never>?
    private var fullscreenTask: Task<Void, Never>?
    private var noticePresentationTask: Task<Void, Never>?
    private var codexLifecycleRefreshTask: Task<Void, Never>?
    private var runtimeLifecycleState: RuntimeLifecycleState = .active
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(container: DependencyContainer) {
        let stateStore = BuddyStateStore(
            batterySensor: container.batterySensor,
            memoryUsageSensor: container.memoryUsageSensor,
            codexAllowanceSensor: container.codexAllowanceSensor,
            fanSensor: container.fanSensor,
            lowPowerModeEnabled: container.lowPowerModeEnabled,
            preferences: container.preferences
        )
        let animationPlayer = PetAnimationPlayer(preferences: container.preferences)
        let petPresentation = PetPresentationStore()
        let alphaMetrics = AlphaMetricsTracker(repository: container.alphaMetrics)

        self.stateStore = stateStore
        self.fullscreenSensor = container.fullscreenSensor
        self.foregroundActivitySensor = container.foregroundActivitySensor
        self.animationPlayer = animationPlayer
        self.petPresentation = petPresentation
        self.alphaMetrics = alphaMetrics
        self.diagnostics = container.diagnostics
        self.sessionLifecycle = container.sessionLifecycle
        self.launchRecoveryAction = LaunchRecoveryPolicy.action(
            previousSessionWasActive: container.sessionLifecycle.isSessionActive
        )
        self.edgePetController = EdgePetWindowController(
            store: stateStore,
            animationPlayer: animationPlayer,
            petPresentation: petPresentation,
            preferences: container.preferences
        )
        super.init()
    }

    func start() {
        sessionLifecycle.isSessionActive = true
        diagnostics.record(.applicationStarted)
        if launchRecoveryAction == .startWithEdgePetHidden {
            diagnostics.record(.recoveredFromUncleanExit)
        }
        edgePetController.onPetClick = { [weak self] in
            self?.togglePopover()
        }
        edgePetController.onDisplayChanged = { [weak self] in
            self?.updateFullscreenSuppression()
        }
        alphaMetrics.startSession()
        configureStatusItem()
        configurePopover()
        observeState()
        observeEnvironment()
        observeFocusSuppression()
        observeActivityConsent()
        updateFullscreenSuppression()
        startFullscreenSampling()
        reconcileActivityConsent()
        edgePetController.restoreVisibility(
            allowAutomaticRestore: launchRecoveryAction == .restoreNormally
        )
        stateStore.start()
        animationPlayer.start()
    }

    func stop() {
        diagnostics.record(.applicationStopped)
        focusTask?.cancel()
        focusTask = nil
        fullscreenTask?.cancel()
        fullscreenTask = nil
        noticePresentationTask?.cancel()
        noticePresentationTask = nil
        codexLifecycleRefreshTask?.cancel()
        codexLifecycleRefreshTask = nil
        alphaMetrics.stopSession()
        stateStore.stop()
        animationPlayer.stop()
        edgePetController.stop()
        noticeBubble.hide()
        sessionLifecycle.isSessionActive = false
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        updateStatusItem(metric: .battery, batteryState: .unavailable)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.delegate = self
    }

    private func installPopoverContentIfNeeded() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NSHostingController(
            rootView: StatusPanelView(
                store: stateStore,
                animationPlayer: animationPlayer,
                edgePetController: edgePetController,
                pendingNotices: pendingNotices,
                focusActivity: focusActivity,
                alphaMetrics: alphaMetrics
            )
        )
    }

    private func observeState() {
        let deviceState = Publishers.CombineLatest4(
            stateStore.$selectedMetric,
            stateStore.$batteryState,
            stateStore.$memoryUsageState,
            stateStore.$memoryUsageLevel
        )

        Publishers.CombineLatest4(
            deviceState,
            stateStore.$codexAllowanceState,
            animationPlayer.$frameIndex,
            petPresentation.$current
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] state, codexAllowanceState, frameIndex, presentation in
                let (metric, batteryState, memoryUsageState, memoryUsageLevel) = state
                let selectedSeverity = switch metric {
                case .battery: batteryState.condition.severity
                case .memoryUsage: memoryUsageLevel.severity
                case .codexAllowance: codexAllowanceState.condition.severity
                }
                self?.animationPlayer.setWarningActive(selectedSeverity == .critical)
                self?.updateStatusItem(
                    metric: metric,
                    batteryState: batteryState,
                    memoryUsageState: memoryUsageState,
                    memoryUsageLevel: memoryUsageLevel,
                    codexAllowanceState: codexAllowanceState,
                    frameIndex: frameIndex,
                    presentation: presentation
                )
            }
            .store(in: &subscriptions)

        stateStore.$batteryState
            .receive(on: RunLoop.main)
            .sink { [weak self] batteryState in
                guard let self else { return }
                if let notice = self.noticeDetector.updateBattery(batteryState, now: Date()) {
                    self.handle(notice)
                }
            }
            .store(in: &subscriptions)

        Publishers.CombineLatest(stateStore.$memoryUsageState, stateStore.$memoryUsageLevel)
            .receive(on: RunLoop.main)
            .sink { [weak self] memoryState, level in
                guard let self else { return }
                if let notice = self.noticeDetector.updateMemory(memoryState, level: level, now: Date()) {
                    self.handle(notice)
                }
            }
            .store(in: &subscriptions)
    }

    private func handle(_ notice: DeviceNotice) {
        guard pendingNotices.enqueue(notice) else { return }
        updateFullscreenSuppression()
        updateFocusInference()

        let now = Date()
        if notice.kind.isOrdinary {
            let eligibility = noticeEligibilityCoordinator.evaluate(
                mode: stateStore.interactionMode,
                now: now,
                evidence: notice.evidence,
                isFocusSuppressed: stateStore.focusSuppressionEnabled
                    && focusActivity.isPossiblyFocused
            )
            guard eligibility == .eligible else { return }
        }

        guard FullscreenPresentationPolicy.shouldShowBubble(
            isFullscreen: isForegroundFullscreen,
            isFocused: stateStore.focusSuppressionEnabled && focusActivity.isPossiblyFocused
        ) else { return }
        petPresentation.handle(.deviceNoticeStarted)
        let wasPresented: Bool
        if let petFrame = edgePetController.visibleFrame {
            wasPresented = showNoticeBubble(notice, beside: petFrame, edge: edgePetController.edge)
        } else if let button = statusItem.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            wasPresented = showNoticeBubble(notice, beside: buttonFrame, edge: .top)
        } else {
            wasPresented = false
        }
        if !wasPresented {
            petPresentation.handle(.noticeEnded)
        }
        if wasPresented && notice.kind.isOrdinary {
            noticeEligibilityCoordinator.recordOrdinaryNoticeShown(at: now)
        }
        if wasPresented {
            alphaMetrics.recordNoticeShown(id: notice.id)
        }
    }

    private func showNoticeBubble(
        _ notice: DeviceNotice,
        beside frame: NSRect,
        edge: PetScreenEdge
    ) -> Bool {
        noticePresentationTask?.cancel()
        noticePresentationTask = nil
        let wasShown = noticeBubble.show(notice, beside: frame, edge: edge) { [weak self] in
            self?.noticePresentationTask?.cancel()
            self?.noticePresentationTask = nil
            self?.petPresentation.handle(.noticeEnded)
        }
        guard wasShown else { return false }

        noticePresentationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.petPresentation.handle(.speakingStarted)
        }
        return true
    }

    private func observeEnvironment() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard let self, self.stateStore.applicationActivityEnabled else { return }
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                self.focusActivity.noteForegroundApplication(application?.bundleIdentifier)
            }
            .store(in: &subscriptions)

        Publishers.Merge(
            center.publisher(for: NSWorkspace.didActivateApplicationNotification),
            center.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateFullscreenSuppression()
        }
        .store(in: &subscriptions)

        center.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                self?.handleRuntimeLifecycle(.systemWillSleep)
            }
            .store(in: &subscriptions)

        center.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.handleRuntimeLifecycle(.systemDidWake)
            }
            .store(in: &subscriptions)

        center.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                self?.refreshCodexAfterScreenWake()
            }
            .store(in: &subscriptions)
    }

    private func observeFocusSuppression() {
        Publishers.CombineLatest(
            focusActivity.$isPossiblyFocused,
            stateStore.$focusSuppressionEnabled
        )
        .map { $0 && $1 }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] isSuppressed in
            self?.edgePetController.setFocusSuppressed(isSuppressed)
            if isSuppressed { self?.noticeBubble.hide() }
        }
        .store(in: &subscriptions)
    }

    private func observeActivityConsent() {
        stateStore.$applicationActivityEnabled
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconcileActivityConsent()
            }
            .store(in: &subscriptions)
    }

    private func handleRuntimeLifecycle(_ event: RuntimeLifecycleEvent) {
        let transition = RuntimeLifecyclePolicy.transition(
            from: runtimeLifecycleState,
            event: event
        )
        runtimeLifecycleState = transition.state

        switch transition.action {
        case .suspend:
            diagnostics.record(.systemWillSleep)
            focusTask?.cancel()
            focusTask = nil
            fullscreenTask?.cancel()
            fullscreenTask = nil
            noticePresentationTask?.cancel()
            noticePresentationTask = nil
            codexLifecycleRefreshTask?.cancel()
            codexLifecycleRefreshTask = nil
            noticeBubble.hide()
            stateStore.stop()
            animationPlayer.stop()
        case .resume:
            diagnostics.record(.systemDidWake)
            stateStore.start()
            animationPlayer.start()
            updateFullscreenSuppression()
            startFullscreenSampling()
            reconcileActivityConsent()
        case nil:
            break
        }
    }

    private func refreshCodexAfterScreenWake() {
        guard runtimeLifecycleState == .active else { return }
        codexLifecycleRefreshTask?.cancel()
        codexLifecycleRefreshTask = Task { [weak self] in
            await self?.stateStore.refreshCodexAllowance(trigger: .screenWake)
        }
    }

    private func reconcileActivityConsent() {
        guard runtimeLifecycleState == .active else { return }

        if stateStore.applicationActivityEnabled {
            updateFocusInference()
            startFocusSampling()
        } else {
            focusTask?.cancel()
            focusTask = nil
            focusActivity.reset()
            edgePetController.setFocusSuppressed(false)
        }
    }

    private func startFocusSampling() {
        guard runtimeLifecycleState == .active,
              stateStore.applicationActivityEnabled,
              focusTask == nil else { return }
        focusTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                self?.updateFocusInference()
            }
        }
    }

    private func updateFocusInference() {
        guard stateStore.applicationActivityEnabled else { return }
        focusActivity.update(foregroundActivitySensor.currentSnapshot())
    }

    private func startFullscreenSampling() {
        guard runtimeLifecycleState == .active, fullscreenTask == nil else { return }
        fullscreenTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: FullscreenPollingPolicy.refreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.updateFullscreenSuppression()
            }
        }
    }

    private func updateFullscreenSuppression() {
        let fullscreen = edgePetController.displayGeometry.map {
            fullscreenSensor.isForegroundApplicationFullscreen(on: $0)
        } ?? false
        guard fullscreen != isForegroundFullscreen else { return }
        isForegroundFullscreen = fullscreen
        edgePetController.setFullscreenSuppressed(fullscreen)
        if fullscreen { noticeBubble.hide() }
    }

    private func updateStatusItem(
        metric: StatusMetric = .battery,
        batteryState: BatteryState,
        memoryUsageState: MemoryUsageState = .unavailable,
        memoryUsageLevel: MemoryUsageLevel = .normal,
        codexAllowanceState: CodexAllowanceState = .notConfigured,
        frameIndex: Int = 0,
        presentation: PetPresentation = .menuIdle
    ) {
        guard let button = statusItem.button else { return }

        switch metric {
        case .battery:
            button.image = MenuBarPetRenderer.image(
                for: batteryState.condition.severity,
                frameIndex: frameIndex,
                presentation: presentation
            )
            button.toolTip = batteryState.chargePercent.map { "Desktop Buddy — Battery \($0)%" }
                ?? "Desktop Buddy — Battery unavailable"
        case .memoryUsage:
            button.image = MenuBarPetRenderer.image(
                for: memoryUsageLevel.severity,
                frameIndex: frameIndex,
                presentation: presentation
            )
            button.toolTip = memoryUsageState.isAvailable
                ? "Desktop Buddy — Memory \(memoryUsageState.usagePercent)%"
                : "Desktop Buddy — Memory unavailable"
        case .codexAllowance:
            button.image = MenuBarPetRenderer.image(
                for: codexAllowanceState.condition.severity,
                frameIndex: frameIndex,
                presentation: presentation
            )
            button.toolTip = codexAllowanceState.primary.map {
                "Desktop Buddy — Codex \($0.remainingPercent)% left (\($0.label) window)"
            } ?? "Desktop Buddy — Codex unavailable"
        }

        button.setAccessibilityLabel(MenuBarStatusAccessibility.label(
            metric: metric,
            battery: batteryState,
            memory: memoryUsageState,
            memoryLevel: memoryUsageLevel,
            codex: codexAllowanceState,
            presentation: presentation
        ))
        button.setAccessibilityHelp("Open the status panel")
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        pendingNotices.expire()
        alphaMetrics.recordMetricGlance(stateStore.selectedMetric)
        alphaMetrics.recordActionForPendingNotices(ids: pendingNotices.notices.map(\.id))
        installPopoverContentIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}
