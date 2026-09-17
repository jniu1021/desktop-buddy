import Foundation

@MainActor
struct DependencyContainer {
    let batterySensor: any BatterySensing
    let memoryUsageSensor: any MemoryUsageSensing
    let fullscreenSensor: any FullscreenSensing
    let foregroundActivitySensor: any ForegroundActivitySensing
    let codexAllowanceSensor: any CodexAllowanceSensing
    let fanSensor: any FanSensing
    let lowPowerModeEnabled: @Sendable () -> Bool
    let preferences: any PreferencesStoring
    let alphaMetrics: any AlphaMetricsPersisting
    let diagnostics: any LocalDiagnosticRecording
    let sessionLifecycle: any SessionLifecyclePersisting

    static func live() -> DependencyContainer {
        let diagnostics = OSLogDiagnosticRecorder()
        return DependencyContainer(
            batterySensor: SystemBatterySensor(),
            memoryUsageSensor: SystemMemoryUsageSensor(),
            fullscreenSensor: ForegroundFullscreenSensor(),
            foregroundActivitySensor: SystemForegroundActivitySensor(),
            codexAllowanceSensor: CodexAppServerAllowanceSensor(
                executableURL: CodexExecutableLocator.locate(),
                diagnostics: diagnostics
            ),
            fanSensor: SystemFanSensor(),
            lowPowerModeEnabled: { ProcessInfo.processInfo.isLowPowerModeEnabled },
            preferences: UserDefaultsPreferencesStore(),
            alphaMetrics: UserDefaultsAlphaMetricsRepository(),
            diagnostics: diagnostics,
            sessionLifecycle: UserDefaultsSessionLifecycleRepository()
        )
    }
}
