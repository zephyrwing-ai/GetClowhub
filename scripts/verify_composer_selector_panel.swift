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
let chatComposer = read("OpenClawInstaller/Views/Dashboard/ChatComposerView.swift")

let emptySurface = slice(dashboard, from: "private var emptyChatSurface: some View", to: "private var timelineChatSurface: some View")
let dismissLayer = slice(dashboard, from: "private var composerSelectorDismissLayer: some View", to: "private var chatContent: some View")
let selectorButton = slice(dashboard, from: "struct ComposerModelSelector: View", to: "private struct ComposerModelPanel: View")
let selectorPanel = slice(dashboard, from: "private struct ComposerModelPanel: View", to: "private func stripProviderPrefix")

assertContains(
    emptySurface,
    "Spacer(minLength: 0)",
    "empty chat surface must center the title and composer with flexible spacers"
)
assertNotContains(
    emptySurface,
    "Spacer(minLength: 80)",
    "empty chat surface must not keep the old fixed top offset"
)
assertNotContains(
    emptySurface,
    "Spacer(minLength: 120)",
    "empty chat surface must not keep the old fixed bottom offset"
)
assertContains(
    chatComposer,
    #"String(localized: "Ask Anything", bundle: LanguageManager.shared.localizedBundle)"#,
    "composer placeholder must be Ask Anything"
)
assertContains(
    dashboard,
    "static let composerPlaceholder = Font.system(size: 14, weight: .regular)",
    "composer placeholder must use the scoped 14pt font"
)
assertContains(
    dashboard,
    "private func closeComposerSelector()",
    "composer selector must close through a shared helper"
)
assertContains(
    dismissLayer,
    "Color.clear",
    "composer selector must add a transparent outside-click layer"
)
assertContains(
    dismissLayer,
    ".contentShape(Rectangle())",
    "transparent outside-click layer must be hit-testable"
)
assertContains(
    dismissLayer,
    "closeComposerSelector()",
    "outside-click layer must close the selector"
)
assertContains(
    chatComposer,
    "ComposerModelSelector(",
    "composer must use a model-only selector"
)
assertContains(
    dashboard,
    "ComposerModelPanel(",
    "composer selector overlay must use a model-only panel"
)
assertContains(
    dashboard,
    "currentModel: viewModel.activeComposerModel",
    "composer selector overlay must use the app-level active composer model"
)
assertContains(
    dashboard,
    "onSelectModel: viewModel.selectComposerModel",
    "composer selector overlay must not write agent model settings"
)
assertNotContains(
    dashboard,
    "ComposerAgentModelSelector",
    "composer must not use the old agent/model selector"
)
assertNotContains(
    dashboard,
    "ComposerAgentModelPanel",
    "composer must not use the old agent/model panel"
)
assertNotContains(
    selectorButton,
    "AgentAvatarImage(",
    "composer selector button must not show or depend on agent selection"
)
assertContains(
    selectorButton,
    "viewModel.activeComposerModel",
    "composer selector button must render the active composer model"
)
assertNotContains(
    selectorButton,
    "currentAgent?.model",
    "composer selector button must not read the selected agent model"
)
assertNotContains(
    selectorPanel,
    "viewModel.selectedAgentId = agent.id",
    "composer model panel must not switch agents"
)
assertNotContains(
    selectorPanel,
    "ForEach(viewModel.availableAgents)",
    "composer model panel must not render an agent list"
)
assertNotContains(
    selectorPanel,
    #"Text("Agent")"#,
    "composer model panel must not expose an Agent section"
)
assertContains(
    selectorPanel,
    "let modelGroups: [ProviderModelGroup]",
    "composer model panel must receive grouped model data as an explicit input"
)
assertContains(
    selectorPanel,
    "let onSelectModel: (String) -> Void",
    "composer model panel must select models through a narrow callback"
)
assertNotContains(
    selectorPanel,
    "@ObservedObject var viewModel: DashboardViewModel",
    "composer model panel must not observe the whole dashboard view model"
)
assertContains(
    selectorPanel,
    "ForEach(modelGroups)",
    "composer model panel must render the injected provider groups directly"
)
assertContains(
    selectorPanel,
    "group.displayName",
    "composer model panel must render provider group headers"
)
assertNotContains(
    selectorPanel,
    "Default (",
    "composer model panel must not show a Default row"
)
assertNotContains(
    selectorPanel,
    #"subtitle: "Inherit""#,
    "composer model panel must not expose inherit text in the model list"
)
assertContains(
    selectorPanel,
    "effectiveSelectedModel",
    "composer model panel must select the effective model when current model inherits the default"
)
assertNotContains(
    selectorPanel,
    "resetToDefault",
    "composer model panel must not reset the composer model to an empty selection"
)
assertNotContains(
    selectorPanel,
    #"Image(systemName: "arrow.counterclockwise")"#,
    "composer model panel must not show a reset icon"
)
assertContains(
    selectorPanel,
    "private static let maxModelPanelHeight",
    "composer model panel must define a fixed maximum height for long model lists"
)
assertContains(
    selectorPanel,
    "ScrollView",
    "composer model panel must put model rows inside an internal scroll view"
)
assertContains(
    selectorPanel,
    "LazyVStack",
    "composer model panel must lazily render model rows inside the scrollable area"
)
assertContains(
    selectorPanel,
    ".frame(maxHeight: Self.maxModelPanelHeight)",
    "composer model panel must clamp height instead of growing beyond the window"
)
assertContains(
    dashboard,
    ".fixedSize(horizontal: true, vertical: false)",
    "composer selector overlay must not force the panel to its full vertical content height"
)
assertNotContains(
    dashboard,
    ".fixedSize(horizontal: true, vertical: true)",
    "composer selector overlay must allow the panel height clamp to take effect"
)
assertNotContains(
    selectorPanel,
    #"title: "\(agent.emoji) \(agent.name)""#,
    "composer agent rows must not show emoji icons"
)

print("Composer selector panel verification passed")
