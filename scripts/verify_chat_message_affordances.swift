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
let backgroundTaskNotification = slice(
    dashboard,
    from: "struct BackgroundTaskNotification: View",
    to: "// MARK: - Thinking Indicator with Background Timer"
)
let thinkingIndicator = slice(
    dashboard,
    from: "struct ThinkingIndicator: View",
    to: "// MARK: - Chat Bubble"
)

assertContains(
    chatView,
    #".onChange(of: viewModel.composerPrefill)"#,
    "ChatView must observe rewind composer prefill events"
)
assertContains(
    chatView,
    "inputText = prefill",
    "rewind prefill must write the original prompt back into the composer"
)
assertContains(
    chatView,
    "viewModel.composerPrefill = nil",
    "rewind prefill must clear the one-shot event after consumption"
)
assertContains(
    chatView,
    "isInputFocused = true",
    "rewind prefill must focus the composer for editing"
)

assertNotContains(
    chatBubble,
    "Timestamp — small, secondary, sits above the message body.",
    "message timestamps must not render as always-visible text above bubbles"
)
assertContains(
    chatBubble,
    "if let ts = message.timestamp",
    "hover action row must still render a timestamp when available"
)
assertContains(
    chatBubble,
    "Self.formatTimestamp(ts)",
    "hover action row must use the existing timestamp formatter"
)
assertContains(
    chatBubble,
    #".opacity(isHovering || copied ? 1.0 : 0.0)"#,
    "copy, rewind, and timestamp row must remain hover-driven"
)

assertNotContains(
    backgroundTaskNotification,
    "brain.head.profile",
    "assistant/background message status rows must not render a fallback assistant avatar"
)
assertNotContains(
    backgroundTaskNotification,
    "message.agentEmoji",
    "assistant/background message status rows must not render an agent emoji avatar"
)
assertNotContains(
    thinkingIndicator,
    "brain.head.profile",
    "assistant thinking rows must not render a fallback assistant avatar"
)
assertNotContains(
    thinkingIndicator,
    "message.agentEmoji",
    "assistant thinking rows must not render an agent emoji avatar"
)

print("Chat message affordance verification passed")
