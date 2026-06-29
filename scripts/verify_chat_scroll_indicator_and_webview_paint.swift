#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboard = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift"),
    encoding: .utf8
)
let chatTimelineSurfaceSource = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift"),
    encoding: .utf8
)
let selectableSource = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift"),
    encoding: .utf8
)
let smoothScrollView = try String(
    contentsOf: root.appendingPathComponent("OpenClawInstaller/Views/Shared/SmoothScrollView.swift"),
    encoding: .utf8
)

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

let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "// MARK: - Chat Bubble"
)
let timelineSurface = slice(
    dashboard,
    from: "private var timelineChatSurface: some View",
    to: "private func composerArea"
)
let timelineSurfaceView = slice(
    chatTimelineSurfaceSource,
    from: "struct ChatTimelineSurface: View",
    to: "***END***"
)
let scrollContent = slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands"
)
let selectableMarkdown = slice(
    selectableSource,
    from: "struct SelectableMarkdownView: View",
    to: "/// WKWebView subclass"
)
let markdownWebView = slice(
    selectableSource,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "***END***"
)

require(!chatView.contains("@State private var showChatScrollIndicator"), "chat view should not own custom scroll indicator visibility when native indicators are enabled")
require(!chatView.contains("@State private var chatScrollIndicatorHideTask"), "chat view should not debounce a custom scroll indicator hide when native indicators are enabled")
require(!chatView.contains("@State private var chatScrollOffset"), "chat view should not track continuous scroll offset")
require(!chatView.contains("@State private var chatScrollViewportHeight"), "chat view should not track continuous viewport height")
require(!chatView.contains("@State private var chatScrollContentHeight"), "chat view should not track continuous content height")
require(!chatView.contains("private let chatScrollOffsetUpdateStep"), "chat scroll should not need offset quantization after geometry writeback removal")
require(!chatView.contains("private let chatScrollSizeMetricEpsilon"), "chat scroll should not need size metric thresholds after geometry writeback removal")

require(!timelineSurface.contains("chatScrollIndicator"), "timeline surface should not overlay a custom chat scroll indicator")
require(!chatView.contains("private var chatScrollIndicator: some View"), "chat view should not define a custom chat scroll indicator")
require(!chatView.contains("showTransientChatScrollIndicator()"), "scroll wheel handling should not show a custom chat scroll indicator")
require(!chatView.contains("chatScrollIndicatorHideTask"), "scroll wheel handling should not schedule custom indicator hiding")
require(!chatView.contains(".animation(.easeOut(duration: 0.08), value: chatScrollOffset)"), "custom scroll indicator should not animate every scroll-offset state update")

require(
    scrollContent.contains("ScrollView(showsIndicators: true)") ||
        timelineSurfaceView.contains("ScrollView(showsIndicators: true)"),
    "native chat scroll indicators should be shown"
)
require(!scrollContent.contains(".coordinateSpace(name: \"chatScrollSpace\")"), "chat scroll should not expose a coordinate space just for indicator metrics")
require(!scrollContent.contains("ChatScrollContentMetricsKey"), "chat scroll content should not publish offset/content metrics")
require(!scrollContent.contains("ChatScrollViewportHeightKey"), "chat scroll view should not publish viewport height")
require(!chatView.contains("quantizedChatScrollOffset"), "chat scroll should not compute quantized offset state")

require(!dashboard.contains("private struct ChatScrollContentMetrics: Equatable"), "chat scroll metrics value should not exist")
require(!dashboard.contains("private struct ChatScrollContentMetricsKey: PreferenceKey"), "content metrics preference key should not exist")
require(!dashboard.contains("private struct ChatScrollViewportHeightKey: PreferenceKey"), "viewport height preference key should not exist")

require(smoothScrollView.contains("struct SmoothScrollView<Content: View>: View"), "shared SmoothScrollView component should exist")
require(smoothScrollView.contains("ScrollView(axes, showsIndicators: false)"), "SmoothScrollView should hide native scroll indicators")
require(smoothScrollView.contains("let indicatorHeight: CGFloat = 38"), "SmoothScrollView should use the standard 38pt indicator height")
require(smoothScrollView.contains(".frame(width: 3, height: indicatorHeight)"), "SmoothScrollView indicator should use the standard 3pt width")
require(smoothScrollView.contains("indicatorHideTask"), "SmoothScrollView should debounce indicator hiding")
require(smoothScrollView.contains("SmoothScrollContentMetricsKey"), "SmoothScrollView should own reusable scroll metrics preference keys")

require(selectableMarkdown.contains("@State private var pendingWebViewReadyTask: DispatchWorkItem?"), "selectable markdown should debounce WebView readiness")
require(selectableMarkdown.contains("markWebViewReadyAfterPaint()"), "selectable markdown should wait before removing fallback")
require(selectableMarkdown.contains("pendingWebViewReadyTask?.cancel()"), "selectable markdown should cancel stale ready tasks")
require(!selectableMarkdown.contains("withAnimation(.easeInOut(duration: 0.12)) {\n                            isWebViewReady = true"), "fallback should not be removed directly inside onRendered")

require(markdownWebView.contains("self.applyHeight(newHeight)"), "WKWebView should apply measured height before marking content rendered")
require(markdownWebView.contains("self.onRendered?()"), "WKWebView should mark rendered from the native measurement path")
require(!markdownWebView.contains("notifyRenderedAfterPaint(webView: webView)"), "WKWebView should not require a separate JS paint notification")
require(!markdownWebView.contains("requestAnimationFrame"), "WKWebView readiness should not add extra JS animation-frame callbacks")
require(!markdownWebView.contains("window.webkit.messageHandlers.rendered.postMessage"), "WKWebView should not post rendered messages through JS")
require(!markdownWebView.contains("config.userContentController.add(context.coordinator, name: \"rendered\")"), "WKWebView should not register a rendered script handler")

print("PASS: native chat scroll indicators and WKWebView paint-ready contracts verified")
