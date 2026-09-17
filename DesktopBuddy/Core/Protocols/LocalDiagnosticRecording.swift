enum LocalDiagnosticSensor: String, Equatable, Sendable {
    case codexAllowance
}

enum LocalDiagnosticFailure: String, Equatable, Sendable {
    case executableMissing
    case processSetupFailed
    case processLaunchFailed
    case requestWriteFailed
    case timedOut
    case connectionClosed
    case responseTooLarge
    case invalidHandshake
    case unsupportedCapability
    case invalidPayload
}

enum LocalDiagnosticEvent: Equatable, Sendable {
    case applicationStarted
    case applicationStopped
    case recoveredFromUncleanExit
    case sensorFailure(sensor: LocalDiagnosticSensor, reason: LocalDiagnosticFailure)
}

protocol LocalDiagnosticRecording: Sendable {
    func record(_ event: LocalDiagnosticEvent)
}
