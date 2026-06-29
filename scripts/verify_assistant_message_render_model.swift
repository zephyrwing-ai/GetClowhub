#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let rendererURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")
let selectableURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift")
let markdownHTMLURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarkdownHTML.swift")
let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let renderer = (try? String(contentsOf: rendererURL, encoding: .utf8)) ?? ""
let selectable = (try? String(contentsOf: selectableURL, encoding: .utf8)) ?? ""
let markdownHTML = (try? String(contentsOf: markdownHTMLURL, encoding: .utf8)) ?? ""

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        return ""
    }
    if end == "***END***" {
        return String(source[startRange.lowerBound..<source.endIndex])
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let renderModel = slice(
    renderer,
    from: "private struct MessageRenderModel",
    to: "struct AssistantMessageContentView: View"
)
let assistantView = slice(
    renderer,
    from: "struct AssistantMessageContentView: View",
    to: "// MARK: - Native"
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "// MARK: - Chat Bubble"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor"
)
let nativeBridge = slice(
    renderer,
    from: "struct NativeSelectableMarkdownView: NSViewRepresentable",
    to: "***END***"
)
let markdownWebView = slice(
    selectable,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "***END***"
)

require(dashboard.contains("AssistantMessageContentView("), "DashboardView should still compose assistant content")
require(!dashboard.contains("private struct MessageRenderModel"), "MessageRenderModel should be split out of DashboardView")
require(!dashboard.contains("struct NativeSelectableMarkdownView: NSViewRepresentable"), "NSTextView bridge should be split out of DashboardView")
require(!dashboard.contains("struct SelectableMarkdownView: View"), "WKWebView fallback should be split out of DashboardView")
require(!dashboard.contains("enum MarkdownHTML"), "MarkdownHTML conversion should be split out of DashboardView")
require(!renderer.isEmpty, "AssistantMessageRenderer.swift should exist")
require(!selectable.isEmpty, "SelectableMarkdownView.swift should exist")
require(!markdownHTML.isEmpty, "MarkdownHTML.swift should exist")
require(markdownHTML.contains("enum MarkdownHTML"), "MarkdownHTML.swift should own MarkdownHTML")

require(!renderModel.isEmpty, "assistant messages should be parsed through MessageRenderModel")
require(renderModel.contains("enum Renderer"), "MessageRenderModel should expose a renderer enum")
require(!renderModel.contains("A2UI"), "release renderer should not reference A2UI")
require(!renderModel.contains("a2ui"), "release renderer should not contain A2UI render cases")
require(renderModel.contains("case nativeText"), "ordinary native rendering should be one render-model case")
require(renderModel.contains("case webViewFallback"), "WKWebView fallback should be one render-model case")
require(renderModel.contains("let isStreaming: Bool"), "MessageRenderModel should carry streaming state into the renderer")
require(renderModel.contains("static func build(content: String, isStreaming: Bool, allowsRichMarkdown: Bool) -> MessageRenderModel"), "MessageRenderModel should own render decisions")
require(renderModel.contains("MarkdownRenderPolicy.mode("), "MarkdownRenderPolicy should be consumed by the render model")
require(renderModel.contains("for: content"), "MessageRenderModel should pass content to MarkdownRenderPolicy")
require(renderModel.contains("isStreaming: isStreaming"), "MessageRenderModel should pass streaming state to MarkdownRenderPolicy")
require(renderModel.contains("allowsWebView: allowsRichMarkdown"), "MessageRenderModel should pass rich-markdown eligibility to MarkdownRenderPolicy")

require(assistantView.contains("let renderModel = MessageRenderModel.build("), "AssistantMessageContentView should build one render model")
require(assistantView.contains("switch renderModel.renderer"), "AssistantMessageContentView should switch on the render model")
require(assistantView.contains("NativeSelectableMarkdownView("), "ordinary assistant content should use the direct selectable native text renderer")
require(assistantView.contains("case .nativeText"), "AssistantMessageContentView should route ordinary native text separately")
require(assistantView.contains("parsesMarkdown: !renderModel.isStreaming"), "native renderer should skip Markdown parsing while streaming")
require(!assistantView.contains("prefersNativeTextSelection"), "direct text selection should not depend on a single-message selection mode")
require(!assistantView.contains("Markdown(content)"), "assistant rendering should not directly use scattered Markdown(content)")

require(!nativeBridge.isEmpty, "NativeSelectableMarkdownView should exist")
require(nativeBridge.contains("NSViewRepresentable"), "native selectable bridge should wrap AppKit")
require(nativeBridge.contains("NSTextView"), "native selectable bridge should use NSTextView for cross-line selection")
require(nativeBridge.contains("isEditable = false"), "native selectable bridge should be read-only")
require(nativeBridge.contains("isSelectable = true"), "native selectable bridge should allow text selection")
require(nativeBridge.contains("override var acceptsFirstResponder: Bool"), "native selectable text view should be able to receive copy commands")
require(nativeBridge.contains("window?.makeFirstResponder(self)"), "native selectable text view should become first responder when selected")
require(nativeBridge.contains("override func copy(_ sender: Any?)"), "native selectable text view should copy its selected text")
require(nativeBridge.contains("NSPasteboard.general"), "native selectable text view should write selected text to pasteboard")
require(nativeBridge.contains("AttributedString("), "native selectable bridge should still parse lightweight Markdown")
require(nativeBridge.contains("markdown: markdown"), "native selectable bridge should pass markdown source into AttributedString")
require(nativeBridge.contains("if parsesMarkdown"), "native selectable bridge should be able to skip Markdown parsing while streaming")
require(nativeBridge.contains("intrinsicContentSize"), "native selectable bridge should publish dynamic height")
require(nativeBridge.contains("func invalidateMeasuredHeight()"), "native selectable bridge should centralize height invalidation")
require(nativeBridge.contains("cachedIntrinsicHeight"), "native selectable bridge should cache measured intrinsic height")
require(nativeBridge.contains("lastMeasuredWidth"), "native selectable bridge should cache the width used for measurement")
require(!nativeBridge.contains("textView.invalidateIntrinsicContentSize()"), "updateNSView should not directly invalidate intrinsic size on every SwiftUI update")
require(!nativeBridge.contains("override func setFrameSize(_ newSize: NSSize) {\n            super.setFrameSize(newSize)\n            textContainer?.containerSize = NSSize(\n                width: max(newSize.width, 1),\n                height: CGFloat.greatestFiniteMagnitude\n            )\n            invalidateIntrinsicContentSize()"), "setFrameSize should not unconditionally invalidate intrinsic size")

require(!chatView.contains("@State private var activeNativeTextSelectionMessageId: UUID?"), "ChatView should not hold single-message selection mode state")
require(!chatView.contains("activeNativeTextSelectionMessageId:"), "ChatView should not pass single-message selection state into ChatBubble")
require(!chatView.contains("setActiveNativeTextSelectionMessageId"), "ChatView should not centralize a removed single-message selection mode")
require(!chatBubble.contains("@State private var isSelectionModeEnabled"), "ChatBubble should not keep independent per-row selection mode state")
require(!chatBubble.contains("let activeNativeTextSelectionMessageId: UUID?"), "ChatBubble should not receive single-message selection state")
require(!chatBubble.contains("var onSetActiveNativeTextSelectionMessageId: (UUID?) -> Void"), "ChatBubble should not request single-message selection mode changes")
require(!chatBubble.contains("private var isSelectionModeEnabled: Bool"), "ChatBubble should not derive a removed selection mode")
require(!chatBubble.contains("prefersNativeTextSelection:"), "ChatBubble should not pass selection mode into assistant renderer")
require(renderer.contains("NativeSelectableMarkdownView("), "NSTextView bridge should provide direct selection by default")
require(!renderer.contains(".textSelection(.enabled)"), "ordinary assistant renderer should avoid SwiftUI SelectionOverlay")
require(!renderer.contains("A2UICardView("), "release assistant renderer should not render A2UI cards")
require(!renderer.contains("logRenderMode(\"a2ui\")"), "release assistant renderer should not log A2UI render mode")

require(!markdownWebView.contains("window.webkit.messageHandlers.rendered.postMessage"), "WebView fallback should not need a JS postMessage just to mark readiness")
require(!markdownWebView.contains("config.userContentController.add(context.coordinator, name: \"rendered\")"), "WebView fallback should not register a rendered message handler")

print("PASS: assistant message render model and native selectable bridge verified")
