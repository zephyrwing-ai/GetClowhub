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
let agentSection = slice(
    dashboard,
    from: "private var agentSectionContent: some View",
    to: "// MARK: - Sidebar Bottom Bar"
)
let expandedSessionBlock = slice(
    agentSection,
    from: "if expandedAgentIds.contains(agent.id) {",
    to: ".animation(.spring(response: 0.28, dampingFraction: 0.86), value: expandedAgentIds)"
)

assertNotContains(
    expandedSessionBlock,
    ".transition(.move(edge: .top).combined(with: .opacity))",
    "collapsing agent session rows must not move old titles during removal"
)
assertContains(
    expandedSessionBlock,
    ".transition(.asymmetric(insertion: .opacity, removal: .identity))",
    "session rows should disappear immediately on collapse while keeping insertion soft"
)

print("Agent session collapse ghosting checks passed")
