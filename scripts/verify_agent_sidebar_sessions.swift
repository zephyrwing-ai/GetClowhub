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
let scrollbarDesign = read("DesignSystems/scrollbar/DESIGN.md")
let sessionRow = slice(dashboard, from: "struct ChatSessionRow: View", to: "/// Compact form for inline sidebar display.")
let sidebarMainList = slice(dashboard, from: "private var sidebarMainList: some View", to: "private func navRow")
let navRow = slice(dashboard, from: "private func navRow", to: "private func sidebarRowContent")
let agentSectionContent = slice(dashboard, from: "private var agentSectionContent: some View", to: "// MARK: - Sidebar Bottom Bar")
let sessionsSectionContent = slice(dashboard, from: "private func sessionsSectionContent(for agent: AgentOption) -> some View", to: "// MARK: - Agent Section Content")
let agentSidebarRow = slice(dashboard, from: "private func agentSidebarRow(_ agent: AgentOption) -> some View", to: "private func agentRowWithContextMenu")
let sidebarCollapsibleRow = slice(dashboard, from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View", to: "// MARK: - Pulsing Dot")

assertNotContains(
    dashboard,
    #"String(localized: "Chat History""#,
    "selected agent sessions must not render a Chat History heading"
)
assertContains(
    agentSidebarRow,
    "AgentAvatarImage(size: DashboardSidebarMetrics.agentAvatarSize, isExpanded: expandedAgentIds.contains(agent.id))",
    "agent sidebar rows must use the shared SVG avatar metric and expanded-state icon"
)
assertContains(
    sidebarCollapsibleRow,
    "HStack(spacing: DashboardSidebarMetrics.agentTitleSpacing)",
    "agent title spacing should use the shared sidebar metric"
)
assertContains(
    dashboard,
    "static let sessionRowContentHeight: CGFloat = 20",
    "session row vertical content height should be 20pt"
)
assertContains(
    dashboard,
    "static let sessionRowActionSize: CGFloat = 20",
    "session row hover action should use the same 20pt vertical size"
)
assertContains(
    dashboard,
    "static let sessionRowVerticalPadding: CGFloat = 4",
    "session row background should use a slimmer vertical padding"
)
assertContains(
    dashboard,
    "static let sessionTitleLeadingSpacer: CGFloat = agentAvatarSize + agentTitleSpacing",
    "session title spacer should match the agent icon area so text aligns with agent names"
)
assertContains(
    dashboard,
    "static let sidebarSectionTitle = Font.system(size: 14, weight: .regular)",
    "sidebar section titles should use the shared typography token"
)
assertContains(
    agentSectionContent,
    ".font(DashboardTypography.sidebarSectionTitle)",
    "Agent section title should use the shared larger typography token"
)
assertContains(
    agentSectionContent,
    #"Image(systemName: "chevron.right")"#,
    "Agent section title should show a chevron next to the title"
)
assertContains(
    agentSectionContent,
    ".rotationEffect(.degrees(areAgentsCollapsed ? 0 : 90))",
    "Agent section title chevron should rotate down when expanded"
)
assertContains(
    agentSectionContent,
    ".rotationEffect(.degrees(areAgentsCollapsed ? 0 : 90))\n                    .opacity(isAgentSectionHeaderHovering ? 1 : 0)",
    "Agent section title chevron should be a hover affordance instead of always visible"
)
assertContains(
    dashboard,
    "@State private var isAgentSectionHeaderHovering = false",
    "Agent section header should track hover for the title-row plus button"
)
assertContains(
    agentSectionContent,
    ".opacity(isAgentSectionHeaderHovering ? 1 : 0)",
    "Agent section title plus button should fade while hovering the title row"
)
assertContains(
    agentSectionContent,
    ".overlay(alignment: .trailing)",
    "Agent section title plus button should float as a trailing overlay instead of occupying title layout"
)
assertContains(
    agentSectionContent,
    ".frame(height: 20)",
    "Agent section title row should keep a stable height when hover controls appear"
)
assertContains(
    agentSectionContent,
    ".animation(.easeInOut(duration: 0.12), value: isAgentSectionHeaderHovering)",
    "Agent section title plus button should fade smoothly on hover"
)
assertContains(
    sidebarMainList,
    "SmoothScrollView {",
    "left sidebar main list should use the shared SmoothScrollView component"
)
assertNotContains(
    sidebarMainList,
    "\n        ScrollView {",
    "left sidebar main list should not use a raw ScrollView"
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
    "private func cancelSessionDeleteConfirmation()",
    "sidebar should centralize canceling pending session delete confirmation"
)
assertContains(
    sidebarMainList,
    "cancelSessionDeleteConfirmation()\n                    viewModel.createNewSession()\n                    selectedTab = .chat",
    "New chat should cancel pending delete confirmation and still switch the main pane to chat"
)
assertContains(
    sidebarMainList,
    "cancelSessionDeleteConfirmation()\n                    onOpenGlobalSessionSearch()",
    "Search chats should cancel pending delete confirmation before opening search"
)
assertContains(
    navRow,
    "cancelSessionDeleteConfirmation()\n            selectedTab = tab",
    "sidebar navigation rows should cancel pending delete confirmation and still switch to their tab"
)
assertContains(
    agentSidebarRow,
    "createSession(for: agent)",
    "agent hover plus must create a new session for that agent"
)
assertContains(
    dashboard,
    #"@State private var expandedAgentIds: Set<String> = []"#,
    "sidebar must remember per-agent expanded session state in a Set"
)
assertContains(
    dashboard,
    #"@State private var areAgentsCollapsed = false"#,
    "sidebar must remember whether the Agent title has collapsed the agent list"
)
assertContains(
    dashboard,
    "toggleAgentSectionCollapse()",
    "Agent title clicks must route through a helper that toggles the whole agent list"
)
assertContains(
    dashboard,
    "if !areAgentsCollapsed {",
    "Agent title collapse must hide the agent rows below the section title"
)
assertContains(
    dashboard,
    #".animation(.spring(response: 0.28, dampingFraction: 0.86), value: areAgentsCollapsed)"#,
    "Agent title collapse must use a spring layout animation"
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
    sidebarCollapsibleRow,
    ".spring(response: 0.28, dampingFraction: 0.86)",
    "agent session expansion must use a spring layout animation"
)
assertContains(
    agentSidebarRow,
    "Image(systemName: \"plus\")",
    "agent rows must expose a hover plus affordance"
)
assertContains(
    sidebarCollapsibleRow,
    "Image(systemName: \"chevron.right\")",
    "agent rows must expose a hover chevron affordance"
)
assertContains(
    sidebarCollapsibleRow,
    #"@State private var isHovering = false"#,
    "agent row hover state must drive both row chrome and hover affordances"
)
assertContains(
    dashboard,
    "@State private var hoveredSessionId: UUID?",
    "session row hover state should be owned by the sidebar so row background and actions stay in sync"
)
assertContains(
    agentSidebarRow,
    #"verticalPadding: 4"#,
    "agent highlight height must be reduced vertically from the previous 44pt row"
)
assertContains(
    sessionsSectionContent,
    "let isSessionHovering = hoveredSessionId == meta.id",
    "session rows should derive a stable hover flag for background and actions"
)
assertContains(
    sessionsSectionContent,
    "isHovering: isSessionHovering",
    "session row hover affordances should use the same hover state as the row background"
)
assertContains(
    sessionsSectionContent,
    ".fill(sessionRowHighlightColor(isActive: isSessionActive, isHovering: isSessionHovering))",
    "session rows should use the dedicated advanced-gray hover and active highlight color"
)
assertContains(
    sessionRow,
    "Color.clear\n                .frame(width: DashboardSidebarMetrics.sessionTitleLeadingSpacer)",
    "session row text should reserve the agent avatar column so session titles align with agent titles"
)
assertContains(
    sessionRow,
    "HStack(spacing: 0)",
    "session title spacer should not add an extra HStack gap before the title"
)
assertContains(
    sessionsSectionContent,
    ".padding(.vertical, DashboardSidebarMetrics.sessionRowVerticalPadding)",
    "session row background vertical padding should use the shared compact metric"
)
assertContains(
    sessionsSectionContent,
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "session row background should fill the available row width without horizontal inset"
)
assertNotContains(
    sessionsSectionContent,
    ".padding(.trailing, DashboardSidebarMetrics.sessionRowTrailingInset)",
    "session row background should not be narrowed from the trailing edge"
)
assertNotContains(
    sessionsSectionContent,
    ".padding(.leading, DashboardSidebarMetrics.sessionRowBackgroundLeadingInset)",
    "session row background should not be horizontally inset"
)
assertNotContains(
    sessionsSectionContent,
    ".padding(.leading, 16)",
    "session row background should not be shifted right"
)
assertNotContains(
    agentSectionContent,
    ".padding(.leading, 10)",
    "expanded session list should not be horizontally indented by its parent container"
)
assertNotContains(
    dashboard,
    "sessionRowTrailingInset",
    "session row should not define any horizontal inset metric"
)
assertContains(
    dashboard,
    "private func sessionRowHighlightColor(isActive: Bool, isHovering: Bool) -> SwiftUI.Color",
    "session rows should have a named quiet gray highlight helper"
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
assertContains(
    scrollbarDesign,
    "# Scrollbar Design System",
    "scrollbar design system folder should document the reusable scrollbar component"
)
assertContains(
    scrollbarDesign,
    "SmoothScrollView",
    "scrollbar design system should name the reusable SwiftUI component"
)

assertNotContains(
    sessionRow,
    "bubble.left",
    "session rows must not show the default chat bubble icon"
)
assertNotContains(
    slice(sessionRow, from: "HStack(spacing: 0) {", to: "HStack(spacing: 2)"),
    "pin",
    "session rows must not show a leading pin icon before the title"
)
assertContains(
    sessionRow,
    #"Image(systemName: meta.isPinned ? "pin.fill" : "pin")"#,
    "session row hover actions should include a pin/unpin icon"
)
assertNotContains(
    sessionRow,
    "meta.isPinned ? .accentColor : .secondary",
    "pinned session action should use pin.fill for state instead of turning blue"
)
assertContains(
    sessionRow,
    "Text(meta.title.isEmpty",
    "session rows must keep the session title as the primary visible content"
)
assertContains(
    sessionRow,
    ".frame(height: DashboardSidebarMetrics.sessionRowContentHeight)",
    "session rows must keep a stable vertical content height when hover actions appear"
)
assertContains(
    sessionRow,
    ".frame(width: DashboardSidebarMetrics.sessionRowActionSize, height: DashboardSidebarMetrics.sessionRowActionSize)",
    "session row hover action should share the stable row action metric"
)
assertContains(
    sessionRow,
    ".frame(width: DashboardSidebarMetrics.sessionRowActionAreaWidth, alignment: .trailing)",
    "session row hover actions should reserve fixed trailing layout space"
)
assertContains(
    sessionRow,
    ".opacity(isHovering || isDeleteConfirming ? 1 : 0)",
    "session row hover action must fade in without changing layout"
)
assertNotContains(
    sessionRow,
    "if isHovering || isDeleteConfirming {",
    "session row hover action must not be conditionally inserted into the layout"
)

print("Agent sidebar session verification passed")
