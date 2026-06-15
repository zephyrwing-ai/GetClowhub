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
let avatarSVG = read("OpenClawInstaller/Assets.xcassets/AgentAvatar.imageset/agent-avatar-concentric-circles.svg")

let emptySurface = slice(dashboard, from: "private var emptyChatSurface: some View", to: "private var chatTopChrome: some View")
let dismissLayer = slice(dashboard, from: "private var composerSelectorDismissLayer: some View", to: "private var chatContent: some View")
let agentAvatarImage = slice(dashboard, from: "private struct AgentAvatarImage: View", to: "// MARK: - Pulsing Dot")
let selectorButton = slice(dashboard, from: "private struct ComposerAgentModelSelector: View", to: "private struct ComposerAgentModelPanel: View")
let selectorPanel = slice(dashboard, from: "private struct ComposerAgentModelPanel: View", to: "private func stripProviderPrefix")

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
    dashboard,
    #"String(localized: "Do Anything", bundle: LanguageManager.shared.localizedBundle)"#,
    "composer placeholder must be Do Anything"
)
assertContains(
    dashboard,
    ".font(.system(size: 16, weight: .regular))",
    "composer placeholder must use the requested 16pt font"
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
    selectorButton,
    "AgentAvatarImage(size: 16)",
    "composer selector button must show the shared SVG agent avatar"
)
assertContains(
    selectorPanel,
    "showsAgentAvatar: true",
    "composer agent rows must show the shared SVG agent avatar"
)
assertNotContains(
    selectorPanel,
    #"title: "\(agent.emoji) \(agent.name)""#,
    "composer agent rows must not show emoji icons"
)
assertNotContains(
    agentAvatarImage,
    ".clipShape(",
    "agent avatar image must not add an outer clipping frame"
)
assertNotContains(
    agentAvatarImage,
    ".strokeBorder(",
    "agent avatar image must not add an outer border"
)
assertNotContains(
    avatarSVG,
    "<rect",
    "agent avatar SVG must not include the white outer rectangle"
)

print("Composer selector panel verification passed")
