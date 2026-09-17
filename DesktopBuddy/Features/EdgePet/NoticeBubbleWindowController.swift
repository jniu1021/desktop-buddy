import AppKit
import SwiftUI

@MainActor
final class NoticeBubbleWindowController {
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    private var onHide: (() -> Void)?
    private let bubbleSize = NSSize(width: 232, height: 74)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: bubbleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
    }

    @discardableResult
    func show(
        _ notice: DeviceNotice,
        beside petFrame: NSRect,
        edge: PetScreenEdge,
        onHide: @escaping () -> Void
    ) -> Bool {
        hideTask?.cancel()
        self.onHide = nil
        panel.contentViewController = NSHostingController(rootView: NoticeBubbleView(notice: notice))
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(petFrame) })
            ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        let preferredOrigin: NSPoint
        switch edge {
        case .left:
            preferredOrigin = NSPoint(x: petFrame.maxX + gap, y: petFrame.midY - bubbleSize.height / 2)
        case .right:
            preferredOrigin = NSPoint(x: petFrame.minX - bubbleSize.width - gap, y: petFrame.midY - bubbleSize.height / 2)
        case .top:
            preferredOrigin = NSPoint(x: petFrame.midX - bubbleSize.width / 2, y: petFrame.minY - bubbleSize.height - gap)
        case .bottom:
            preferredOrigin = NSPoint(x: petFrame.midX - bubbleSize.width / 2, y: petFrame.maxY + gap)
        }
        panel.setFrameOrigin(NSPoint(
            x: min(max(preferredOrigin.x, visible.minX), visible.maxX - bubbleSize.width),
            y: min(max(preferredOrigin.y, visible.minY), visible.maxY - bubbleSize.height)
        ))
        panel.orderFrontRegardless()
        self.onHide = onHide
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
        return true
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel.orderOut(nil)
        let completion = onHide
        onHide = nil
        completion?()
    }
}

private struct NoticeBubbleView: View {
    let notice: DeviceNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notice.title)
                .font(.subheadline.weight(.semibold))
            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .padding(2)
    }
}
