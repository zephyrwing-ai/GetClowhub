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
let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let sessionRow = slice(dashboard, from: "struct ChatSessionRow: View", to: "/// Compact form for inline sidebar display.")
let sidebarMainList = slice(dashboard, from: "private var sidebarMainList: some View", to: "private func navRow")

assertNotContains(
    dashboard,
    #"String(localized: "Chat History""#,
    "selected agent sessions must not render a Chat History heading"
)
assertContains(
    dashboard,
    "AgentAvatarImage(size: 24)",
    "agent sidebar rows must use the shared SVG avatar asset"
)
assertContains(
    sidebarMainList,
    "onOpenGlobalSessionSearch()",
    "left sidebar must expose the global chat search entry point"
)
assertContains(
    sidebarMainList,
    #"sidebarRowContent(title: String(localized: "Search chats""#,
    "left sidebar search entry must be a standalone Search chats row"
)
assertContains(
    dashboard,
    "onCreateSession: { createSession(for: agent) }",
    "agent hover plus must create a new session for that agent"
)
assertContains(
    dashboard,
    #"@State private var expandedAgentIds: Set<String> = []"#,
    "sidebar must remember per-agent expanded session state in a Set"
)
assertContains(
    dashboard,
    "expandedAgentIds.contains(agent.id)",
    "selected agent sessions must render from remembered expanded state"
)
assertNotContains(
    dashboard,
    "if viewModel.selectedAgentId == agent.id && selectedTab == .chat {",
    "selecting an agent must not automatically expand its sessions"
)
assertContains(
    dashboard,
    "private func toggleAgentSelection(_ agent: AgentOption)",
    "agent clicks must route through a helper that toggles expansion on repeated clicks"
)
assertContains(
    dashboard,
    #".transition(.move(edge: .top).combined(with: .opacity))"#,
    "agent session lists must animate when expanding or collapsing"
)
assertContains(
    dashboard,
    #".animation(.spring(response: 0.28, dampingFraction: 0.86), value: expandedAgentIds)"#,
    "agent session expansion must use a spring layout animation"
)
assertContains(
    dashboard,
    "Image(systemName: \"plus\")",
    "agent rows must expose a hover plus affordance"
)
assertContains(
    dashboard,
    "Image(systemName: \"chevron.right\")",
    "agent rows must expose a hover chevron affordance"
)
assertContains(
    dashboard,
    #"let isHovering = hoveredAgentId == agent.id"#,
    "agent row hover state must drive both row chrome and hover affordances"
)
assertContains(
    dashboard,
    #".padding(.vertical, 3)"#,
    "agent highlight height must be reduced vertically from the previous 44pt row"
)
assertContains(
    dashboard,
    "private func createSession(for agent: AgentOption)",
    "sidebar must route per-agent new-session creation through a named helper"
)
assertContains(
    viewModel,
    "func createNewSession(forAgent agentId: String) -> UUID",
    "view model must support creating a session for an explicit agent"
)
assertContains(
    viewModel,
    "selectedAgentId = agentId",
    "explicit per-agent session creation must switch the selected agent"
)

assertNotContains(
    sessionRow,
    "bubble.left",
    "session rows must not show the default chat bubble icon"
)
assertNotContains(
    sessionRow,
    "pin.fill",
    "session rows must not show a leading pin icon"
)
assertContains(
    sessionRow,
    "Text(meta.title.isEmpty",
    "session rows must keep the session title as the primary visible content"
)

print("Agent sidebar session verification passed")
