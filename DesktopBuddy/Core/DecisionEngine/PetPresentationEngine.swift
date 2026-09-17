enum PetPresentation: String, CaseIterable, Hashable, Sendable {
    case menuIdle = "MENU_IDLE"
    case emerging = "EMERGING"
    case edgeIdle = "EDGE_IDLE"
    case retreating = "RETREATING"
    case focusHidden = "FOCUS_HIDDEN"
    case deviceNotice = "DEVICE_NOTICE"
    case speaking = "SPEAKING"

    var accessibilityName: String {
        switch self {
        case .menuIdle: "Menu idle"
        case .emerging: "Pet emerging"
        case .edgeIdle: "Desktop pet idle"
        case .retreating: "Pet retreating"
        case .focusHidden: "Hidden for focused work"
        case .deviceNotice: "Device notice"
        case .speaking: "Pet speaking"
        }
    }
}

enum PetPresentationEvent: Equatable {
    case edgeShowStarted
    case edgeShowCompleted
    case edgeHideStarted
    case edgeHidden(focusSuppressed: Bool)
    case deviceNoticeStarted
    case speakingStarted
    case noticeEnded
}

struct PetPresentationEngine {
    private(set) var current: PetPresentation = .menuIdle
    private var base: PetPresentation = .menuIdle
    private var noticeIsActive = false

    mutating func handle(_ event: PetPresentationEvent) {
        switch event {
        case .edgeShowStarted:
            setBase(.emerging)
        case .edgeShowCompleted:
            setBase(.edgeIdle)
        case .edgeHideStarted:
            setBase(.retreating)
        case let .edgeHidden(focusSuppressed):
            setBase(focusSuppressed ? .focusHidden : .menuIdle)
        case .deviceNoticeStarted:
            noticeIsActive = true
            current = .deviceNotice
        case .speakingStarted:
            guard noticeIsActive else { return }
            current = .speaking
        case .noticeEnded:
            noticeIsActive = false
            current = base
        }
    }

    private mutating func setBase(_ presentation: PetPresentation) {
        base = presentation
        if !noticeIsActive {
            current = presentation
        }
    }
}
