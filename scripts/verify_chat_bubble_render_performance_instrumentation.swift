import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fatalError(message)
    }
}

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start) else {
        fatalError("Could not slice \(start) -> \(end)")
    }
    if end == "***END***" {
        return String(text[startRange.lowerBound..<text.endIndex])
    }
    guard let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        fatalError("Could not slice \(start) -> \(end)")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let renderer = read("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")
let selectableSource = read("OpenClawInstaller/Views/Dashboard/SelectableMarkdownView.swift")
let chatBubble = slice(dashboard, from: "struct ChatBubble: View", to: "private struct InlineUserMessageEditor: View")
let assistantContent = slice(renderer, from: "struct AssistantMessageContentView: View", to: "// MARK: - Native Markdown View")
let selectableMarkdown = slice(selectableSource, from: "struct SelectableMarkdownView: View", to: "private class ScrollThroughWebView")
let markdownWebView = slice(selectableSource, from: "private struct _MarkdownWebView: NSViewRepresentable", to: "***END***")

assertContains(
    renderer,
    "func dashboardElapsedMillisecondsText(since start: ContinuousClock.Instant) -> String",
    "dashboard should expose a shared elapsed-time formatter for render instrumentation"
)
assertContains(
    chatBubble,
    #"phase=bubble_appear"#,
    "chat bubble should log when a visible message row appears"
)
assertContains(
    chatBubble,
    #"content_length="#,
    "chat bubble logs should include content length, not raw content"
)
assertContains(
    chatBubble,
    #"attachment_count="#,
    "chat bubble logs should include attachment count"
)
assertContains(
    assistantContent,
    #"phase=assistant_content_render_mode mode=\(mode"#,
    "assistant content should log render mode through the shared helper"
)
assertContains(
    assistantContent,
    #"logRenderMode("webview")"#,
    "assistant content should log WebView render mode"
)
assertContains(
    assistantContent,
    #"logRenderMode("native_selectable")"#,
    "assistant content should log lightweight native text render mode"
)
assertContains(
    selectableMarkdown,
    "webViewMountStart",
    "selectable markdown should track WebView mount start time"
)
assertContains(
    selectableMarkdown,
    #"phase=webview_markdown_ready"#,
    "selectable markdown should log when WebView content becomes visible"
)
assertContains(
    selectableMarkdown,
    #"phase=webview_height_changed"#,
    "selectable markdown should log measured height changes"
)
assertContains(
    markdownWebView,
    "measureStart",
    "markdown WebView coordinator should time JS height measurement"
)
assertContains(
    markdownWebView,
    #"phase=webview_measure_height"#,
    "markdown WebView coordinator should log height measurement attempts"
)
assertContains(
    markdownWebView,
    #"phase=webview_measure_retry"#,
    "markdown WebView coordinator should log width-not-ready retries"
)

print("Chat bubble render performance instrumentation checks passed")
