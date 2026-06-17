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

let titleToolbar = slice(
    dashboard,
    from: #".toolbar {"#,
    to: #".alert("Error""#
)
let titlePopoverView = slice(
    dashboard,
    from: "private struct SessionTitlePopoverView: View",
    to: "// MARK: - Input Mode Picker"
)

assertContains(
    titleToolbar,
    "SessionTitlePopoverView(",
    "conversation title must use the custom hover popover title view"
)
assertContains(
    titleToolbar,
    "messages: currentSessionUserMessages",
    "conversation title popover must receive current session user messages"
)
assertNotContains(
    titleToolbar,
    ".allowsHitTesting(false)",
    "conversation title must be interactive for hover popover behavior"
)

assertContains(
    dashboard,
    "private var currentSessionUserMessages: [ChatMessage]",
    "DashboardView must expose filtered user messages for the active session title popover"
)
assertContains(
    dashboard,
    ".filter { $0.role == .user",
    "title popover message source must filter to user messages only"
)

assertContains(
    titlePopoverView,
    "@State private var hoverOpenTask: Task<Void, Never>?",
    "title popover must keep a cancellable hover-delay task"
)
assertContains(
    titlePopoverView,
    "try? await Task.sleep(nanoseconds: 300_000_000)",
    "title popover must wait 300ms before opening on hover"
)
assertContains(
    titlePopoverView,
    "hoverOpenTask?.cancel()",
    "title popover must cancel pending hover opens when pointer leaves"
)
assertContains(
    titlePopoverView,
    ".popover(isPresented: $isPopoverPresented",
    "title popover must use an interactive popover instead of a system tooltip"
)
assertContains(
    titlePopoverView,
    "ScrollView",
    "title popover content must be scrollable for long sessions"
)
assertContains(
    titlePopoverView,
    "LazyVStack",
    "title popover content must render user messages as a list"
)
assertContains(
    titlePopoverView,
    "ForEach(messages) { message in",
    "title popover must preserve message identity for future jump behavior"
)
assertContains(
    titlePopoverView,
    "onTapMessage(message)",
    "title popover rows must expose a future message-selection hook"
)
assertContains(
    titlePopoverView,
    ".frame(width: 360)",
    "title popover must use a stable readable width"
)
assertContains(
    titlePopoverView,
    ".frame(maxHeight: 320)",
    "title popover must cap height so long sessions scroll"
)

print("Session title user messages popover source verification passed")
