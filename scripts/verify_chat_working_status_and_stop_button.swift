#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let viewModelURL = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let localizableURL = root.appendingPathComponent("OpenClawInstaller/Localizable.xcstrings")
let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let viewModel = try String(contentsOf: viewModelURL, encoding: .utf8)
let localizable = try String(contentsOf: localizableURL, encoding: .utf8)

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

let composerInputCard = slice(
    dashboard,
    from: "private var composerInputCard: some View",
    to: "private var terminalPanel: some View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor: View"
)
let thinkingIndicator = slice(
    dashboard,
    from: "struct ThinkingIndicator: View",
    to: "private struct WorkStatusHeader: View"
)
let workStatusHeader = slice(
    dashboard,
    from: "private struct WorkStatusHeader: View",
    to: "private struct IsolatedElapsedWorkStatusText: View"
)
let isolatedElapsedWorkStatusText = slice(
    dashboard,
    from: "private struct IsolatedElapsedWorkStatusText: View",
    to: "private struct ShimmeringWorkStatusText: View"
)

require(dashboard.contains("private var currentForegroundTaskMessageId: UUID?"), "chat view should expose the current foreground task message id")
require(dashboard.contains("private var shouldShowStopButton: Bool"), "chat view should decide when the composer becomes a stop button")
require(composerInputCard.contains("Image(systemName: shouldShowStopButton ? \"square.fill\" : \"arrow.up\")"), "composer button should switch from arrow to centered square while streaming with empty input")
require(composerInputCard.contains(".font(.system(size: shouldShowStopButton ? 9 : 13, weight: .semibold))"), "composer stop square should render at 9pt while the send arrow remains 13pt")
require(composerInputCard.contains("if shouldShowStopButton, let messageId = currentForegroundTaskMessageId"), "composer stop state should cancel the current foreground message")
require(composerInputCard.contains("viewModel.cancelChat(messageId)"), "composer stop state should call cancelChat")
require(composerInputCard.contains(".disabled(!canSend && !shouldShowStopButton)"), "composer button should stay enabled for stop state without text")

require(dashboard.contains("private struct WorkStatusHeader: View"), "chat view should define a reusable working-status header")
require(dashboard.contains("private struct ChatScrollCompensationApplier: NSViewRepresentable"), "chat scroll should have an AppKit offset compensation bridge")
require(dashboard.contains("@State private var pendingWorkStatusScrollCompensation"), "chat view should store pending dynamic scroll compensation")
require(dashboard.contains("@State private var workStatusExpansionCompensationRevision"), "chat view should version scroll compensation requests")
require(dashboard.contains("private func compensateWorkStatusExpansion(by delta: CGFloat)"), "chat view should compensate the measured work status height delta")
require(dashboard.contains("ChatScrollCompensationApplier("), "chat scroll content should install the compensation bridge")
require(dashboard.contains("clipView.setBoundsOrigin"), "scroll compensation should adjust the NSScrollView clip view by measured pixels")
require(dashboard.contains("private static func nearestScrollView"), "scroll compensation should robustly find the hosting NSScrollView")
require(dashboard.contains("private static func applyCompensation"), "scroll compensation should retry after SwiftUI content height updates")
require(dashboard.contains("remainingRetries"), "scroll compensation should not be lost when the first pass clamps to the old max offset")
require(dashboard.contains("documentView.layoutSubtreeIfNeeded()"), "scroll compensation should force layout before computing max offset")
require(dashboard.contains("private static func visualCompensationOffset"), "scroll compensation should convert measured height deltas into the scroll view's coordinate system")
require(dashboard.contains("documentView.isFlipped ? delta : -delta"), "scroll compensation should keep content visually anchored when working rows expand upward")
require(viewModel.contains("let completedAt: Date?"), "chat messages should persist a terminal work end time")
require(viewModel.contains("completedAt: resolvedCompletedAt"), "message updates should stamp the terminal work end time")
require(dashboard.contains("let end: Date?"), "working-status header should accept an optional end time")
require(dashboard.contains("let onExpansionHeightChange: ((CGFloat) -> Void)?"), "working-status header should report measured expansion height deltas")
require(dashboard.contains("private struct WorkStatusHeaderHeightKey: PreferenceKey"), "working-status header should publish its measured height")
require(dashboard.contains("@State private var measuredHeight"), "working-status header should measure its actual height")
require(dashboard.contains("@State private var hasMeasuredHeight"), "working-status header should prime height tracking before reporting deltas")
require(dashboard.contains("private static let expansionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)"), "working-status expansion should reuse the sidebar agent spring timing")
require(dashboard.contains("private static let measuredHeightDeltaThreshold: CGFloat = 2"), "working-status height reporting should ignore sub-2pt measurement jitter")
require(dashboard.contains("abs(delta) >= Self.measuredHeightDeltaThreshold"), "working-status height reporting should use the shared jitter threshold")
require(dashboard.contains("onExpansionHeightChange?(delta)"), "working-status header should report incremental measured height deltas")
require(dashboard.contains("withAnimation(Self.expansionAnimation)"), "working-status toggle should animate expansion state changes")
require(dashboard.contains(".transition(.move(edge: .top).combined(with: .opacity))"), "working-status activity rows should slide and fade like the agent sidebar")
require(dashboard.contains(".animation(Self.expansionAnimation, value: isExpanded)"), "working-status header should animate layout changes from expansion state")
require(chatBubble.contains("WorkStatusHeader(")
        && chatBubble.contains("start: message.timestamp")
        && chatBubble.contains("end: message.completedAt"),
        "assistant bubble should pass the terminal end time into the working status")
require(chatBubble.contains("onExpansionHeightChange: onWorkStatusExpansionHeightChange"), "assistant bubble should forward working status expansion deltas")
require(thinkingIndicator.contains("onExpansionHeightChange: onWorkStatusExpansionHeightChange"), "empty loading indicator should forward working status expansion deltas")
require(chatBubble.contains("if showsTopWorkStatus"), "assistant bubble should gate the top work status")
require(chatBubble.contains("private var showsTopWorkStatus: Bool"), "chat bubble should compute whether a top working status is needed")
require(chatBubble.contains("message.completedAt != nil"), "assistant completed bubbles should keep showing the top work status")
require(dashboard.contains("Worked for"), "finished English work status should read Worked for")
require(localizable.contains(#""Worked for %@"#), "finished work status should have a localized Worked for key")
require(localizable.contains(#""value" : "已运行 %@"#), "finished Chinese work status should read 已运行")
require(dashboard.contains("private struct ShimmeringWorkStatusText: View"), "active working status should have a dedicated shimmer text view")
require(dashboard.contains("private struct IsolatedElapsedWorkStatusText: View"), "active seconds display should be isolated into a fixed-size leaf view")
require(!workStatusHeader.contains("TimelineView(.periodic(from: start, by: 1))"), "working-status header should not refresh its whole layout every second")
require(isolatedElapsedWorkStatusText.contains("TimelineView(.periodic(from: start, by: 1))"), "isolated seconds text should own the one-second timeline")
require(isolatedElapsedWorkStatusText.contains("ShimmeringWorkStatusText(")
        && isolatedElapsedWorkStatusText.contains("text: WorkStatusDurationText.status("),
        "isolated active seconds should render through the shimmer text view")
require(isolatedElapsedWorkStatusText.contains(".monospacedDigit()"), "isolated seconds text should use monospaced digits")
require(isolatedElapsedWorkStatusText.contains(".frame(width: Self.reservedWidth"), "isolated seconds text should reserve a stable width")
require(dashboard.contains("LinearGradient("), "shimmer text should use a moving linear gradient highlight")
require(dashboard.contains("withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false))"), "shimmer text should animate the highlight continuously")

require(!chatBubble.contains("ProgressView()"), "chat bubble streaming/background rows should not render spinner progress views")
require(!chatBubble.contains("onCancel?(message)"), "chat bubble should not expose cancel buttons while streaming/background")
require(!thinkingIndicator.contains("ProgressView()"), "empty loading indicator should not render a spinner")
require(!thinkingIndicator.contains("viewModel.cancelChat(message.id)"), "empty loading indicator should not own cancel")

print("PASS: chat working-status header and composer stop button contracts verified")
