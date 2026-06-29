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

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let chatComposer = read("OpenClawInstaller/Views/Dashboard/ChatComposerView.swift")
let markdownHTML = read("OpenClawInstaller/Views/Dashboard/MarkdownHTML.swift")
let rightInspectorSplit = read("OpenClawInstaller/Views/Dashboard/Inspector/RightInspectorSplitView.swift")
let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let metrics = read("OpenClawInstaller/Views/Dashboard/OutputsSidebarLayoutMetrics.swift")
let layoutScript = read("scripts/verify_outputs_sidebar_layout.swift")
let rightOutputsTitlebarAccessory = slice(dashboard, from: "private struct RightOutputsTitlebarAccessory: View", to: "// MARK: - Sidebar")

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
    chatComposer,
    #"String(localized: "Ask Anything", bundle: LanguageManager.shared.localizedBundle)"#,
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
    #"navRow(.market, title: String(localized: "AgentsMarket""#,
    "AgentsMarket row must appear directly after Automation"
)
assertNotContains(
    dashboard,
    #"navRow(.outputs"#,
    "left sidebar must not render an Outputs navigation row"
)
assertContains(
    dashboard,
    #".id("chatScrollView")"#,
    "timeline branch must keep the chat scroll view identity"
)
assertContains(
    dashboard,
    #"proxy.scrollTo("chatBottom", anchor: .bottom)"#,
    "timeline branch must keep bottom-scroll targeting"
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
    #"private var bubbleBackgroundColor: SwiftUI.Color"#,
    "chat bubbles must centralize visible gray fills"
)
assertContains(
    dashboard,
    #"Color.gray.opacity(0.14)"#,
    "user chat bubbles must use visible gray fills"
)
assertContains(
    dashboard,
    #"Color(NSColor.controlBackgroundColor)"#,
    "assistant chat bubbles must use a system gray fill"
)
assertContains(
    markdownHTML,
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
    #"overlayPreferenceValue(ComposerInputCardBoundsKey.self)"#,
    "composer selector panels must be an overlay"
)
assertContains(
    dashboard,
    #"overlayPreferenceValue(ComposerSelectorButtonBoundsKey.self)"#,
    "composer selector button must anchor overlay placement"
)
assertContains(
    dashboard,
    #"ComposerModelPanel("#,
    "composer must use the custom model-only panel"
)
assertContains(
    chatComposer,
    #"ComposerModelSelector("#,
    "composer must use the model-only selector"
)
assertNotContains(
    dashboard,
    #"ComposerAgentModelPanel"#,
    "composer must not keep the old agent/model panel"
)
assertNotContains(
    dashboard,
    #"composerSelectorShowsModels"#,
    "composer selector must not keep the old adjacent agent/model panel state"
)
assertContains(
    dashboard,
    "private static let emptyChatContentYOffset: CGFloat = -48",
    "empty chat welcome/composer group must define an explicit upward offset"
)
assertContains(
    dashboard,
    ".offset(y: Self.emptyChatContentYOffset)",
    "empty chat welcome/composer group must move upward as one centered unit"
)

assertContains(metrics, "collapsedWidth: CGFloat = 0", "closed Outputs sidebar must reserve zero width")
assertNotContains(metrics, "titlebarAccessoryWidthAdjustment", "titlebar accessory width must not be coupled to the Outputs split pane width")
assertContains(layoutScript, "narrow windows close Outputs without leaving a trailing strip", "Outputs layout verification must cover narrow-window closed strip behavior")
assertContains(dashboard, "RightInspectorSplitView(", "Outputs sidebar must use the reusable AppKit right split container")
assertContains(dashboard, "@State private var isWorkspaceSidebarClosing = false", "Outputs sidebar must keep its content mounted while the close animation runs")
assertContains(dashboard, "@State private var workspaceSidebarCollapseRequestID = 0", "Outputs sidebar must request AppKit collapse before committing collapsed state")
assertContains(dashboard, "@State private var isWorkspaceSidebarOpening = false", "Outputs sidebar must keep its opening animation state before committing expanded state")
assertContains(dashboard, "@State private var workspaceSidebarExpandRequestID = 0", "Outputs sidebar must request AppKit expand before committing expanded state")
assertContains(dashboard, "@State private var pendingWorkspaceSidebarCloseReset = false", "Outputs sidebar reset must be deferred until close animation completion")
assertContains(dashboard, "collapseRequestID: workspaceSidebarCollapseRequestID", "Outputs sidebar split must receive direct collapse requests")
assertContains(dashboard, "expandRequestID: workspaceSidebarExpandRequestID", "Outputs sidebar split must receive direct expand requests")
assertContains(dashboard, "onSidebarExpandFinished: completeWorkspaceSidebarOpen", "Outputs sidebar split must notify DashboardView after opening")
assertContains(dashboard, "onSidebarCollapseFinished: completeWorkspaceSidebarClose", "Outputs sidebar split must notify DashboardView after collapsing")
assertNotContains(dashboard, "isChatTabActive && !isWorkspaceSidebarClosing && (workspaceSidebarExpanded || workspaceEditingFilePath != nil)", "Outputs sidebar should not commit visual collapsed state before the AppKit collapse animation starts")
assertContains(dashboard, "workspaceSidebarExpanded || workspaceEditingFilePath != nil || isWorkspaceSidebarOpening || isWorkspaceSidebarClosing", "Outputs sidebar content must stay mounted while opening or closing")
assertNotContains(dashboard, "private final class DashboardWorkspaceSplitController: NSViewController", "DashboardView must not inline the reusable AppKit split controller")
assertNotContains(dashboard, "private struct DashboardWorkspaceSplitView<Content: View, Sidebar: View>: NSViewControllerRepresentable", "DashboardView must not inline the reusable AppKit split shell")
assertContains(rightInspectorSplit, "private final class RightInspectorSplitController: NSViewController", "Outputs sidebar shell must be owned by the reusable AppKit controller")
assertContains(rightInspectorSplit, "enum RightInspectorSplitMetrics", "right split metrics must be shared with the titlebar accessory")
assertContains(rightInspectorSplit, "static let animationDuration: TimeInterval = 0.30", "right split and titlebar accessory must share one smoother animation duration")
assertContains(rightInspectorSplit, "sidebarWidthConstraint?.animator().constant", "Outputs sidebar must animate one AppKit width constraint")
assertContains(rightInspectorSplit, "private var isAnimatingSidebar = false", "Outputs sidebar animation should be tracked inside the AppKit split controller")
assertContains(rightInspectorSplit, "guard hasInstalledLayout, hasAppliedInitialLayout, !isAnimatingSidebar else { return }", "layout passes during Outputs animation must not snap the middle pane to the final width")
assertContains(rightInspectorSplit, "private var sidebarAnimationGeneration = 0", "Outputs sidebar animation should invalidate stale completions")
assertContains(rightInspectorSplit, "private var onSidebarCollapseFinished: (() -> Void)?", "Outputs sidebar collapse completion must be owned by the AppKit split controller")
assertContains(rightInspectorSplit, "private var onSidebarExpandFinished: (() -> Void)?", "Outputs sidebar expand completion must be owned by the AppKit split controller")
assertContains(rightInspectorSplit, "private var lastExpandRequestID = 0", "Outputs sidebar controller must track direct expand request ids")
assertContains(rightInspectorSplit, "private var lastCollapseRequestID = 0", "Outputs sidebar controller must track direct collapse request ids")
assertContains(rightInspectorSplit, "let shouldCollapseFromRequest = collapseRequestID != lastCollapseRequestID", "Outputs sidebar must start closing from a direct AppKit request")
assertContains(rightInspectorSplit, "let shouldExpandFromRequest = expandRequestID != lastExpandRequestID", "Outputs sidebar must start opening from a direct AppKit request")
assertContains(rightInspectorSplit, "let isCollapsingSidebar = (shouldAnimate && currentIsSidebarExpanded && !isSidebarExpanded && hasAppliedInitialLayout) || (shouldCollapseFromRequest && hasAppliedInitialLayout)", "Outputs sidebar must identify closing before replacing the SwiftUI root")
assertContains(rightInspectorSplit, "let shouldDeferSidebarRootUpdate = isCollapsingSidebar || (isAnimatingSidebar && !currentIsSidebarExpanded)", "Outputs sidebar content must stay mounted during follow-up updates while closing")
assertContains(rightInspectorSplit, "if !shouldDeferSidebarRootUpdate {\n            sidebarHost.rootView = sidebar\n        }", "Outputs sidebar content must stay mounted while closing")
assertContains(rightInspectorSplit, "self.sidebarHost.rootView = sidebar\n                self.onSidebarCollapseFinished?()", "Outputs sidebar root and SwiftUI state must update only after close animation")
assertContains(rightInspectorSplit, "if isAnimatingSidebar && !currentIsSidebarExpanded && isSidebarExpanded {\n            return\n        }", "Outputs sidebar must not reverse a requested close while SwiftUI still reports expanded business state")
assertContains(rightInspectorSplit, "if isAnimatingSidebar && currentIsSidebarExpanded && !isSidebarExpanded {\n            return\n        }", "Outputs sidebar must not reverse a requested open while SwiftUI still reports collapsed business state")
assertContains(rightInspectorSplit, "self.sidebarHost.rootView = sidebar\n                    self.onSidebarExpandFinished?()", "Outputs sidebar expanded state must update only after open animation")
assertContains(rightInspectorSplit, "guard self.sidebarAnimationGeneration == animationID else { return }", "stale Outputs sidebar animation completions must not hide the current sidebar")
assertContains(rightInspectorSplit, "animateSidebarWidth(to: targetWidth)", "Outputs sidebar width changes should animate through the AppKit width constraint")
assertContains(rightInspectorSplit, "private let sidebarRail = NSView()", "Outputs sidebar must use an AppKit inspector rail")
assertContains(rightInspectorSplit, "private let sidebarSeparator = NSBox()", "Outputs sidebar rail must own a native separator")
assertContains(rightInspectorSplit, "private let sidebarClipView = NSView()", "Outputs sidebar rail must own a dedicated clipping view")
assertContains(rightInspectorSplit, "sidebarRail.clipsToBounds = true", "Outputs sidebar rail must clip while its width animates")
assertContains(rightInspectorSplit, "sidebarClipView.clipsToBounds = true", "Outputs sidebar clip view must prevent content flashing outside the rail")
assertContains(rightInspectorSplit, "sidebarRail.addSubview(sidebarSeparator)", "Outputs separator must be installed inside the rail")
assertContains(rightInspectorSplit, "sidebarRail.addSubview(sidebarClipView)", "Outputs clip view must be installed inside the rail")
assertContains(rightInspectorSplit, "sidebarClipView.addSubview(sidebarHost.view)", "Outputs SwiftUI host must live inside the clip view")
assertContains(rightInspectorSplit, "sidebarRail.widthAnchor.constraint(equalToConstant: 0)", "Outputs sidebar width animation must target the whole inspector rail")
assertContains(rightInspectorSplit, "contentHost.view.trailingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)", "Outputs inspector rail and middle pane must share one moving Auto Layout boundary")
assertContains(rightInspectorSplit, "sidebarRail.trailingAnchor.constraint(equalTo: view.trailingAnchor)", "Outputs inspector rail must stay pinned to the window edge")
assertContains(rightInspectorSplit, "sidebarSeparator.leadingAnchor.constraint(equalTo: sidebarRail.leadingAnchor)", "Outputs separator must sit on the moving boundary")
assertContains(rightInspectorSplit, "sidebarClipView.leadingAnchor.constraint(equalTo: sidebarSeparator.trailingAnchor)", "Outputs content must start after the separator")
assertContains(rightInspectorSplit, "sidebarHost.view.leadingAnchor.constraint(equalTo: sidebarClipView.leadingAnchor)", "Outputs SwiftUI host must be anchored inside the clip view")
assertContains(rightInspectorSplit, "sidebarContentWidthConstraint?.constant", "Outputs SwiftUI host width must be pre-sized separately from the animated rail")
assertContains(rightInspectorSplit, "separatorWidthConstraint.priority = .fittingSizeCompression", "Outputs separator width must yield while the rail collapses to zero width")
assertNotContains(rightInspectorSplit, "sidebarRail.isHidden", "Outputs inspector rail must stay mounted at zero width so the width animation remains smooth")
assertNotContains(rightInspectorSplit, "sidebarHost.view.isHidden", "Outputs sidebar must not toggle the SwiftUI host visibility during titlebar button animation")
assertNotContains(rightInspectorSplit, "sidebarContainer", "Outputs sidebar must use the fuller rail/clip/separator structure instead of the simpler B container")
assertNotContains(rightInspectorSplit, "NSSplitViewItem", "Outputs sidebar must not rely on resident split item state")
assertNotContains(rightInspectorSplit, "splitView.animator().setPosition", "Outputs sidebar must not animate a split divider")
assertNotContains(rightInspectorSplit, "canCollapse", "Outputs sidebar must not rely on split-item collapse behavior")
assertNotContains(rightInspectorSplit, "prepareSidebarForExpansion", "Outputs sidebar must not relayout in a separate pre-expansion phase")
assertNotContains(rightInspectorSplit, ".isCollapsed", "Outputs sidebar must use zero divider width instead of collapsed state")
assertNotContains(dashboard, ".inspector(isPresented:", "Outputs sidebar must not use SwiftUI inspector in AppKit split mode")
assertNotContains(dashboard, "private var workspaceInspectorContent: some View", "Outputs sidebar must not keep a SwiftUI inspector wrapper")
assertNotContains(dashboard, "private var workspaceSplitColumn: some View", "Outputs sidebar must not use a manual trailing split column")
assertContains(dashboard, "private func workspaceSidebarPane(width: CGFloat) -> some View", "Outputs header and content must live in one AppKit split pane")
assertContains(dashboard, "WorkspaceOutputsPaneHeader(", "Outputs split pane must own the title/search/open header")
assertContains(dashboard, "ToolbarItem(placement: .navigation)", "conversation title must live in the window toolbar")
assertNotContains(dashboard, "ToolbarItem(placement: .primaryAction)", "Outputs toggle must not use the main toolbar primaryAction placement")
assertContains(dashboard, "DashboardTitlebarAccessoryInstaller(", "Outputs controls must be installed into the existing titlebar header")
assertContains(dashboard, "RightOutputsTitlebarAccessory(", "Outputs toggle must stay in the titlebar accessory")
assertContains(dashboard, "isTerminalOpen: terminalOpen", "Terminal state must be passed into the right titlebar accessory")
assertContains(dashboard, "toggleTerminal:", "Terminal toggle must be wired into the right titlebar accessory")
assertNotContains(dashboard, #"Image(systemName: "tray.full.fill")"#, "right sidebar header must not show the removed blue tray icon")
assertNotContains(dashboard, ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceSidebarExpanded)", "Outputs sidebar expansion must not be double-animated by the SwiftUI root")
assertNotContains(dashboard, ".animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceEditingFilePath)", "Outputs sidebar editor-width changes must not be double-animated by the SwiftUI root")
assertNotContains(dashboard, "private var chatTopChrome", "ChatView must not own the conversation header")
assertNotContains(dashboard, "private var conversationHeader: some View", "conversation header must not consume vertical space inside the chat content")
assertNotContains(dashboard, "WorkspaceInspectorHeader(", "right sidebar content must not create a second header row")
assertContains(dashboard, "private struct RightOutputsTitlebarAccessory: View", "right sidebar toggle must live in the existing titlebar header")
assertNotContains(rightOutputsTitlebarAccessory, #"Text("Outputs")"#, "right titlebar accessory must not resize as a second Outputs header")
assertContains(rightOutputsTitlebarAccessory, #"Image(systemName: "terminal")"#, "right titlebar accessory must restore the Terminal button")
assertBefore(rightOutputsTitlebarAccessory, #"Image(systemName: "terminal")"#, #"Image(systemName: "sidebar.right")"#, "Terminal button must sit to the left of the right sidebar button")
assertContains(rightOutputsTitlebarAccessory, #"Image(systemName: "sidebar.right")"#, "right sidebar collapse must use the standard inspector sidebar icon")
assertContains(rightOutputsTitlebarAccessory, ".font(.system(size: 18, weight: .medium))", "right sidebar titlebar icon must visually match the system left-sidebar toolbar icon size")
assertContains(rightOutputsTitlebarAccessory, ".frame(width: 34, height: 34)", "right sidebar titlebar icon must use the same apparent button footprint as the left toolbar icon")
assertNotContains(rightOutputsTitlebarAccessory, #"Image(systemName: "xmark")"#, "right sidebar collapse must not use a generic close icon")
assertContains(dashboard, "private func shouldShowOutputItem", "right sidebar must filter the workspace to output artifacts")
assertContains(dashboard, "\"USER.md\", \"BOOTSTRAP.md\", \"HEARTBEAT.md\", \"TOOLS.md\"", "Outputs filtering must exclude user/context documents")

assertContains(config, "struct GatewaySettingsGroup", "Gateway settings group must exist")
assertContains(config, "Text(\"Gateway\")", "Gateway heading must be shown")
assertContains(config, "GatewayConfigSection(viewModel: viewModel, showsTitle: false)", "Gateway config title must not duplicate inside the grouped container")
assertContains(config, "ModelConfigSection(viewModel: viewModel)", "custom API provider controls must remain in the Gateway group")

assertContains(dashboard, "if isHovering {", "session rows must expose hover-only actions")
assertContains(dashboard, "Button(action: isDeleteConfirming ? onDeleteConfirm : onDeleteIntent)", "session-row delete action must be separate from row navigation")

print("Chat composer polish source verification passed")
