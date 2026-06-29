#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

func sliceAfter(_ source: String, anchor: String, from start: String, to end: String) -> String {
    guard let anchorRange = source.range(of: anchor),
          let startRange = source.range(of: start, range: anchorRange.lowerBound..<source.endIndex),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = try read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let subAgents = try read("OpenClawInstaller/Views/Agent/SubAgentsTabView.swift")

let composerInputCard = slice(
    dashboard,
    from: "private var composerInputCard: some View",
    to: "private var terminalPanel: some View"
)
let composerArea = slice(
    dashboard,
    from: "private func composerArea(maxWidth: CGFloat, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View",
    to: "private var composerFloatingPanels: some View"
)
let pendingQueueView = slice(
    dashboard,
    from: "private struct PendingComposerQueueView: View",
    to: "// MARK: - Chat Bubble"
)
let agentContextMenu = slice(
    dashboard,
    from: "private func agentRowWithContextMenu(_ agent: AgentOption) -> some View",
    to: "private func sidebarItemHighlightColor"
)
let agentSidebarRow = sliceAfter(
    dashboard,
    anchor: "// MARK: - Agents List",
    from: "private func agentSidebarRow(_ agent: AgentOption) -> some View",
    to: "private func agentRowWithContextMenu"
)
let sidebarCollapsibleRow = slice(
    dashboard,
    from: "struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View",
    to: "// MARK: - Pulsing Dot"
)
let sidebarViewBody = slice(
    dashboard,
    from: "struct SidebarView: View",
    to: "// MARK: - Sidebar Top Header"
)
let legacyAgentsList = slice(
    dashboard,
    from: "private var agentsList: some View",
    to: "// MARK: - Marketplace List"
)
let deleteAgent = slice(
    subAgents,
    from: "@discardableResult",
    to: "// MARK: - Update Model"
)

require(!composerInputCard.contains("PendingComposerQueueView("), "pending queue should not live inside composerInputCard")
require(composerArea.contains("VStack(spacing: 8)"), "composerArea should stack queue above the input card")
require(composerArea.contains("PendingComposerQueueView("), "composerArea should render pending queue above the input card")
require(composerArea.contains("composerInputCard"), "composerArea should still render the input card")

require(pendingQueueView.contains("let onSend: (PendingComposerMessage) -> Void"), "pending queue should expose a send/priority action")
require(pendingQueueView.contains("systemName: \"paperplane\""), "pending queue rows should show a direct send button")
require(dashboard.contains("private func sendPendingComposerMessage(_ message: PendingComposerMessage)"), "chat view should implement direct/priority send for queued messages")
require(dashboard.contains("if viewModel.isSendingMessage {\n            promotePendingComposerMessage(message)"), "queued send should promote while a response is running")

require(!agentContextMenu.contains("New Agent"), "agent row context menu should not contain New Agent")
require(!agentContextMenu.contains("onRequestCreateAgent()"), "agent row context menu should not open create-agent")
require(agentContextMenu.contains("Remove Agent"), "agent row context menu should still expose remove for custom agents")
require(agentSidebarRow.contains(".contextMenu"), "agent sidebar row should own the context menu on the full row")
require(agentSidebarRow.contains("Remove Agent"), "agent sidebar row context menu should expose remove for custom agents")
require(sidebarCollapsibleRow.contains(".contentShape(Rectangle())"), "agent sidebar row should define a full-row hit area")

require(deleteAgent.contains("func deleteAgent(agentId: String) async -> Bool"), "deleteAgent should return success/failure")
require(deleteAgent.contains("@discardableResult"), "deleteAgent result may be ignored by existing callers")
require(deleteAgent.contains("lastActionError"), "deleteAgent should expose a failure reason")
require(deleteAgent.contains("return deleted"), "deleteAgent should report whether the agent disappeared after reload")

require(sidebarViewBody.contains(".alert(\"Remove Agent\""), "visible SidebarView body should own the remove-agent alert")
require(sidebarViewBody.contains("let deleted = await createAgentVM.deleteAgent(agentId: agentId)"), "sidebar remove alert should check delete result")
require(sidebarViewBody.contains("expandedAgentIds.remove(agentId)"), "successful delete should collapse removed agent")
require(sidebarViewBody.contains("viewModel.removeDeletedAgentState(agentId: agentId)"), "successful delete should clear removed agent UI state")
require(sidebarViewBody.contains("viewModel.errorMessage = createAgentVM.lastActionError"), "failed delete should surface an error")
require(!legacyAgentsList.contains(".alert(\"Remove Agent\""), "legacy agentsList should not own remove-agent alert")

print("PASS: queue position, queued send, and agent delete contracts verified")
