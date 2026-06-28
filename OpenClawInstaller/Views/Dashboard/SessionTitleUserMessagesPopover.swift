import SwiftUI
import AppKit

struct SessionTitleUserMessagesPopover: View {
    let title: String
    let messages: [ChatMessage]
    let onTapMessage: (ChatMessage) -> Void

    @State private var isTitleHovering = false
    @State private var isPopoverHovering = false
    @State private var isPopoverPresented = false
    @State private var popoverCloseTask: DispatchWorkItem?

    var body: some View {
        SessionTitlePopoverHost(
            isPresented: $isPopoverPresented,
            messages: messages,
            onPopoverHoverChange: updatePopoverHover,
            onTapMessage: { message in
                closePopover()
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
                        .fill(Color.secondary.opacity(isTitleHovering || isPopoverPresented ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(isTitleHovering || isPopoverPresented ? 0.22 : 0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .onHover { hovering in
            isTitleHovering = hovering
            if hovering {
                openPopoverIfPossible()
            } else {
                schedulePopoverClose()
            }
        }
        .onDisappear {
            closePopover()
        }
        .onChange(of: messages.count) { count in
            if count == 0 {
                closePopover()
            }
        }
    }

    private func openPopoverIfPossible() {
        popoverCloseTask?.cancel()
        popoverCloseTask = nil
        guard !messages.isEmpty else { return }
        isPopoverPresented = true
    }

    private func schedulePopoverClose() {
        popoverCloseTask?.cancel()
        let task = DispatchWorkItem {
            if !isTitleHovering && !isPopoverHovering {
                closePopover()
            }
        }
        popoverCloseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }

    private func closePopover() {
        popoverCloseTask?.cancel()
        popoverCloseTask = nil
        isPopoverPresented = false
        isTitleHovering = false
        isPopoverHovering = false
    }

    private func updatePopoverHover(_ hovering: Bool) {
        isPopoverHovering = hovering
        if hovering {
            popoverCloseTask?.cancel()
            popoverCloseTask = nil
        } else {
            schedulePopoverClose()
        }
    }
}

private struct SessionTitlePopoverHost<Label: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let messages: [ChatMessage]
    let onPopoverHoverChange: (Bool) -> Void
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
            onPopoverHoverChange: onPopoverHoverChange,
            onTapMessage: onTapMessage
        )

        if isPresented, !messages.isEmpty {
            context.coordinator.schedulePresent(relativeTo: nsView, isPresented: $isPresented)
        } else {
            context.coordinator.close()
        }
    }

    func makeCoordinator() -> SessionTitlePopoverCoordinator {
        SessionTitlePopoverCoordinator()
    }
}

private final class SessionTitlePopoverCoordinator: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var hostingController: NSHostingController<SessionTitleUserMessagesPopoverContent>?
    private var messages: [ChatMessage] = []
    private var onPopoverHoverChange: (Bool) -> Void = { _ in }
    private var onTapMessage: (ChatMessage) -> Void = { _ in }
    private var isPresented: Binding<Bool>?
    private var pendingPresentWork: DispatchWorkItem?

    func update(
        messages: [ChatMessage],
        onPopoverHoverChange: @escaping (Bool) -> Void,
        onTapMessage: @escaping (ChatMessage) -> Void
    ) {
        self.messages = messages
        self.onPopoverHoverChange = onPopoverHoverChange
        self.onTapMessage = onTapMessage
        hostingController?.rootView = SessionTitleUserMessagesPopoverContent(
            messages: messages,
            onPopoverHoverChange: onPopoverHoverChange,
            onTapMessage: onTapMessage
        )
    }

    func schedulePresent(relativeTo sourceView: NSView, isPresented: Binding<Bool>) {
        self.isPresented = isPresented
        pendingPresentWork?.cancel()

        let work = DispatchWorkItem { [weak self, weak sourceView] in
            guard let self, let sourceView else {
                isPresented.wrappedValue = false
                return
            }
            guard isPresented.wrappedValue, !self.messages.isEmpty else { return }
            guard sourceView.window != nil, !sourceView.bounds.isEmpty else {
                isPresented.wrappedValue = false
                return
            }

            let popover = self.ensurePopover()
            guard !popover.isShown else { return }
            popover.show(
                relativeTo: sourceView.bounds,
                of: sourceView,
                preferredEdge: .maxY
            )
        }
        pendingPresentWork = work
        DispatchQueue.main.async(execute: work)
    }

    func close() {
        pendingPresentWork?.cancel()
        pendingPresentWork = nil
        popover?.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        guard isPresented?.wrappedValue == true else { return }
        DispatchQueue.main.async {
            self.isPresented?.wrappedValue = false
        }
    }

    private func ensurePopover() -> NSPopover {
        if let popover {
            return popover
        }

        let controller = NSHostingController(
            rootView: SessionTitleUserMessagesPopoverContent(
                messages: messages,
                onPopoverHoverChange: onPopoverHoverChange,
                onTapMessage: onTapMessage
            )
        )
        controller.view.setFrameSize(NSSize(width: 360, height: 1))
        hostingController = controller

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 320)
        popover.contentViewController = controller
        popover.delegate = self
        self.popover = popover
        return popover
    }
}

private struct SessionTitleUserMessagesPopoverContent: View {
    let messages: [ChatMessage]
    let onPopoverHoverChange: (Bool) -> Void
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
        .background(SessionTitleLiquidGlassBackground(cornerRadius: 12))
        .onHover { hovering in
            onPopoverHoverChange(hovering)
        }
    }
}

private struct SessionTitleLiquidGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.36),
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.04),
                                Color.black.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.12),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 180
                        )
                    )
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                Color.white.opacity(0.22),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
            .shadow(color: Color.white.opacity(0.18), radius: 1, x: 0, y: 1)
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
