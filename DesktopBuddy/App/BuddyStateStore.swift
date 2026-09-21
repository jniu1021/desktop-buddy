import Combine
import Foundation

@MainActor
final class BuddyStateStore: ObservableObject {
    @Published private(set) var batteryState: BatteryState = .unavailable
    @Published private(set) var memoryUsageState: MemoryUsageState = .unavailable
    @Published private(set) var memoryUsageLevel: MemoryUsageLevel = .normal
    @Published private(set) var codexAllowanceState: CodexAllowanceState = .notConfigured
    @Published private(set) var fanReadoutState: FanReadoutState = .unavailable
    @Published private(set) var lastUpdatedAt: Date?
    @Published var onboardingCompleted: Bool {
        didSet { preferences.onboardingCompleted = onboardingCompleted }
    }
    @Published var selectedMetric: StatusMetric {
        didSet { preferences.selectedMetric = selectedMetric }
    }
    @Published var interactionMode: InteractionMode {
        didSet { preferences.interactionMode = interactionMode }
    }
    @Published var focusSuppressionEnabled: Bool {
        didSet { preferences.focusSuppressionEnabled = focusSuppressionEnabled }
    }
    @Published var applicationActivityEnabled: Bool {
        didSet { preferences.applicationActivityEnabled = applicationActivityEnabled }
    }
    @Published var codexIntegrationEnabled: Bool {
        didSet {
            preferences.codexIntegrationEnabled = codexIntegrationEnabled
            if codexIntegrationEnabled {
                startCodexPolling()
            } else {
                codexTask?.cancel()
                codexTask = nil
                codexAllowanceState = .notConfigured
                if selectedMetric == .codexAllowance { selectedMetric = .battery }
            }
        }
    }

    private let batterySensor: any BatterySensing
    private let memoryUsageSensor: any MemoryUsageSensing
    private let codexAllowanceSensor: any CodexAllowanceSensing
    private let fanSensor: any FanSensing
    private let lowPowerModeEnabled: @Sendable () -> Bool
    private let preferences: any PreferencesStoring
    private var refreshTask: Task<Void, Never>?
    private var memoryUsageTask: Task<Void, Never>?
    private var codexTask: Task<Void, Never>?
    private var lastCodexRefreshStartedAt: Date?
    private var memoryUsageClassifier = MemoryUsageLevelClassifier()
    private var memorySamplingIntervalGate = MemorySamplingIntervalGate()

    init(
        batterySensor: any BatterySensing,
        memoryUsageSensor: any MemoryUsageSensing,
        codexAllowanceSensor: any CodexAllowanceSensing,
        fanSensor: any FanSensing,
        lowPowerModeEnabled: @escaping @Sendable () -> Bool,
        preferences: any PreferencesStoring
    ) {
        self.batterySensor = batterySensor
        self.memoryUsageSensor = memoryUsageSensor
        self.codexAllowanceSensor = codexAllowanceSensor
        self.fanSensor = fanSensor
        self.lowPowerModeEnabled = lowPowerModeEnabled
        self.preferences = preferences
        self.onboardingCompleted = preferences.onboardingCompleted
        self.selectedMetric = preferences.codexIntegrationEnabled
            ? preferences.selectedMetric
            : (preferences.selectedMetric == .codexAllowance ? .battery : preferences.selectedMetric)
        self.interactionMode = preferences.interactionMode
        self.focusSuppressionEnabled = preferences.focusSuppressionEnabled
        self.applicationActivityEnabled = preferences.applicationActivityEnabled
        self.codexIntegrationEnabled = preferences.codexIntegrationEnabled
    }

    func start() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()

                guard let self, !Task.isCancelled else { return }
                let cadence = self.currentPollingCadence

                do {
                    try await Task.sleep(for: cadence.deviceRefreshDelay)
                } catch {
                    return
                }
            }
        }

        memoryUsageTask = Task { [weak self] in
            guard let self else { return }

            for await state in memoryUsageSensor.stateUpdates() {
                guard !Task.isCancelled else { return }
                applyMemoryUsage(state, now: Date())
            }
        }
        startCodexPolling()
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        memoryUsageTask?.cancel()
        memoryUsageTask = nil
        codexTask?.cancel()
        codexTask = nil
    }

    func refresh() async {
        async let batteryState = batterySensor.currentState()
        async let memoryUsageState = memoryUsageSensor.currentState()

        self.batteryState = await batteryState
        applyMemorySamplingCadence()
        applyMemoryUsage(await memoryUsageState, now: Date())
    }

    func refreshCodexAllowance(
        trigger: CodexRefreshTrigger = .manual,
        now: Date = Date()
    ) async {
        guard codexIntegrationEnabled else { return }
        guard CodexRefreshPolicy.shouldRefresh(
            for: trigger,
            lastRefreshStartedAt: lastCodexRefreshStartedAt,
            now: now
        ) else { return }
        lastCodexRefreshStartedAt = now
        if codexAllowanceState.primary == nil {
            codexAllowanceState = .loading
        }
        let state = await codexAllowanceSensor.currentAllowance()
        guard !Task.isCancelled, codexIntegrationEnabled else { return }
        codexAllowanceState = state
    }

    func refreshFanReadings() async {
        fanReadoutState = await fanSensor.currentState()
    }

    private func startCodexPolling() {
        guard refreshTask != nil, codexIntegrationEnabled, codexTask == nil else { return }
        codexTask = Task { [weak self] in
            var backoff = CodexPollingBackoff()
            var trigger = CodexRefreshTrigger.startupOrResume
            while !Task.isCancelled {
                await self?.refreshCodexAllowance(trigger: trigger)
                guard let self, self.codexIntegrationEnabled, !Task.isCancelled else { return }
                let delay = backoff.nextDelay(after: self.codexAllowanceState.availability)
                trigger = .scheduled
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func applyMemoryUsage(_ state: MemoryUsageState, now: Date) {
        memoryUsageState = state
        if state.isAvailable {
            memoryUsageLevel = memoryUsageClassifier.update(
                usageFraction: state.usageFraction,
                now: now
            )
        }
        lastUpdatedAt = now
    }

    private var currentPollingCadence: DevicePollingCadence {
        DevicePollingPolicy.cadence(
            powerSource: batteryState.powerSource,
            lowPowerModeEnabled: lowPowerModeEnabled()
        )
    }

    private func applyMemorySamplingCadence() {
        let requestedInterval = currentPollingCadence.memorySampleIntervalSeconds
        guard let interval = memorySamplingIntervalGate.intervalToApply(requestedInterval) else {
            return
        }
        memoryUsageSensor.setSamplingInterval(seconds: interval)
    }
}
