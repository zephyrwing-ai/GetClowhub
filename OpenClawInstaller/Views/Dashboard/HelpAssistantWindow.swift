import SwiftUI
import AppKit

// MARK: - Window Controller

class HelpAssistantWindowController {
    static let shared = HelpAssistantWindowController()

    private var window: NSWindow?
    private var viewModel: HelpAssistantViewModel?

    func showWindow(dashboardViewModel: DashboardViewModel) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        if viewModel == nil {
            viewModel = HelpAssistantViewModel(dashboardViewModel: dashboardViewModel)
        }

        let contentView = HelpAssistantView(viewModel: viewModel!)
        let hostingView = NSHostingView(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "GetClawHub Help"
        win.contentView = hostingView
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 320, height: 400)
        win.maxSize = NSSize(width: 600, height: 800)
        win.center()
        win.delegate = WindowDelegate.shared

        self.window = win
        win.makeKeyAndOrderFront(nil)
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    fileprivate func windowWillClose() {
        window = nil
    }

    private class WindowDelegate: NSObject, NSWindowDelegate {
        static let shared = WindowDelegate()
        func windowWillClose(_ notification: Notification) {
            HelpAssistantWindowController.shared.windowWillClose()
        }
    }
}

// MARK: - Help Assistant View

struct HelpAssistantView: View {
    @ObservedObject var viewModel: HelpAssistantViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Spacer()
                Circle()
                    .fill(viewModel.isServiceRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.isServiceRunning ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Message area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            welcomeView
                        } else {
                            ForEach(viewModel.messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                            if viewModel.isLoading {
                                typingIndicator
                            }
                        }
                    }
                    .padding(12)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            inputBar

            // Offline notice
            if !viewModel.isServiceRunning {
                offlineNotice
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 20)

            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text("Hi! I'm GetClawHub Assistant")
                .font(.headline)

            Text("Ask me anything about using GetClawHub.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(quickQuestions, id: \.0) { zh, en in
                    let isChinese = LanguageManager.shared.currentLocale.language.languageCode?.identifier.hasPrefix("zh") == true
                    let displayText = isChinese ? zh : en
                    Button(action: { viewModel.sendQuestion(displayText) }) {
                        Text(displayText)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private var quickQuestions: [(String, String)] {
        guard let tab = viewModel.currentTab else {
            return viewModel.quickQuestions(for: .status)
        }
        return viewModel.quickQuestions(for: tab)
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.bubble.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Text("Typing...")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a question...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit {
                    viewModel.sendQuestion(viewModel.inputText)
                }
                .disabled(viewModel.isLoading)

            Button(action: { viewModel.sendQuestion(viewModel.inputText) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canSend ? .accentColor : Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isLoading
    }

    // MARK: - Offline Notice

    private var offlineNotice: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
            Text("Offline — FAQ answers only")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: HelpMessage
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    /// Visual ack for the copy button — flips on for ~1.5s after a copy
    /// click. Mirrors `ChatBubble.copied` in DashboardView.swift so the
    /// Help window's UX matches the main chat.
    @State private var copied = false
    @State private var copyResetTask: DispatchWorkItem?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    if message.role == .assistant {
                        SelectableMarkdownView(content: message.content)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(bubbleBackground)
                            .cornerRadius(12)
                    } else {
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(bubbleBackground)
                            .cornerRadius(12)
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
                .contextMenu {
                    Button(action: { performCopy(message.content) }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                // Always-visible copy affordance under each bubble (dimmed
                // when the bubble isn't hovered). The assistant side
                // renders via WKWebView (SelectableMarkdownView), which
                // supports drag-select inside a single message but
                // can't span bubbles — so a one-click copy is the most
                // reliable path. Click → icon swaps to checkmark + "已
                // 复制" label for 1.5s.
                if !message.content.isEmpty {
                    Button(action: { performCopy(message.content) }) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(copied ? .green : .secondary)
                            if copied {
                                Text("已复制")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(NSColor.windowBackgroundColor))
                                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(copied ? "已复制" : "复制消息")
                    .opacity(isHovering || copied ? 1.0 : 0.55)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                    .animation(.easeInOut(duration: 0.18), value: copied)
                }
            }

            if message.role == .user {
                Spacer(minLength: 40)
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.15))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copy + show the "已复制" ack for 1.5s. Re-clicks restart the
    /// reset window instead of stacking timers.
    private func performCopy(_ text: String) {
        copyToClipboard(text)
        withAnimation(.easeInOut(duration: 0.18)) {
            copied = true
        }
        copyResetTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                copied = false
            }
        }
        copyResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}
