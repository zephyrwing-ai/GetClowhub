import SwiftUI
import AppKit

struct SessionTitleUserMessagesPopover: View {
    let title: String
    let messages: [ChatMessage]
    let onTapMessage: (ChatMessage) -> Void

    @State private var isTitleHovering = false

    var body: some View {
        SessionTitlePanelHost(
            isTitleHovering: isTitleHovering,
            messages: messages,
            onTapMessage: { message in
                onTapMessage(message)
            }
        ) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(isTitleHovering ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(isTitleHovering ? 0.22 : 0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .onHover { hovering in
            isTitleHovering = hovering
        }
    }
}

private struct SessionTitlePanelHost<Label: View>: NSViewRepresentable {
    let isTitleHovering: Bool
    let messages: [ChatMessage]
    let onTapMessage: (ChatMessage) -> Void
    @ViewBuilder let label: () -> Label

    func makeNSView(context: Context) -> NSHostingView<Label> {
        let view = NSHostingView(rootView: label())
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ nsView: NSHostingView<Label>, context: Context) {
        nsView.rootView = label()
        context.coordinator.update(
            messages: messages,
            onTapMessage: onTapMessage
        )
        context.coordinator.setTitleHovering(isTitleHovering, relativeTo: nsView)
    }

    func makeCoordinator() -> SessionTitlePopoverCoordinator {
        SessionTitlePopoverCoordinator()
    }

    static func dismantleNSView(_ nsView: NSHostingView<Label>, coordinator: SessionTitlePopoverCoordinator) {
        coordinator.closeImmediately()
    }
}

private final class SessionTitlePopoverCoordinator {
    private let panelContentSize = NSSize(width: 360, height: 320)
    private let panelChromeInset: CGFloat = 14
    private let titlePanelVerticalOffset: CGFloat = 8
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SessionTitleUserMessagesPopoverContent>?
    private var messages: [ChatMessage] = []
    private var onTapMessage: (ChatMessage) -> Void = { _ in }
    private var isTitleHovering = false
    private var isPanelHovering = false
    private var pendingPresentWork: DispatchWorkItem?
    private var panelCloseTask: DispatchWorkItem?

    private var panelWindowSize: NSSize {
        NSSize(
            width: panelContentSize.width + (panelChromeInset * 2),
            height: panelContentSize.height + (panelChromeInset * 2)
        )
    }

    func update(
        messages: [ChatMessage],
        onTapMessage: @escaping (ChatMessage) -> Void
    ) {
        self.messages = messages
        self.onTapMessage = onTapMessage
        hostingController?.rootView = SessionTitleUserMessagesPopoverContent(
            messages: messages,
            onPanelHoverChange: updatePanelHover,
            onTapMessage: handleTapMessage
        )
        if messages.isEmpty {
            closeImmediately()
        }
    }

    func setTitleHovering(_ hovering: Bool, relativeTo sourceView: NSView) {
        isTitleHovering = hovering
        if hovering {
            panelCloseTask?.cancel()
            panelCloseTask = nil
            schedulePresent(relativeTo: sourceView)
        } else {
            schedulePanelClose()
        }
    }

    func schedulePresent(relativeTo sourceView: NSView) {
        pendingPresentWork?.cancel()

        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView else { return }
            guard self.isTitleHovering, !self.messages.isEmpty else { return }
            guard sourceView.window != nil, !sourceView.bounds.isEmpty else { return }

            let panel = self.ensurePanel()
            panel.setFrame(self.panelFrame(relativeTo: sourceView), display: true)
            panel.orderFrontRegardless()
        }
        pendingPresentWork = work
        DispatchQueue.main.async(execute: work)
    }

    func closeImmediately() {
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        panelCloseTask?.cancel()
        panelCloseTask = nil
        panel?.orderOut(nil)
    }

    private func updatePanelHover(_ hovering: Bool) {
        isPanelHovering = hovering
        if hovering {
            panelCloseTask?.cancel()
            panelCloseTask = nil
        } else {
            schedulePanelClose()
        }
    }

    private func schedulePanelClose() {
        panelCloseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !isTitleHovering && !isPanelHovering && !isMouseInsidePanel {
                panel?.orderOut(nil)
            }
        }
        panelCloseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    private func handleTapMessage(_ message: ChatMessage) {
        closeImmediately()
        onTapMessage(message)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let controller = NSHostingController(
            rootView: SessionTitleUserMessagesPopoverContent(
                messages: messages,
                onPanelHoverChange: updatePanelHover,
                onTapMessage: handleTapMessage
            )
        )
        controller.view.setFrameSize(panelWindowSize)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = controller
        self.panel = panel
        return panel
    }

    private func panelFrame(relativeTo sourceView: NSView) -> NSRect {
        guard let window = sourceView.window else {
            return NSRect(origin: .zero, size: panelWindowSize)
        }

        let titleFrameInWindow = sourceView.convert(sourceView.bounds, to: nil)
        let titleFrameOnScreen = window.convertToScreen(titleFrameInWindow)
        let x = titleFrameOnScreen.midX - (panelWindowSize.width / 2)
        let visibleTopY = titleFrameOnScreen.minY - titlePanelVerticalOffset
        let y = visibleTopY - panelContentSize.height - panelChromeInset

        return NSRect(x: x, y: y, width: panelWindowSize.width, height: panelWindowSize.height)
    }

    private var isMouseInsidePanel: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }
}

private struct SessionTitleUserMessagesPopoverContent: View {
    let messages: [ChatMessage]
    let onPanelHoverChange: (Bool) -> Void
    let onTapMessage: (ChatMessage) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(messages) { message in
                    Button {
                        onTapMessage(message)
                    } label: {
                        SessionTitleUserMessageRow(message: message)
                    }
                    .buttonStyle(.plain)

                    if message.id != messages.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 360)
        .frame(maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(SessionTitlePanelBackground(cornerRadius: 12))
        .background(SessionTitlePanelHoverTracker(onPanelHoverChange: onPanelHoverChange))
        .padding(14)
    }
}

private struct SessionTitlePanelBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.10),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

private struct SessionTitlePanelHoverTracker: NSViewRepresentable {
    let onPanelHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onPanelHoverChange = onPanelHoverChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onPanelHoverChange = onPanelHoverChange
    }

    final class TrackingView: NSView {
        var onPanelHoverChange: (Bool) -> Void = { _ in }
        private var trackingArea: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea

            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            onPanelHoverChange(true)
        }

        override func mouseExited(with event: NSEvent) {
            onPanelHoverChange(false)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                let boundsInWindow = convert(bounds, to: nil)
                onPanelHoverChange(boundsInWindow.contains(window.mouseLocationOutsideOfEventStream))
            } else {
                onPanelHoverChange(false)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct SessionTitleUserMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let timestamp = message.timestamp {
                Text(Self.timestampFormatter.string(from: timestamp))
                    .font(DashboardTypography.messageMeta)
                    .foregroundStyle(.secondary)
            }

            Text(messagePreview)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var messagePreview: String {
        let trimmed = message.content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Empty message" : trimmed
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
