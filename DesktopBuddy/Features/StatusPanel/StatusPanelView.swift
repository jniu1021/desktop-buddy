import Foundation
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var store: BuddyStateStore
    @ObservedObject var animationPlayer: PetAnimationPlayer
    @ObservedObject var edgePetController: EdgePetWindowController
    @ObservedObject var pendingNotices: PendingNoticeStore
    @ObservedObject var focusActivity: FocusActivityStore
    @ObservedObject var alphaMetrics: AlphaMetricsTracker
    @State private var isMemoryDetailsExpanded = false
    @State private var showsPetSettings = false
    @State private var showsFanStatus = false
    @State private var showsLocalActivity = false

    var body: some View {
        VStack(spacing: 0) {
            navigationButtons
            .padding([.top, .horizontal], 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    if showsFanStatus {
                        fanStatusCard
                    } else if showsPetSettings {
                        petSettingsCard
                    } else {
                        if !pendingNotices.notices.isEmpty {
                            pendingNoticeCard
                        }
                        if !store.onboardingCompleted {
                            welcomeCard
                        }
                        summaryCard

                        if store.selectedMetric == .memoryUsage {
                            memoryDetailsButton
                        } else if store.selectedMetric == .codexAllowance {
                            codexDetailsCard
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)

            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 320, height: 360)
        .task(id: showsFanStatus) {
            guard showsFanStatus else { return }
            while !Task.isCancelled {
                await store.refreshFanReadings()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    private var pendingNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pending reminders", systemImage: "bell.badge")
                .font(.subheadline.weight(.semibold))

            ForEach(pendingNotices.notices) { notice in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title)
                            .font(.subheadline.weight(.medium))
                        Text(notice.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                            Text("Expires")
                            Text(notice.expiresAt, style: .relative)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                    Spacer(minLength: 0)
                    Button {
                        alphaMetrics.recordNoticeDismissed(id: notice.id)
                        pendingNotices.dismiss(id: notice.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Dismiss reminder")
                    .accessibilityLabel("Dismiss \(notice.title)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Welcome to Desktop Buddy", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))

            Text("Your pixel pig makes laptop status easier to read. Battery and memory work locally, offline, and without an account.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose a status above, and use Show pig below to summon it. Codex allowance and app activity for focus detection are optional choices in Pet settings; neither is turned on by this guide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Privacy choices") {
                    showsPetSettings = true
                    showsFanStatus = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Got it") {
                    store.onboardingCompleted = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            navigationButton(
                title: "Battery",
                systemImage: "battery.75",
                isSelected: !showsPetSettings && !showsFanStatus && store.selectedMetric == .battery
            ) {
                store.selectedMetric = .battery
                alphaMetrics.recordMetricGlance(.battery)
                showsPetSettings = false
                showsFanStatus = false
            }

            navigationButton(
                title: "Memory",
                systemImage: "memorychip",
                isSelected: !showsPetSettings && !showsFanStatus && store.selectedMetric == .memoryUsage
            ) {
                store.selectedMetric = .memoryUsage
                alphaMetrics.recordMetricGlance(.memoryUsage)
                showsPetSettings = false
                showsFanStatus = false
            }

            if store.codexIntegrationEnabled {
                navigationButton(
                    title: "Codex",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isSelected: !showsPetSettings && !showsFanStatus && store.selectedMetric == .codexAllowance
                ) {
                    store.selectedMetric = .codexAllowance
                    alphaMetrics.recordMetricGlance(.codexAllowance)
                    showsPetSettings = false
                    showsFanStatus = false
                }
            }

            navigationButton(
                title: "Fans",
                systemImage: "fanblades",
                isSelected: showsFanStatus,
                accessibilityName: "Fan readings"
            ) {
                showsFanStatus = true
                showsPetSettings = false
            }

            navigationButton(
                title: "Pet",
                systemImage: "gearshape",
                isSelected: showsPetSettings && !showsFanStatus,
                accessibilityName: "Pet settings"
            ) {
                showsPetSettings = true
                showsFanStatus = false
            }
        }
    }

    private func navigationButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityName: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                PixelPigView(
                    severity: selectedSeverity,
                    frameIndex: animationPlayer.frameIndex
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selectedMetric.displayName)
                        .font(.headline)

                    Text(primaryStatus)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(secondaryStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if store.selectedMetric == .memoryUsage, store.memoryUsageState.isAvailable {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: store.memoryUsageState.usageFraction)
                        .tint(severityColor)
                        .accessibilityLabel("Memory usage")
                        .accessibilityValue("\(store.memoryUsageState.usagePercent) percent used")

                    Text(memoryLevelMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var memoryDetailsButton: some View {
        VStack(spacing: 0) {
            Button {
                isMemoryDetailsExpanded.toggle()
            } label: {
                HStack {
                    Label("Memory details", systemImage: "info.circle")
                    Spacer()
                    Image(systemName: isMemoryDetailsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isMemoryDetailsExpanded ? "Expanded" : "Collapsed")

            if isMemoryDetailsExpanded {
                Divider()
                    .padding(.vertical, 12)

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    detailRow("Compressed", formattedBytes(store.memoryUsageState.compressedBytes))
                    detailRow("Swap used", formattedBytes(store.memoryUsageState.swapUsedBytes))
                    detailRow("Swap writes", formattedRate(store.memoryUsageState.swapOutBytesPerSecond))
                    detailRow("System pressure", store.memoryUsageState.systemPressure.displayName)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var codexDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex allowance")
                .font(.subheadline.weight(.semibold))
            if let primary = store.codexAllowanceState.primary {
                codexWindowRow(primary)
            }
            if let secondary = store.codexAllowanceState.secondary {
                codexWindowRow(secondary)
            }
            if store.codexAllowanceState.primary == nil {
                Text(codexAvailabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var fanStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Fans", systemImage: "fanblades")
                .font(.headline)

            Text("Monitoring only. macOS automatic control remains the default; Desktop Buddy cannot change fan speed yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch store.fanReadoutState.availability {
            case .available:
                ForEach(store.fanReadoutState.fans, id: \.index) { fan in
                    fanReadingRow(fan)
                }
            case .fanless:
                Text("No fans reported by this Mac.")
                    .font(.subheadline)
            case .unavailable:
                Text("Fan readings unavailable on this Mac or macOS version.")
                    .font(.subheadline)
            }

            Text("Fan 0 and Fan 1 are not labeled left/right until their physical positions are verified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func fanReadingRow(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fan \(fan.index)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(fan.currentRPM.map { "\(Int($0.rounded())) RPM" } ?? "RPM unavailable")
                    .font(.subheadline.monospacedDigit())
            }
            Text(fanModeName(fan.mode))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let minimum = fan.minimumRPM, let maximum = fan.maximumRPM {
                Text("Range: \(Int(minimum.rounded()))–\(Int(maximum.rounded())) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let target = fan.targetRPM {
                Text("Target: \(Int(target.rounded())) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
    }

    private func fanModeName(_ mode: FanControlMode) -> String {
        switch mode {
        case .automatic: "Automatic (macOS)"
        case .manual: "Manual (set outside Desktop Buddy)"
        case .system: "System-managed"
        case .unknown: "Control mode unavailable"
        }
    }

    private func codexWindowRow(_ window: CodexQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(window.label) window")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(window.remainingPercent)% left")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(window.remainingPercent) / 100)
                .tint(severityColor)
                .accessibilityLabel("\(window.label) allowance remaining")
                .accessibilityValue("\(window.remainingPercent) percent left")
            if let resetsAt = window.resetsAt {
                HStack(spacing: 4) {
                    Text("Resets")
                    Text(resetsAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var petSettingsCard: some View {
        VStack(spacing: 18) {
            PixelPigView(
                severity: selectedSeverity,
                frameIndex: animationPlayer.frameIndex
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Pixel Pig")
                    .font(.headline)

                Text("Local-first: battery and memory status work without an account or sensitive permissions. Full-screen retreat checks window geometry, not window titles or content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Interaction mode")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 6) {
                        ForEach(InteractionMode.allCases, id: \.self) { mode in
                            Button(mode.displayName) {
                                store.interactionMode = mode
                            }
                            .buttonStyle(.bordered)
                            .tint(store.interactionMode == mode ? .accentColor : .secondary)
                            .accessibilityAddTraits(store.interactionMode == mode ? .isSelected : [])
                        }
                    }

                    Text("Ordinary notices are eligible no more often than every \(store.interactionMode.ordinaryCooldownMinutes) minutes, and only when a relevant event exists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Critical-battery warnings are immediate. Low-battery and high-memory bubbles follow this interval; suppressed events remain in Pending reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Animate pet", isOn: $animationPlayer.animationsEnabled)

                Text("Privacy & permissions")
                    .font(.subheadline.weight(.medium))

                Toggle("Allow app activity for focus detection", isOn: $store.applicationActivityEnabled)

                Text("Optional. Reads the frontmost app identifier and seconds since the last input to estimate focused work. This short history stays in memory and is cleared when you turn it off. No typed content, window titles, or screenshots are read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Stay quiet during possible focused work", isOn: $store.focusSuppressionEnabled)
                    .disabled(!store.applicationActivityEnabled)

                Text(store.applicationActivityEnabled
                     ? "Possible focus needs a recognized development, terminal, writing, design, or office app, five minutes of sustained use, recent input activity, and few app switches. Browsers and chat apps are not assumed to be focused work."
                     : "Focus-based hiding is inactive until app activity is allowed. Full-screen hiding still works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if focusActivity.isPossiblyFocused {
                    Text("Current activity: possibly focused work")
                        .font(.caption.weight(.medium))
                }

                Toggle("Enable Codex allowance", isOn: $store.codexIntegrationEnabled)

                Text("Optional. Reads your signed-in local Codex App Server normally every five minutes, with slower retries after repeated errors; no login key is copied or stored by Desktop Buddy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    "Show desktop pet",
                    isOn: Binding(
                        get: {
                            edgePetController.wantsVisible
                                && !edgePetController.isRecoveryRestoreSuppressed
                        },
                        set: { edgePetController.setVisible($0) }
                    )
                )

                if edgePetController.isRecoveryRestoreSuppressed {
                    Text("Desktop pet stayed hidden because the previous session ended unexpectedly. Turn it on when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if edgePetController.isFullscreenSuppressed
                    && edgePetController.wantsVisible
                    && !edgePetController.isVisible {
                    Text("Desktop pet is temporarily hidden while another app is full screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if edgePetController.isFocusSuppressed
                    && edgePetController.wantsVisible
                    && !edgePetController.isVisible {
                    Text("Desktop pet is temporarily hidden during possible focused work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Size")
                    Slider(
                        value: Binding(
                            get: { edgePetController.scale },
                            set: { edgePetController.setScale($0) }
                        ),
                        in: 0.75...1.5,
                        step: 0.05
                    )
                    .accessibilityLabel("Desktop pig size")
                    .accessibilityValue("\(Int((edgePetController.scale * 100).rounded())) percent")
                    Text("\(Int((edgePetController.scale * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }

                Button("Reset position") {
                    edgePetController.resetPosition()
                }

                Text("Current edge: \(edgePetController.edge.displayName)")
                    .font(.caption.weight(.medium))

                Text("Drag the pig toward any side to move it around the screen edges. Transparent space outside its silhouette still passes clicks through.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                DisclosureGroup("Local alpha activity", isExpanded: $showsLocalActivity) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Stored only on this Mac. These counters contain no application names, window titles, typed content, or timeline, and are never uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            detailRow("Notices shown", "\(alphaMetrics.snapshot.noticesShown)")
                            detailRow("Dismissed", "\(alphaMetrics.snapshot.noticesDismissed)")
                            detailRow("Acted on", "\(alphaMetrics.snapshot.noticesActedOn)")
                            detailRow("Battery glances", "\(alphaMetrics.snapshot.batteryGlances)")
                            detailRow("Memory glances", "\(alphaMetrics.snapshot.memoryGlances)")
                            detailRow("Codex glances", "\(alphaMetrics.snapshot.codexGlances)")
                            detailRow("Sessions", "\(alphaMetrics.snapshot.sessionsStarted)")
                            detailRow(
                                "App time",
                                formattedDuration(alphaMetrics.totalSessionSeconds())
                            )
                        }
                        .font(.caption)

                        Button("Clear local activity counts", role: .destructive) {
                            alphaMetrics.clear()
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.medium))

                Button("Show welcome guide again") {
                    store.onboardingCompleted = false
                    showsPetSettings = false
                    showsFanStatus = false
                }

                if animationPlayer.systemReduceMotionEnabled {
                    Text("Animation is paused because Reduce Motion is enabled in macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }

            Button(edgePetController.isVisible ? "Hide pig" : "Show pig") {
                if edgePetController.isVisible {
                    edgePetController.setVisible(false)
                } else {
                    edgePetController.summon()
                }
            }
            .accessibilityHint(edgePetController.isVisible
                ? "Hide the desktop pig until you show it again"
                : "Show the desktop pig at its saved screen edge, including during full screen or focused work")

            Spacer()

            if let lastUpdatedAt = showsFanStatus ? store.fanReadoutState.observedAt
                : (store.selectedMetric == .codexAllowance
                    ? store.codexAllowanceState.updatedAt : store.lastUpdatedAt) {
                Text(lastUpdatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    if showsFanStatus {
                        await store.refreshFanReadings()
                    } else if store.selectedMetric == .codexAllowance {
                        await store.refreshCodexAllowance()
                    } else {
                        await store.refresh()
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityLabel(showsFanStatus ? "Refresh fan readings" : "Refresh \(store.selectedMetric.displayName) status")
            .keyboardShortcut("r", modifiers: .command)
        }
    }

    private var primaryStatus: String {
        switch store.selectedMetric {
        case .battery:
            return store.batteryState.chargePercent.map { "\($0)%" } ?? "Unavailable"
        case .memoryUsage:
            return store.memoryUsageState.isAvailable
                ? "\(store.memoryUsageState.usagePercent)%"
                : "Unavailable"
        case .codexAllowance:
            return store.codexAllowanceState.primary.map { "\($0.remainingPercent)% left" }
                ?? (store.codexAllowanceState.availability == .loading ? "Connecting…" : "Unavailable")
        }
    }

    private var secondaryStatus: String {
        switch store.selectedMetric {
        case .battery:
            return batteryStatus
        case .memoryUsage:
            guard store.memoryUsageState.isAvailable else {
                return "Memory information unavailable"
            }
            return "\(formattedBytes(store.memoryUsageState.usedBytes)) of \(formattedBytes(store.memoryUsageState.totalBytes))"
        case .codexAllowance:
            return store.codexAllowanceState.primary.map { "\($0.label) window" }
                ?? "Optional local integration"
        }
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

    private var codexAvailabilityMessage: String {
        switch store.codexAllowanceState.availability {
        case .notConfigured: "Not enabled"
        case .loading: "Connecting…"
        case .available: "Allowance unavailable"
        case .executableMissing: "Codex CLI not found"
        case .unavailable: "Unable to read Codex allowance. Check your CLI sign-in."
        }
    }

    private var severityColor: Color {
        switch selectedSeverity {
        case .normal: return .green
        case .elevated: return .orange
        case .caution: return .yellow
        case .critical: return .red
        case .unavailable: return .secondary
        }
    }

    private var batteryStatus: String {
        let state = store.batteryState

        if state.isCharging {
            return "Charging"
        }

        switch state.powerSource {
        case .adapter:
            return "Connected to power"
        case .battery:
            return batteryMessage(for: state.condition)
        case .unknown:
            return "Battery information unavailable"
        }
    }

    private var memoryLevelMessage: String {
        switch store.memoryUsageLevel {
        case .normal:
            return "Memory usage looks good"
        case .elevated:
            return "Memory usage is elevated"
        case .high:
            return "Consider reviewing high-memory apps"
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .memory
        )
    }

    private func formattedRate(_ bytesPerSecond: UInt64) -> String {
        guard bytesPerSecond > 0 else { return "None" }
        return "\(formattedBytes(bytesPerSecond))/s"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func batteryMessage(for condition: BatteryCondition) -> String {
        switch condition {
        case .normal:
            return "Battery looks good"
        case .low:
            return "Battery is getting low"
        case .critical:
            return "Consider connecting your charger"
        case .unavailable:
            return "Battery information unavailable"
        }
    }
}
