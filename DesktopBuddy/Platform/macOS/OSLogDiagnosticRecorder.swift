import OSLog

struct OSLogDiagnosticRecorder: LocalDiagnosticRecording {
    private static let logger = Logger(
        subsystem: "com.desktopbuddy.app",
        category: "local-diagnostics"
    )

    func record(_ event: LocalDiagnosticEvent) {
        switch event {
        case .applicationStarted:
            Self.logger.notice("application_started")
        case .applicationStopped:
            Self.logger.notice("application_stopped")
        case .recoveredFromUncleanExit:
            Self.logger.warning("recovered_from_unclean_exit edge_pet_auto_restore_suppressed=true")
        case .systemWillSleep:
            Self.logger.notice("system_will_sleep runtime_sampling_suspended=true")
        case .systemDidWake:
            Self.logger.notice("system_did_wake runtime_sampling_resumed=true")
        case let .sensorFailure(sensor, reason):
            Self.logger.error(
                "sensor_failure sensor=\(sensor.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public)"
            )
        }
    }
}
