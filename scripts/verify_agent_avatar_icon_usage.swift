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
let persona = read("OpenClawInstaller/Views/Agent/PersonaTabView.swift")
let subAgents = read("OpenClawInstaller/Views/Agent/SubAgentsTabView.swift")
let marketplaceOverview = read("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let marketplaceDetail = read("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
let marketplaceAgent = read("OpenClawInstaller/Models/MarketplaceAgent.swift")
let avatarContents = read("OpenClawInstaller/Assets.xcassets/AgentAvatar.imageset/Contents.json")
let avatarView = read("OpenClawInstaller/Views/Shared/AgentAvatarImage.swift")
let agentDaySVG = read("OpenClawInstaller/Assets.xcassets/AgentAvatar.imageset/agent-day.svg")
let agentNightSVG = read("OpenClawInstaller/Assets.xcassets/AgentAvatar.imageset/agent-night.svg")

let collapsedPanel = slice(dashboard, from: "private var collapsedBody: some View", to: "private var edgeChevronHandle: some View")
let agentCard = slice(dashboard, from: "private var agentCard: some View", to: "} label: {")
let agentSettingsPanel = slice(dashboard, from: "private struct AgentSettingsPanel: View", to: "Button(action: onClose)")
let marketplaceRow = slice(dashboard, from: "private struct MarketplaceAgentRow: View", to: "private struct PulsingDot: View")
let agentSectionContent = slice(dashboard, from: "private var agentSectionContent: some View", to: "// MARK: - Sidebar Bottom Bar")
let agentSidebarRow = slice(dashboard, from: "private func agentSidebarRow(_ agent: AgentOption) -> some View", to: "private func agentRowWithContextMenu")
let sidebarCollapsibleRow = slice(dashboard, from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View", to: "// MARK: - Pulsing Dot")
let identityCard = slice(persona, from: "struct IdentityCardView: View", to: "VStack(alignment: .leading, spacing: 4)")
let activityContent = slice(dashboard, from: "private var activityContent: some View", to: "// MARK: - Sub-blocks")
let subAgentCard = slice(subAgents, from: "private struct AgentSummaryCard: View", to: "// Name")
let subAgentDetail = slice(subAgents, from: "private struct AgentDetailPanel: View", to: "VStack(alignment: .leading, spacing: 2)")
let marketplaceOverviewCard = slice(marketplaceOverview, from: "private struct AgentCard: View", to: "VStack(alignment: .leading, spacing: 2)")
let marketplaceDetailHeader = slice(marketplaceDetail, from: "private var headerSection: some View", to: "VStack(alignment: .leading, spacing: 6)")

assertContains(
    avatarView,
    #"Image("AgentAvatar")"#,
    "shared agent avatar must render the unified AgentAvatar asset"
)
assertNotContains(
    avatarView,
    ".interpolation(.high)",
    "shared agent avatar must not use high bitmap interpolation for SVG"
)
assertContains(
    agentDaySVG,
    #"viewBox="0 0 24 24""#,
    "light agent SVG must use a small 24x24 coordinate system for crisp sidebar rendering"
)
assertContains(
    agentNightSVG,
    #"viewBox="0 0 24 24""#,
    "dark agent SVG must use a small 24x24 coordinate system for crisp sidebar rendering"
)
assertContains(
    agentDaySVG,
    #"stroke-width="1.8""#,
    "light agent SVG stroke must stay crisp after shrinking in AgentsMarket rows"
)
assertContains(
    agentNightSVG,
    #"stroke-width="1.8""#,
    "dark agent SVG stroke must stay crisp after shrinking in AgentsMarket rows"
)
assertContains(
    agentDaySVG,
    ##"fill="#F9F9F7""##,
    "light agent SVG must use a soft light-mode avatar fill"
)
assertContains(
    agentNightSVG,
    ##"fill="#222522""##,
    "dark agent SVG must use a quiet dark-mode avatar fill"
)
for path in [
    #"M12 12 L6.0 6.8"#,
    #"M12 12 L18.1 6.7"#,
    #"M12 12 L12 20.1"#
] {
    assertContains(
        agentDaySVG,
        path,
        "light agent SVG must use center-to-edge orchestration lines"
    )
    assertContains(
        agentNightSVG,
        path,
        "dark agent SVG must use center-to-edge orchestration lines"
    )
}
assertContains(
    agentDaySVG,
    #"r="2.35""#,
    "light agent SVG must include a single filled center node"
)
assertContains(
    agentNightSVG,
    #"r="2.35""#,
    "dark agent SVG must include a single filled center node"
)
assertNotContains(
    agentDaySVG,
    #"r="6""#,
    "light agent SVG must no longer use the old middle concentric ring"
)
assertNotContains(
    agentNightSVG,
    #"r="6""#,
    "dark agent SVG must no longer use the old middle concentric ring"
)
assertNotContains(
    agentDaySVG,
    #"r="3""#,
    "light agent SVG must no longer use the old inner concentric ring"
)
assertNotContains(
    agentNightSVG,
    #"r="3""#,
    "dark agent SVG must no longer use the old inner concentric ring"
)
assertNotContains(
    agentDaySVG,
    ##"fill="#151515""##,
    "light agent SVG must be line-only, not a filled disk"
)
assertNotContains(
    agentNightSVG,
    ##"fill="#ffffff""##,
    "dark agent SVG must avoid a pure-white filled disk"
)
assertContains(
    avatarContents,
    #"agent-day.svg"#,
    "AgentAvatar asset must include the light-mode SVG"
)
assertContains(
    avatarContents,
    #"agent-night.svg"#,
    "AgentAvatar asset must include the dark-mode SVG"
)
assertContains(
    avatarContents,
    #""appearance" : "luminosity""#,
    "AgentAvatar asset must use luminosity appearance variants"
)
assertNotContains(
    avatarContents,
    #"agent-avatar-concentric-circles.svg"#,
    "AgentAvatar asset must not point at the old SVG"
)
assertNotContains(
    avatarContents,
    #"agent-avatar-unified-dark.png"#,
    "AgentAvatar asset must not point at the replaced PNG"
)
assertContains(
    agentSectionContent,
    ".opacity(isAgentSectionHeaderHovering ? 1 : 0)",
    "Agent section plus button must reserve layout space and fade on hover"
)
assertContains(
    agentSectionContent,
    ".rotationEffect(.degrees(areAgentsCollapsed ? 0 : 90))",
    "Agent section title chevron must rotate between collapsed and expanded states"
)
assertContains(
    agentSidebarRow,
    "AgentAvatarImage(size: DashboardSidebarMetrics.agentAvatarSize)",
    "agent sidebar rows must use the shared SVG avatar metric"
)
assertContains(
    agentSidebarRow,
    ".contextMenu",
    "agent sidebar rows must expose context menus from the full row wrapper"
)
assertContains(
    agentSidebarRow,
    #"Label("Remove Agent", systemImage: "trash")"#,
    "agent sidebar row context menu must keep the custom agent delete action"
)
assertContains(
    sidebarCollapsibleRow,
    ".contentShape(Rectangle())",
    "agent sidebar rows must keep a full-width hit target for taps and context menus"
)
assertContains(
    sidebarCollapsibleRow,
    ".opacity(isHovering || isExpanded ? 1 : 0)",
    "agent row chevron must reserve layout space and fade on hover or expanded state"
)
assertContains(
    sidebarCollapsibleRow,
    ".opacity(isHovering ? 1 : 0)",
    "agent row plus button must reserve layout space and fade on hover"
)
assertContains(
    marketplaceRow,
    "AgentAvatarImage(size: 26)",
    "AgentsMarket list rows must use a large enough avatar for the agent mark"
)

for (name, source) in [
    ("collapsed details panel", collapsedPanel),
    ("expanded current agent card", agentCard),
    ("agent settings panel header", agentSettingsPanel),
    ("activity panel item", activityContent),
    ("marketplace agent row", marketplaceRow),
    ("persona identity card", identityCard),
    ("sub-agent card", subAgentCard),
    ("sub-agent detail header", subAgentDetail),
    ("marketplace overview card", marketplaceOverviewCard),
    ("marketplace detail header", marketplaceDetailHeader)
] {
    assertContains(source, "AgentAvatarImage(", "\(name) must use the shared agent avatar")
    assertNotContains(source, ".emoji", "\(name) must not render emoji data as the agent icon")
}

assertNotContains(
    dashboard,
    #"Label("\(a.emoji) \(a.name)", systemImage: "checkmark")"#,
    "agent picker must not include emoji data in menu labels"
)
assertNotContains(
    dashboard,
    #"Text("\(a.emoji) \(a.name)")"#,
    "agent picker must not include emoji data in menu labels"
)
assertNotContains(
    subAgents,
    #"- **Emoji:**"#,
    "new agent identity files must not write emoji data"
)
assertNotContains(
    subAgents,
    "emojiForName",
    "new agent creation must not synthesize emoji data"
)
assertNotContains(
    marketplaceAgent,
    #"- **Emoji:**"#,
    "marketplace installs must not write emoji data into IDENTITY.md"
)

print("Agent avatar icon usage verification passed")
