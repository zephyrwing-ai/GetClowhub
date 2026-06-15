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

func assertBefore(_ haystack: String, _ first: String, _ second: String, _ message: String) {
    guard
        let firstRange = haystack.range(of: first),
        let secondRange = haystack.range(of: second),
        firstRange.lowerBound < secondRange.lowerBound
    else {
        fatalError(message)
    }
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let metrics = read("OpenClawInstaller/Views/Dashboard/OutputsSidebarLayoutMetrics.swift")
let layoutScript = read("scripts/verify_outputs_sidebar_layout.swift")

assertContains(
    dashboard,
    #"String(localized: "No matching skills", bundle: LanguageManager.shared.localizedBundle)"#,
    "skills empty-state label must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "No matching agents", bundle: LanguageManager.shared.localizedBundle)"#,
    "agents empty-state label must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "Do Anything", bundle: LanguageManager.shared.localizedBundle)"#,
    "composer placeholder must use the active language bundle"
)
assertContains(
    dashboard,
    #"String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle)"#,
    "empty session fallback title must be localized"
)
assertContains(
    dashboard,
    #"String(localized: "Delete", bundle: LanguageManager.shared.localizedBundle)"#,
    "session-row delete affordance help must be localized"
)

assertBefore(
    dashboard,
    #"navRow(.tasksLogs, title: String(localized: "Automation""#,
    #"navRow(.market, title: String(localized: "Market""#,
    "Market row must appear directly after Automation"
)
assertNotContains(
    dashboard,
    #"navRow(.outputs"#,
    "left sidebar must not render an Outputs navigation row"
)
assertContains(
    dashboard,
    #".id("chatTop")"#,
    "timeline branch must keep chatTop anchor"
)
assertContains(
    dashboard,
    #".id("chatBottom")"#,
    "timeline branch must keep chatBottom anchor"
)
assertContains(
    dashboard,
    #"Color.clear"#,
    "scroll anchors should be invisible clear views"
)

assertContains(
    dashboard,
    #"RoundedRectangle(cornerRadius: 10, style: .continuous)"#,
    "chat bubbles must use tightened desktop-style 10pt corners"
)
assertContains(
    dashboard,
    #"return Color.white.opacity(message.role == .user ? 0.12 : 0.095)"#,
    "dark-mode chat bubbles must use visible gray fills"
)
assertContains(
    dashboard,
    #"return Color.black.opacity(message.role == .user ? 0.075 : 0.055)"#,
    "light-mode chat bubbles must use visible gray fills"
)
assertContains(
    dashboard,
    #"let codeBg = isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.10)""#,
    "code blocks must remain visibly distinct inside gray chat bubbles"
)
assertContains(
    dashboard,
    #"Button(action: { performCopy(message.content) })"#,
    "copy toolbar must remain available for gray bubble content"
)

assertContains(
    dashboard,
    #".overlay(alignment: .bottomTrailing) {"#,
    "composer selector panels must be an overlay"
)
assertContains(
    dashboard,
    #"ComposerAgentModelPanel("#,
    "composer must use the custom agent/model panel"
)
assertContains(
    dashboard,
    #"composerSelectorShowsModels"#,
    "composer selector must support the adjacent model panel state"
)

assertContains(metrics, "collapsedWidth: CGFloat = 0", "closed Outputs sidebar must reserve zero width")
assertContains(layoutScript, "narrow windows close Outputs without leaving a trailing strip", "Outputs layout verification must cover narrow-window closed strip behavior")
assertContains(dashboard, "if sidebarWidth > 0", "Outputs sidebar column must render only when width is positive")
assertContains(dashboard, ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: outputsSidebarExpanded)", "Outputs sidebar expansion must animate")

assertContains(config, "struct GatewaySettingsGroup", "Gateway settings group must exist")
assertContains(config, "Text(\"Gateway\")", "Gateway heading must be shown")
assertContains(config, "GatewayConfigSection(viewModel: viewModel, showsTitle: false)", "Gateway config title must not duplicate inside the grouped container")
assertContains(config, "ModelConfigSection(viewModel: viewModel)", "custom API provider controls must remain in the Gateway group")

assertContains(dashboard, "if isHovering {", "session rows must expose hover-only actions")
assertContains(dashboard, "Button(action: onDelete)", "session-row delete action must be separate from row navigation")

print("Chat composer polish source verification passed")
