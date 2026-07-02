import SwiftUI
import AppKit
import Foundation
import os.log

let chatRenderPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")

func dashboardElapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
    let duration = start.duration(to: ContinuousClock.now)
    let components = duration.components
    let milliseconds = Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.1f", milliseconds)
}

// MARK: - Assistant Markdown Rendering

enum MarkdownRenderMode {
    case native
    case webView
}

enum MarkdownRenderPolicy {
    static let heightUpdateThreshold: CGFloat = 4
    static let recentRichMessageLimit = 6

    static func mode(for content: String, isStreaming: Bool, allowsWebView: Bool = true) -> MarkdownRenderMode {
        if isStreaming { return .native }
        if !allowsWebView { return .native }
        return requiresWebView(content) ? .webView : .native
    }

    static func shouldApplyMeasuredHeight(current: CGFloat, measured: CGFloat) -> Bool {
        abs(current - measured) >= heightUpdateThreshold
    }

    static func isComplexMarkdown(_ content: String) -> Bool {
        requiresWebView(content)
    }

    static func recentRichMessageIds(in messages: [ChatMessage]) -> Set<UUID> {
        var ids: Set<UUID> = []

        for message in messages.reversed() {
            guard ids.count < recentRichMessageLimit else { break }
            guard message.role == .assistant,
                  message.taskStatus == .completed,
                  requiresWebView(message.content) else {
                continue
            }
            ids.insert(message.id)
        }

        return ids
    }

    private static func requiresWebView(_ content: String) -> Bool {
        containsMarkdownTable(content)
            || containsMathSyntax(content)
            || containsHTMLBlock(content)
    }

    private static func containsMarkdownTable(_ content: String) -> Bool {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 2 else { return false }

        for index in 0..<(lines.count - 1) {
            let header = lines[index]
            let separator = lines[index + 1]
                .trimmingCharacters(in: .whitespaces)

            if header.contains("|"),
               separator.contains("|"),
               separator.contains("-"),
               separator.allSatisfy({ char in
                   char == "|" || char == "-" || char == ":" || char == " "
               }) {
                return true
            }
        }
        return false
    }

    private static func containsMathSyntax(_ content: String) -> Bool {
        if content.contains("$$")
            || content.contains(#"\("#)
            || content.contains(#"\["#)
            || content.contains(#"\begin{"#) {
            return true
        }

        let pattern = #"(?<![A-Za-z0-9])\$[^\n$]{1,160}\$(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    private static func containsHTMLBlock(_ content: String) -> Bool {
        let pattern = #"<\s*(table|thead|tbody|tr|td|th|div|details|summary|img|video|audio|iframe|style|script|br|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }
}

private struct MessageRenderModel {
    enum Renderer {
        case nativeText
        case webViewFallback
    }

    let content: String
    let isStreaming: Bool
    let renderer: Renderer

    static func build(content: String, isStreaming: Bool, allowsRichMarkdown: Bool) -> MessageRenderModel {
        let mode = MarkdownRenderPolicy.mode(
            for: content,
            isStreaming: isStreaming,
            allowsWebView: allowsRichMarkdown
        )
        switch mode {
        case .native:
            return MessageRenderModel(content: content, isStreaming: isStreaming, renderer: .nativeText)
        case .webView:
            return MessageRenderModel(content: content, isStreaming: isStreaming, renderer: .webViewFallback)
        }
    }
}

struct AssistantMessageContentView: View {
    let content: String
    let isStreaming: Bool
    let allowsRichMarkdown: Bool

    init(
        content: String,
        isStreaming: Bool,
        allowsRichMarkdown: Bool = true
    ) {
        self.content = content
        self.isStreaming = isStreaming
        self.allowsRichMarkdown = allowsRichMarkdown
    }

    var body: some View {
        let renderModel = MessageRenderModel.build(
            content: content,
            isStreaming: isStreaming,
            allowsRichMarkdown: allowsRichMarkdown
        )

        switch renderModel.renderer {
        case .webViewFallback:
            SelectableMarkdownView(
                content: renderModel.content,
                copyFallbackText: renderModel.content
            )
                .onAppear {
                    logRenderMode("webview")
                }
        case .nativeText:
            NativeSelectableMarkdownView(
                content: renderModel.content,
                fullTextCopyFallback: renderModel.content,
                parsesMarkdown: !renderModel.isStreaming,
                fontSize: 14
            )
                .onAppear {
                    logRenderMode("native_selectable")
                }
        }
    }

    private func logRenderMode(_ mode: String) {
        chatRenderPerfLog.info("phase=assistant_content_render_mode mode=\(mode, privacy: .public) content_length=\(content.count, privacy: .public) is_streaming=\(isStreaming, privacy: .public) allows_rich_markdown=\(allowsRichMarkdown, privacy: .public)")
    }
}

// MARK: - Native Markdown View (lightweight, no WKWebView)

/// Renders markdown using SwiftUI's native AttributedString.
/// Zero WKWebView overhead — no process spawn, no HTML parsing, no height measurement.
struct NativeMarkdownView: View {
    let content: String

    var body: some View {
        Text(attributedContent)
            .font(DashboardTypography.message)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content)
    }
}

struct NativeSelectableMarkdownView: NSViewRepresentable {
    let content: String
    let fullTextCopyFallback: String
    let parsesMarkdown: Bool
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat

    init(
        content: String,
        fullTextCopyFallback: String? = nil,
        parsesMarkdown: Bool,
        fontSize: CGFloat = 14,
        lineSpacing: CGFloat = 2,
        paragraphSpacing: CGFloat = 6
    ) {
        self.content = content
        self.fullTextCopyFallback = fullTextCopyFallback ?? content
        self.parsesMarkdown = parsesMarkdown
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
    }

    func makeNSView(context: Context) -> IntrinsicHeightTextView {
        let textView = IntrinsicHeightTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.fullTextCopyFallback = fullTextCopyFallback
        apply(content, parsesMarkdown: parsesMarkdown, to: textView)
        return textView
    }

    func updateNSView(_ textView: IntrinsicHeightTextView, context: Context) {
        let width = max(textView.bounds.width, 1)
        if abs(context.coordinator.lastWidth - width) > IntrinsicHeightTextView.layoutEpsilon {
            _ = textView.updateContainerWidth(width)
            context.coordinator.lastWidth = width
        }
        if context.coordinator.lastContent != content
            || context.coordinator.lastFullTextCopyFallback != fullTextCopyFallback
            || context.coordinator.lastParsesMarkdown != parsesMarkdown
            || context.coordinator.lastFontSize != fontSize
            || context.coordinator.lastLineSpacing != lineSpacing
            || context.coordinator.lastParagraphSpacing != paragraphSpacing {
            textView.fullTextCopyFallback = fullTextCopyFallback
            apply(content, parsesMarkdown: parsesMarkdown, to: textView)
            context.coordinator.lastContent = content
            context.coordinator.lastFullTextCopyFallback = fullTextCopyFallback
            context.coordinator.lastParsesMarkdown = parsesMarkdown
            context.coordinator.lastFontSize = fontSize
            context.coordinator.lastLineSpacing = lineSpacing
            context.coordinator.lastParagraphSpacing = paragraphSpacing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            content: content,
            fullTextCopyFallback: fullTextCopyFallback,
            parsesMarkdown: parsesMarkdown,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
    }

    private func apply(_ markdown: String, parsesMarkdown: Bool, to textView: IntrinsicHeightTextView) {
        let rendered = Self.attributedString(
            from: markdown,
            parsesMarkdown: parsesMarkdown,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
        if let textStorage = textView.textStorage {
            textStorage.beginEditing()
            textStorage.setAttributedString(rendered)
            textStorage.endEditing()
        }
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.refreshMeasuredHeightAfterContentChange()
    }

    private static func attributedString(
        from markdown: String,
        parsesMarkdown: Bool,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> NSAttributedString {
        let mutable: NSMutableAttributedString
        if parsesMarkdown {
            let attributed = (try? AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(markdown)
            mutable = NSMutableAttributedString(attributed)
        } else {
            mutable = NSMutableAttributedString(string: markdown)
        }
        let fullRange = NSRange(location: 0, length: mutable.length)
        if fullRange.length > 0 {
            mutable.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle(lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing)
                ],
                range: fullRange
            )
        }
        return mutable
    }

    private static func paragraphStyle(lineSpacing: CGFloat, paragraphSpacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.lineBreakMode = .byWordWrapping
        return style
    }

    final class Coordinator {
        var lastContent: String
        var lastFullTextCopyFallback: String
        var lastParsesMarkdown: Bool
        var lastFontSize: CGFloat
        var lastLineSpacing: CGFloat
        var lastParagraphSpacing: CGFloat
        var lastWidth: CGFloat = 0

        init(
            content: String,
            fullTextCopyFallback: String,
            parsesMarkdown: Bool,
            fontSize: CGFloat,
            lineSpacing: CGFloat,
            paragraphSpacing: CGFloat
        ) {
            self.lastContent = content
            self.lastFullTextCopyFallback = fullTextCopyFallback
            self.lastParsesMarkdown = parsesMarkdown
            self.lastFontSize = fontSize
            self.lastLineSpacing = lineSpacing
            self.lastParagraphSpacing = paragraphSpacing
        }
    }

    final class IntrinsicHeightTextView: NSTextView {
        static let layoutEpsilon: CGFloat = 0.5

        private var cachedIntrinsicHeight: CGFloat?
        private var lastMeasuredWidth: CGFloat = 0
        private var lastAppliedFrameWidth: CGFloat = 0
        var fullTextCopyFallback: String = ""

        override var acceptsFirstResponder: Bool { true }

        override var intrinsicContentSize: NSSize {
            guard let textContainer = textContainer else {
                return NSSize(width: NSView.noIntrinsicMetric, height: 22)
            }
            let width = max(textContainer.containerSize.width, 1)
            guard width > 1 else {
                return NSSize(width: NSView.noIntrinsicMetric, height: max(22, cachedIntrinsicHeight ?? 22))
            }
            if let cachedIntrinsicHeight,
               abs(lastMeasuredWidth - width) <= Self.layoutEpsilon {
                return NSSize(width: NSView.noIntrinsicMetric, height: max(22, cachedIntrinsicHeight))
            }
            let height = measureHeight(for: textContainer)
            cachedIntrinsicHeight = height
            lastMeasuredWidth = width
            return NSSize(width: NSView.noIntrinsicMetric, height: max(22, height))
        }

        @discardableResult
        func updateContainerWidth(_ width: CGFloat) -> Bool {
            let normalizedWidth = max(width, 1)
            let currentWidth = textContainer?.containerSize.width ?? 0
            guard abs(currentWidth - normalizedWidth) > Self.layoutEpsilon else { return false }
            textContainer?.containerSize = NSSize(
                width: normalizedWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            return refreshMeasuredHeight()
        }

        func refreshMeasuredHeightAfterContentChange() {
            _ = refreshMeasuredHeight()
        }

        @discardableResult
        private func refreshMeasuredHeight() -> Bool {
            guard let textContainer else {
                let shouldInvalidate = cachedIntrinsicHeight != nil
                cachedIntrinsicHeight = nil
                if shouldInvalidate {
                    invalidateIntrinsicContentSize()
                }
                return shouldInvalidate
            }

            let width = max(textContainer.containerSize.width, 1)
            guard width > 1 else {
                let shouldInvalidate = cachedIntrinsicHeight != nil
                cachedIntrinsicHeight = nil
                lastMeasuredWidth = width
                if shouldInvalidate {
                    invalidateIntrinsicContentSize()
                }
                return shouldInvalidate
            }

            let previousHeight = cachedIntrinsicHeight
            let measuredHeight = measureHeight(for: textContainer)
            cachedIntrinsicHeight = measuredHeight
            lastMeasuredWidth = width

            let heightChanged = previousHeight.map { abs($0 - measuredHeight) > Self.layoutEpsilon } ?? true
            if heightChanged {
                invalidateIntrinsicContentSize()
                return true
            }
            return false
        }

        private func measureHeight(for textContainer: NSTextContainer) -> CGFloat {
            layoutManager?.ensureLayout(for: textContainer)
            return ceil(layoutManager?.usedRect(for: textContainer).height ?? 22)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            let width = max(newSize.width, 1)
            guard abs(lastAppliedFrameWidth - width) > Self.layoutEpsilon else { return }
            lastAppliedFrameWidth = width
            _ = updateContainerWidth(width)
        }

        override func mouseDown(with event: NSEvent) {
            markActiveForCopy()
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            markActiveForCopy()
            super.mouseDragged(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            markActiveForCopy()
            super.mouseUp(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard Self.isCommandCopyEvent(event) else {
                return super.performKeyEquivalent(with: event)
            }
            copy(nil)
            return true
        }

        override func keyDown(with event: NSEvent) {
            if Self.isCommandCopyEvent(event) {
                copy(nil)
                return
            }
            super.keyDown(with: event)
        }

        override func copy(_ sender: Any?) {
            guard copySelectedTextIfAvailable() else {
                if !fullTextCopyFallback.isEmpty {
                    Self.copyTextToPasteboard(fullTextCopyFallback)
                    return
                }
                super.copy(sender)
                return
            }
        }

        func copySelectedTextIfAvailable() -> Bool {
            let selected = selectedText
            guard !selected.isEmpty else { return false }
            Self.copyTextToPasteboard(selected)
            return true
        }

        private var selectedText: String {
            selectedRanges
                .compactMap { rangeValue -> String? in
                    let range = rangeValue.rangeValue
                    guard range.length > 0,
                          range.location != NSNotFound,
                          NSMaxRange(range) <= string.utf16.count,
                          let swiftRange = Range(range, in: string) else {
                        return nil
                    }
                    return String(string[swiftRange])
                }
                .joined()
        }

        private func markActiveForCopy() {
            NativeSelectableTextSelectionRegistry.activeTextView = self
            window?.makeFirstResponder(self)
        }

        private static func isCommandCopyEvent(_ event: NSEvent) -> Bool {
            event.type == .keyDown &&
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) &&
                event.charactersIgnoringModifiers?.lowercased() == "c"
        }

        private static func copyTextToPasteboard(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

enum NativeSelectableTextSelectionRegistry {
    static weak var activeTextView: NativeSelectableMarkdownView.IntrinsicHeightTextView?

    static func copySelectedTextFromFirstResponder(_ sender: Any?) -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else {
            return false
        }
        textView.copy(sender)
        return true
    }

    static func copyActiveSelection() -> Bool {
        activeTextView?.copySelectedTextIfAvailable() == true
    }
}
