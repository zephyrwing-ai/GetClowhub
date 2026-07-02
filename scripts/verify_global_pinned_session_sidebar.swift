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

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        fatalError("Could not slice \(start) -> \(end)")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let chatSessionModel = read("OpenClawInstaller/Models/ChatSession.swift")

assertContains(
    chatSessionModel,
    "var isPinned: Bool",
    "pin state should stay on ChatSession metadata instead of a separate persisted queue"
)

assertContains(
    viewModel,
    "@Published var pinnedSessions: [ChatSessionMetadata] = []",
    "view model should expose a derived global pinned session list"
)
assertContains(
    viewModel,
    "private static func orderedSessionMetadata",
    "session metadata ordering should be centralized so pinned/project/general lists stay consistent"
)
assertContains(
    viewModel,
    "pinnedSessions = Self.orderedSessionMetadata(grouped.values.flatMap { $0 }.filter(\\.isPinned))",
    "global pinned sessions should be derived from all non-archived sessions and ordered by recency"
)
assertNotContains(
    viewModel,
    "pinnedAt",
    "pin ordering should not add a new pinnedAt field"
)
assertContains(
    viewModel,
    "let agentId = sessionMetadata(for: sessionId)?.agentId ?? selectedAgentId",
    "global pinned row delete/archive actions should resolve the owning agent from session metadata"
)
let togglePinSession = slice(
    viewModel,
    from: "func togglePinSession(_ sessionId: UUID)",
    to: "/// Mark a session as archived."
)
assertNotContains(
    togglePinSession,
    "session.updatedAt = Date()",
    "pin/unpin should not update updatedAt because it is a presentation state change, not conversation activity"
)

let projectGrouping = slice(
    viewModel,
    from: "private func rebuildProjectSessionGroups",
    to: "/// Remove in-memory UI state"
)
assertContains(
    projectGrouping,
    "let unpinnedSessions = Self.orderedSessionMetadata(sessions.filter { !$0.isPinned })",
    "project/general grouping should exclude pinned sessions before grouping"
)
assertContains(
    projectGrouping,
    "let general = unpinnedSessions.filter { $0.projectId == nil }",
    "general session rows should only include non-pinned sessions"
)
assertContains(
    projectGrouping,
    "Dictionary(grouping: unpinnedSessions.filter { $0.projectId != nil })",
    "project folders should only include non-pinned sessions"
)

assertContains(
    dashboard,
    "globalPinnedSessionsSection",
    "sidebar should render a global pinned section"
)
assertContains(
    dashboard,
    "if !viewModel.pinnedSessions.isEmpty",
    "global pinned section should be hidden when there are no pinned sessions"
)
assertContains(
    dashboard,
    "sessionRows(viewModel.pinnedSessions, switchGlobally: true)",
    "pinned rows should use the shared session row renderer with global switching"
)

let sessionRows = slice(
    dashboard,
    from: "private func sessionRows",
    to: "private func projectFolderRow"
)
assertContains(
    sessionRows,
    "switchGlobally: Bool = false",
    "session row renderer should distinguish local agent rows from global pinned rows"
)
assertContains(
    sessionRows,
    "viewModel.switchSessionGlobally(to: meta.id)",
    "global pinned rows should switch by session id across agents"
)
assertContains(
    sessionRows,
    "viewModel.switchSession(to: meta.id)",
    "normal rows should preserve the local same-agent switch path"
)

let chatSessionRow = slice(
    dashboard,
    from: "struct ChatSessionRow: View",
    to: "#Preview"
)
assertContains(
    chatSessionRow,
    "let onPinToggle: () -> Void",
    "session rows should expose a hover pin action"
)
assertContains(
    chatSessionRow,
    #"Image(systemName: meta.isPinned ? "pin.fill" : "pin")"#,
    "session rows should show pin state in the hover action"
)
assertNotContains(
    chatSessionRow,
    "meta.isPinned ? .accentColor : .secondary",
    "pinned session rows should not turn the pin action blue"
)
assertContains(
    chatSessionRow,
    "HStack(spacing: 2)",
    "session row hover actions should lay out pin and delete icons together"
)
assertContains(
    dashboard,
    "static let sessionRowActionAreaWidth: CGFloat = sessionRowActionSize * 2 + 2",
    "session row should reserve a fixed trailing action area for pin and delete icons"
)
assertNotContains(
    chatSessionRow,
    ".overlay(alignment: .trailing)",
    "session row actions should participate in layout instead of overlaying long titles"
)
assertContains(
    chatSessionRow,
    ".frame(width: DashboardSidebarMetrics.sessionRowActionAreaWidth",
    "session row action area should keep a fixed width even when hidden"
)

print("Global pinned session sidebar checks passed")
