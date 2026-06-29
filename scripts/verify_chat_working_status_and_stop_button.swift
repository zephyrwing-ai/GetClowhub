#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let composerURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChatComposerView.swift")
let timelineURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift")
let workStatusURL = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/WorkStatusHeader.swift")
let viewModelURL = root.appendingPathComponent("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let localizableURL = root.appendingPathComponent("OpenClawInstaller/Localizable.xcstrings")
let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let composer = try String(contentsOf: composerURL, encoding: .utf8)
let timeline = try String(contentsOf: timelineURL, encoding: .utf8)
let workStatus = try String(contentsOf: workStatusURL, encoding: .utf8)
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

let composerInputCard = composer
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "struct InlineUserMessageEditor: View"
)
let thinkingIndicator = slice(
    dashboard,
    from: "struct ThinkingIndicator: View",
    to: "struct ChatBubble: View"
)
let workStatusHeader = slice(
    workStatus,
    from: "struct WorkStatusHeader: View",
    to: "private struct IsolatedElapsedWorkStatusText: View"
)
let isolatedElapsedWorkStatusText = slice(
    workStatus,
    from: "private struct IsolatedElapsedWorkStatusText: View",
    to: "private struct ShimmeringWorkStatusText: View"
)

require(dashboard.contains("private var currentForegroundTaskMessageId: UUID?"), "chat view should expose the current foreground task message id")
require(dashboard.contains("private var shouldShowStopButton: Bool"), "chat view should decide when the composer becomes a stop button")
require(composerInputCard.contains("Image(systemName: shouldShowStopButton ? \"square.fill\" : \"arrow.up\")"), "composer button should switch from arrow to centered square while streaming with empty input")
require(composerInputCard.contains(".font(.system(size: shouldShowStopButton ? 9 : 13, weight: .semibold))"), "composer stop square should render at 9pt while the send arrow remains 13pt")
require(composerInputCard.contains("if shouldShowStopButton, let messageId = currentForegroundTaskMessageId"), "composer stop state should cancel the current foreground message")
require(composerInputCard.contains("onCancelMessage(messageId)"), "composer stop state should call the injected cancel action")
require(composerInputCard.contains(".disabled(!canSend && !shouldShowStopButton)"), "composer button should stay enabled for stop state without text")

require(workStatus.contains("struct WorkStatusHeader: View"), "working-status header should live in its own reusable component file")
require(!dashboard.contains("private struct WorkStatusHeader: View"), "DashboardView should not keep the working-status implementation inline")
require(!dashboard.contains("struct ChatScrollCompensationApplier: NSViewRepresentable"), "chat scroll should not use an AppKit offset compensation bridge for working-status expansion")
require(!dashboard.contains("@State private var pendingWorkStatusScrollCompensation"), "chat view should not store dynamic work-status scroll compensation")
require(!dashboard.contains("@State private var workStatusExpansionCompensationRevision"), "chat view should not version work-status scroll compensation requests")
require(!dashboard.contains("private func compensateWorkStatusExpansion(by delta: CGFloat)"), "chat view should not compensate measured work-status height deltas")
require(!timeline.contains("ChatScrollCompensationApplier("), "chat scroll content should not install the compensation bridge")
require(!dashboard.contains("clipView.setBoundsOrigin"), "working-status expansion should not imperatively move the NSScrollView clip view")
require(!workStatus.contains("WorkStatusHeaderHeightKey"), "working-status header should not publish measured height")
require(!workStatus.contains("onPreferenceChange"), "working-status header should not write measured height changes back into state")
require(!workStatus.contains("onExpansionHeightChange"), "working-status header should not report expansion deltas to the chat container")
require(viewModel.contains("let completedAt: Date?"), "chat messages should persist a terminal work end time")
require(viewModel.contains("completedAt: resolvedCompletedAt"), "message updates should stamp the terminal work end time")
require(workStatus.contains("let end: Date?"), "working-status header should accept an optional end time")
require(workStatus.contains("private static let expansionAnimation = Animation.spring(response: 0.28, dampingFraction: 0.86)"), "working-status expansion should reuse the sidebar agent spring timing")
require(workStatus.contains("withAnimation(Self.expansionAnimation)"), "working-status toggle should animate expansion state changes")
require(workStatus.contains(".transition(.move(edge: .top).combined(with: .opacity))"), "working-status activity rows should slide and fade like the agent sidebar")
require(workStatus.contains(".animation(Self.expansionAnimation, value: isExpanded)"), "working-status header should animate layout changes from expansion state")
require(chatBubble.contains("WorkStatusHeader(")
        && chatBubble.contains("start: message.timestamp")
        && chatBubble.contains("end: message.completedAt"),
        "assistant bubble should pass the terminal end time into the working status")
require(!chatBubble.contains("onExpansionHeightChange:"), "assistant bubble should not forward working status expansion deltas")
require(!thinkingIndicator.contains("onExpansionHeightChange:"), "empty loading indicator should not forward working status expansion deltas")
require(chatBubble.contains("if showsTopWorkStatus"), "assistant bubble should gate the top work status")
require(chatBubble.contains("private var showsTopWorkStatus: Bool"), "chat bubble should compute whether a top working status is needed")
require(chatBubble.contains("message.completedAt != nil"), "assistant completed bubbles should keep showing the top work status")
require(workStatus.contains("Worked for"), "finished English work status should read Worked for")
require(localizable.contains(#""Worked for %@"#), "finished work status should have a localized Worked for key")
require(localizable.contains(#""value" : "已运行 %@"#), "finished Chinese work status should read 已运行")
require(workStatus.contains("private struct ShimmeringWorkStatusText: View"), "active working status should have a dedicated shimmer text view")
require(workStatus.contains("private struct IsolatedElapsedWorkStatusText: View"), "active seconds display should be isolated into a fixed-size leaf view")
require(!workStatusHeader.contains("TimelineView(.periodic(from: start, by: 1))"), "working-status header should not refresh its whole layout every second")
require(isolatedElapsedWorkStatusText.contains("TimelineView(.periodic(from: start, by: 1))"), "isolated seconds text should own the one-second timeline")
require(isolatedElapsedWorkStatusText.contains("ShimmeringWorkStatusText(")
        && isolatedElapsedWorkStatusText.contains("text: WorkStatusDurationText.status("),
        "isolated active seconds should render through the shimmer text view")
require(isolatedElapsedWorkStatusText.contains(".monospacedDigit()"), "isolated seconds text should use monospaced digits")
require(isolatedElapsedWorkStatusText.contains(".frame(width: Self.reservedWidth"), "isolated seconds text should reserve a stable width")
require(workStatus.contains("LinearGradient("), "shimmer text should use a moving linear gradient highlight")
require(workStatus.contains("withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false))"), "shimmer text should animate the highlight continuously")

require(!chatBubble.contains("ProgressView()"), "chat bubble streaming/background rows should not render spinner progress views")
require(!chatBubble.contains("onCancel?(message)"), "chat bubble should not expose cancel buttons while streaming/background")
require(!thinkingIndicator.contains("ProgressView()"), "empty loading indicator should not render a spinner")
require(!thinkingIndicator.contains("viewModel.cancelChat(message.id)"), "empty loading indicator should not own cancel")

print("PASS: chat working-status header and composer stop button contracts verified")
