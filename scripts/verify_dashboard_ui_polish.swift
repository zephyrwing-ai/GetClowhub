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

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
        fatalError(message)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let agentListRow = slice(
    dashboard,
    from: "private struct AgentListRow: View",
    to: "// MARK: - Pulsing Dot"
)
let agentSidebarRow = slice(
    dashboard,
    from: "private func agentSidebarRow(_ agent: AgentOption) -> some View",
    to: "private func toggleAgentSelection"
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "private struct ComposerAgentModelSelector: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)
let markdownWebView = slice(
    dashboard,
    from: "private struct _MarkdownWebView: NSViewRepresentable",
    to: "enum MarkdownHTML"
)
let markdownHTML = slice(
    dashboard,
    from: "enum MarkdownHTML",
    to: "#Preview"
)

assertContains(
    dashboard,
    "private enum DashboardTypography",
    "dashboard should centralize scoped chat/sidebar typography"
)
assertContains(
    chatView,
    "DashboardTypography.composer",
    "composer input should use the scoped readable typography"
)
assertContains(
    chatBubble,
    "DashboardTypography.message",
    "plain chat bubbles should use the scoped readable typography"
)
assertContains(
    markdownHTML,
    #"font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;"#,
    "WKWebView markdown should use a Codex/Claude-like system text stack"
)
assertContains(
    markdownHTML,
    "font-size: 14px; color:",
    "WKWebView markdown body text should match the 14pt chat message size"
)
assertNotContains(
    markdownHTML,
    "font-size: 15px; color:",
    "WKWebView markdown body text must not be larger than plain chat messages"
)

assertContains(
    agentListRow,
    "let isExpanded: Bool",
    "agent rows must receive expanded state"
)
assertContains(
    agentListRow,
    #"Image(systemName: "chevron.right")"#,
    "agent row chevron must use a single right chevron icon"
)
assertContains(
    agentListRow,
    ".rotationEffect(.degrees(isExpanded ? 90 : 0))",
    "agent row chevron must rotate down when sessions are expanded"
)
assertContains(
    agentSidebarRow,
    "sidebarAgentHighlightColor(isActive: isActive, isHovering: isHovering)",
    "agent hover/selected background must use the high-grade gray helper"
)
assertContains(
    dashboard,
    "private func sidebarAgentHighlightColor",
    "sidebar must centralize agent hover gray color selection"
)

assertContains(
    markdownWebView,
    "lastRenderedNonEmptySource",
    "WKWebView renderer must track the last non-empty source to avoid blank frames"
)
assertContains(
    markdownWebView,
    "shouldPreserveRenderedContent",
    "WKWebView renderer must guard against replacing rendered content with an empty body"
)
assertContains(
    markdownWebView,
    "if shouldPreserveRenderedContent",
    "WKWebView renderer must skip blank-body injection when preserving content"
)
assertNotContains(
    markdownWebView,
    "webView.loadHTMLString(html, baseURL: nil)\n        context.coordinator.lastSource = content",
    "WKWebView initial load should record rendered source before returning"
)

print("Dashboard UI polish verification passed")
