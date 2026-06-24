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
let sharedOverlay = read("OpenClawInstaller/Views/Shared/DashboardModalOverlay.swift")
let dashboardBody = slice(dashboard, from: "var body: some View", to: "private var activeTab")
let beginRename = slice(dashboard, from: "private func beginSessionRename", to: "private func saveSessionRename")
let saveRename = slice(dashboard, from: "private func saveSessionRename", to: "private func dismissSessionRename")
let renameOverlay = slice(dashboard, from: "private var sessionRenameOverlay", to: "private func presentSkillDetail")
let sidebarInit = slice(dashboard, from: "struct SidebarView: View", to: "private var isDark")
let sessionsSection = slice(dashboard, from: "private func sessionsSectionContent(for agent: AgentOption) -> some View", to: "// MARK: - Agent Section Content")

assertNotContains(
    dashboard,
    #".alert("Rename Session""#,
    "session rename should use the dashboard overlay instead of the system alert"
)
assertContains(
    dashboard,
    "private struct SessionRenamePresentation: Identifiable",
    "rename overlay state should be represented by an identifiable session presentation"
)
assertContains(
    dashboard,
    "@State private var sessionRenamePresentation: SessionRenamePresentation?",
    "dashboard root should own the active rename presentation"
)
assertContains(
    dashboardBody,
    "if sessionRenamePresentation != nil",
    "dashboard root should render the rename overlay"
)
assertContains(
    beginRename,
    "viewModel.switchSessionGlobally(to: meta.id)",
    "opening rename should first make the target session the active session"
)
assertContains(
    beginRename,
    "viewModel.selectedTab = .chat",
    "opening rename should put the dashboard back on the chat tab"
)
assertContains(
    renameOverlay,
    "dismissSessionRename()",
    "clicking the dimmed area should dismiss without saving"
)
assertContains(
    renameOverlay,
    "DashboardModalOverlay(",
    "rename overlay should reuse the shared dashboard modal overlay shell"
)
assertContains(
    sharedOverlay,
    "let scrimOpacity: Double",
    "shared dashboard modal overlay should support configurable scrim opacity"
)
assertContains(
    sharedOverlay,
    "let verticalOffset: CGFloat",
    "shared dashboard modal overlay should support configurable vertical placement"
)
assertContains(
    sharedOverlay,
    "scrimOpacity: Double = 0.001",
    "shared dashboard modal overlay should keep the existing transparent default"
)
assertContains(
    sharedOverlay,
    "verticalOffset: CGFloat = 0",
    "shared dashboard modal overlay should keep the existing centered default"
)
assertContains(
    sharedOverlay,
    ".opacity(scrimOpacity)",
    "shared dashboard modal overlay should apply configurable scrim opacity"
)
assertContains(
    sharedOverlay,
    ".offset(y: verticalOffset)",
    "shared dashboard modal overlay should apply configurable vertical offset"
)
assertContains(
    renameOverlay,
    "scrimOpacity: isDark ? 0.28 : 0.16",
    "rename overlay should dim the dashboard background"
)
assertContains(
    renameOverlay,
    "verticalOffset: -44",
    "rename overlay should sit slightly above center"
)
assertContains(
    renameOverlay,
    "languageManager.localizedBundle",
    "rename overlay copy should use the existing LanguageManager localized bundle"
)
for hardcodedCopy in [
    #"Text("Rename chat")"#,
    #"Text("Keep it short and recognizable")"#,
    #"TextField("Chat name""#,
    #".help("Close")"#,
    #"Button("Cancel""#,
    #"Button("Save""#
] {
    assertNotContains(
        renameOverlay,
        hardcodedCopy,
        "rename overlay should not hard-code user-facing copy: \(hardcodedCopy)"
    )
}
assertNotContains(
    renameOverlay,
    "Color.black.opacity(isDark ? 0.28 : 0.16)",
    "rename overlay should not maintain its own background click layer"
)
assertContains(
    renameOverlay,
    "Color(red: 0.965, green: 0.973, blue: 0.955)",
    "rename overlay should use the snow surface color"
)
assertContains(
    renameOverlay,
    "let snowText = Color(red: 0.10, green: 0.12, blue: 0.10)",
    "rename overlay should use fixed dark text on the snow surface"
)
assertContains(
    renameOverlay,
    "let snowSecondaryText = Color(red: 0.42, green: 0.44, blue: 0.40)",
    "rename overlay should use fixed secondary text on the snow surface"
)
assertNotContains(
    renameOverlay,
    ".background(.regularMaterial",
    "rename overlay panel should not use the generic material background"
)
assertContains(
    saveRename,
    "viewModel.renameSession(presentation.id, to: sessionRenameDraft)",
    "saving the dialog should reuse the existing session rename persistence"
)
assertContains(
    sidebarInit,
    "let onRequestRenameSession: (ChatSessionMetadata) -> Void",
    "sidebar should keep rename routing as a parent-owned action"
)
assertContains(
    sessionsSection,
    ".onTapGesture(count: 2)",
    "session rows should expose double-click rename"
)
assertContains(
    sessionsSection,
    "onRequestRenameSession(meta)",
    "both double-click and context menu rename should use the shared rename request"
)

print("Session double-click rename overlay checks passed")
