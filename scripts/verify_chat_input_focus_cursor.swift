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
let subAgents = read("OpenClawInstaller/Views/Agent/SubAgentsTabView.swift")

let typography = slice(
    dashboard,
    from: "enum DashboardTypography",
    to: "struct DashboardView"
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "struct ComposerModelSelector: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)
let createAgentSheet = slice(
    subAgents,
    from: "struct CreateAgentSheet: View",
    to: "// MARK: - SubAgentInfo"
)

assertContains(
    typography,
    "static let userMessage = Font.system(size: 14",
    "user message typography should use the scoped 14pt text size"
)
assertContains(
    chatBubble,
    "fontSize: 14",
    "user chat bubbles should use the scoped 14pt readable text size"
)

assertContains(
    chatView,
    ".tint(Color(NSColor.labelColor))",
    "composer text input should use a neutral text cursor instead of the blue accent cursor"
)
assertContains(
    createAgentSheet,
    ".tint(Color(NSColor.labelColor))",
    "create-agent text fields should use a neutral text cursor instead of the blue accent cursor"
)

assertContains(
    createAgentSheet,
    "private enum CreateAgentFocusedField",
    "create-agent sheet should own explicit focus targets"
)
assertContains(
    createAgentSheet,
    "@FocusState private var focusedField: CreateAgentFocusedField?",
    "create-agent sheet should track focused input locally"
)
assertContains(
    createAgentSheet,
    ".focused($focusedField, equals: .agentId)",
    "create-agent Agent ID field should be focusable via local FocusState"
)
assertContains(
    createAgentSheet,
    "focusedField = .agentId",
    "create-agent sheet should focus Agent ID when presented"
)

assertContains(
    chatView,
    "if let tv = responder as? NSTextView, tv.isFieldEditor {",
    "chat key handler must ignore macOS TextField field editors so create-agent typing does not hit the composer"
)
assertContains(
    chatView,
    "let textView = responder as? NSTextView",
    "composer focus monitor must ignore TextField field editors from overlays"
)
assertContains(
    chatView,
    "!textView.isFieldEditor",
    "composer focus monitor must ignore TextField field editors from overlays"
)

assertContains(
    chatView,
    "private var sendButtonFillColor: SwiftUI.Color",
    "send button active/disabled colors should be centralized"
)
assertContains(
    chatView,
    "? Color.primary.opacity(0.62)",
    "send button should use neutral high-grade gray when text is sendable"
)
assertNotContains(
    chatView,
    "? Color.accentColor\n                                      : Color(NSColor.quaternaryLabelColor)",
    "send button should no longer use the blue accent color for the active state"
)

print("Chat input focus and cursor verification passed")
