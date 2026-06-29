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
let popover = read("OpenClawInstaller/Views/Dashboard/SessionTitleUserMessagesPopover.swift")
let timeline = read("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

let titleToolbar = slice(
    dashboard,
    from: #".toolbar {"#,
    to: #".alert("Error""#
)
let chatView = slice(
    dashboard,
    from: "struct ChatView: View",
    to: "struct ComposerModelSelector: View"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "// MARK: - Typewriter Text for Streaming"
)

assertContains(
    titleToolbar,
    "SessionTitleUserMessagesPopover(",
    "conversation title must use the locally owned hover popover component"
)
assertContains(
    titleToolbar,
    "messages: currentSessionUserMessages",
    "conversation title hover control must know whether user messages are available"
)
assertContains(
    titleToolbar,
    "onTapMessage: jumpToUserMessage",
    "conversation title popover should only call back to Dashboard when a user message is selected"
)
assertNotContains(
    titleToolbar,
    ".allowsHitTesting(false)",
    "conversation title must be interactive for hover popover behavior"
)

assertContains(
    dashboard,
    "private var currentSessionUserMessages: [ChatMessage]",
    "DashboardView must expose filtered user messages for the active session title popover"
)
assertContains(
    dashboard,
    ".filter { $0.role == .user",
    "title popover message source must filter to user messages only"
)

assertContains(
    project,
    "SessionTitleUserMessagesPopover.swift in Sources",
    "local title popover component must be compiled into the app target"
)

assertContains(
    popover,
    "struct SessionTitleUserMessagesPopover: View",
    "title user-message popover should live in its own focused component"
)
assertContains(
    popover,
    "@State private var isTitleHovering = false",
    "title hover state should be local to the title popover component"
)
assertNotContains(
    popover,
    "@State private var isPopoverHovering",
    "panel hover state should stay inside the AppKit coordinator"
)
assertNotContains(
    popover,
    "@State private var isPopoverPresented",
    "title panel presentation state should stay inside the AppKit coordinator, not SwiftUI state"
)
assertNotContains(
    popover,
    "@State private var popoverCloseTask: DispatchWorkItem?",
    "panel close scheduling should stay inside the AppKit coordinator"
)
assertContains(
    popover,
    "RoundedRectangle(cornerRadius: 8, style: .continuous)",
    "conversation title must render inside a lightweight rounded rectangle"
)
assertContains(
    popover,
    "private struct SessionTitlePanelHost<Label: View>: NSViewRepresentable",
    "toolbar title should use a narrow AppKit bridge to anchor a local panel"
)
assertContains(
    popover,
    "private var panel: NSPanel?",
    "title user-message panel should be owned locally by the AppKit coordinator"
)
assertContains(
    popover,
    "private let panelContentSize = NSSize(width: 360, height: 320)",
    "title user-message panel should keep a stable content size"
)
assertContains(
    popover,
    "private let panelChromeInset: CGFloat = 14",
    "title user-message panel should reserve transparent chrome for visible rounded corners and shadow"
)
assertContains(
    popover,
    "private var panelWindowSize: NSSize",
    "title user-message panel window should be larger than content so corners are not clipped"
)
assertContains(
    popover,
    "let panel = NSPanel(",
    "title user-message surface should use a borderless NSPanel so no system arrow is drawn"
)
assertContains(
    popover,
    "styleMask: [.borderless, .nonactivatingPanel]",
    "title user-message panel should be borderless and non-activating"
)
assertContains(
    popover,
    "panel.backgroundColor = .clear",
    "title user-message panel should let the SwiftUI glass surface define the visible background"
)
assertContains(
    popover,
    "panel.isOpaque = false",
    "title user-message panel should stay transparent around the rounded rectangle"
)
assertContains(
    popover,
    "controller.view.wantsLayer = true",
    "title user-message panel hosting view should be layer-backed for transparent rounded content"
)
assertContains(
    popover,
    "controller.view.layer?.backgroundColor = NSColor.clear.cgColor",
    "title user-message panel hosting view should not paint an opaque rectangular background"
)
assertContains(
    popover,
    "panel.hasShadow = false",
    "title user-message panel should avoid a second AppKit shadow around the SwiftUI glass surface"
)
assertContains(
    popover,
    "panel.orderFrontRegardless()",
    "title user-message panel should be shown without activating the main window"
)
assertContains(
    popover,
    "panel.setFrame(",
    "title user-message panel should be positioned from the title view's screen frame"
)
assertContains(
    popover,
    "panelFrame(relativeTo: sourceView)",
    "title user-message panel positioning should be computed from the title view"
)
assertNotContains(
    popover,
    ".popover(",
    "title hover UI should not use SwiftUI popover state attached to DashboardView"
)
assertNotContains(
    popover,
    "NSPopover",
    "title hover UI should not use NSPopover because it draws a system arrow"
)
assertContains(
    popover,
    "setTitleHovering(isTitleHovering, relativeTo: nsView)",
    "title panel hover changes should be forwarded to the local AppKit coordinator"
)
assertContains(
    popover,
    "private var pendingPresentWork: DispatchWorkItem?",
    "title panel should cancel stale async show attempts when SwiftUI rebuilds the source view"
)
assertContains(
    popover,
    "DispatchQueue.main.async(execute: work)",
    "title popover should defer AppKit show until the next main run loop"
)
assertContains(
    popover,
    "!self.messages.isEmpty",
    "title panel should re-check messages before showing"
)
assertContains(
    popover,
    "guard sourceView.window != nil, !sourceView.bounds.isEmpty else",
    "title panel should only show from a source view attached to a window with stable bounds"
)
assertNotContains(
    popover,
    "isPresented.wrappedValue = false",
    "title panel source-view failures should not write SwiftUI presentation state"
)
assertContains(
    popover,
    "sourceView.convert(sourceView.bounds, to: nil)",
    "title panel placement should start from the title view bounds"
)
assertContains(
    popover,
    "window.convertToScreen(titleFrameInWindow)",
    "title panel placement should convert the title frame into screen coordinates"
)
assertContains(
    popover,
    "private let titlePanelVerticalOffset: CGFloat = 8",
    "title panel should use a small fixed offset below the session title instead of polling layout"
)
assertContains(
    popover,
    "let visibleTopY = titleFrameOnScreen.minY - titlePanelVerticalOffset",
    "title panel visible surface should start slightly below the session title"
)
assertContains(
    popover,
    "let y = visibleTopY - panelContentSize.height - panelChromeInset",
    "title panel window should account for transparent chrome while positioning visible content"
)
assertNotContains(
    popover,
    "window.contentLayoutRect",
    "title panel should not use contentLayoutRect because it aligns to the wrong visual line here"
)
assertNotContains(
    popover,
    "titleFrameOnScreen.minY - panelSize.height",
    "title panel should no longer attach vertically to the session title"
)
assertContains(
    popover,
    "if !isTitleHovering && !isPanelHovering",
    "local close scheduling should keep the panel open while the pointer is over title or panel"
)
assertContains(
    popover,
    "private var isMouseInsidePanel: Bool",
    "title panel should have an AppKit-level mouse-position fallback for hover stability"
)
assertContains(
    popover,
    "panel.frame.contains(NSEvent.mouseLocation)",
    "title panel close scheduling should not close while the cursor is still inside the panel frame"
)
assertContains(
    popover,
    "private struct SessionTitlePanelHoverTracker: NSViewRepresentable",
    "panel content should use an AppKit tracking-area bridge for stable hover while scrolling"
)
assertContains(
    popover,
    "NSTrackingArea(",
    "panel hover should be backed by a native AppKit tracking area"
)
assertContains(
    popover,
    ".mouseEnteredAndExited",
    "panel hover tracking should only listen for pointer enter and exit events"
)
assertContains(
    popover,
    ".activeAlways",
    "panel hover tracking should remain active for the floating non-activating panel"
)
assertContains(
    popover,
    ".inVisibleRect",
    "panel hover tracking should follow the host view bounds without manual frame polling"
)
assertContains(
    popover,
    "ScrollView",
    "title popover content must be scrollable for long sessions"
)
assertContains(
    popover,
    "LazyVStack",
    "title popover content must render user messages as a list"
)
assertContains(
    popover,
    "ForEach(messages) { message in",
    "title popover must preserve message identity for future jump behavior"
)
assertContains(
    popover,
    "onTapMessage(message)",
    "title popover rows must expose a future message-selection hook"
)
assertContains(
    popover,
    ".frame(width: 360)",
    "title popover must use a stable readable width"
)
assertContains(
    popover,
    ".frame(maxHeight: 320)",
    "title popover must cap height so long sessions scroll"
)
assertContains(
    popover,
    ".padding(14)",
    "title popover content should leave transparent room for rounded corners and shadow"
)
assertContains(
    popover,
    "private struct SessionTitlePanelBackground: View",
    "title popover should use a named SwiftUI-native system-material background"
)

let titlePopoverContent = slice(
    popover,
    from: "private struct SessionTitleUserMessagesPopoverContent: View",
    to: "private struct SessionTitlePanelHoverTracker: NSViewRepresentable"
)
let panelBackground = slice(
    popover,
    from: "private struct SessionTitlePanelBackground: View",
    to: "private struct SessionTitleUserMessageRow: View"
)

assertContains(
    titlePopoverContent,
    ".background(SessionTitlePanelBackground(cornerRadius: 12))",
    "title popover content should apply the restored system-material background as its outer surface"
)
assertContains(
    titlePopoverContent,
    ".background(SessionTitlePanelHoverTracker(onPanelHoverChange: onPanelHoverChange))",
    "title popover content should keep hover tracking local to the panel surface"
)
assertNotContains(
    titlePopoverContent,
    ".onHover",
    "panel hover should not depend on SwiftUI onHover inside the scrollable content"
)
assertContains(
    panelBackground,
    ".fill(.regularMaterial)",
    "title panel background should restore the original lighter system material"
)
assertNotContains(
    panelBackground,
    "LinearGradient(",
    "title panel background should not add dark custom gradient overlays"
)
assertNotContains(
    panelBackground,
    "RadialGradient(",
    "title panel background should not add custom lens overlays that shift the original color"
)
assertContains(
    panelBackground,
    ".strokeBorder(",
    "title panel background should keep a subtle edge"
)
assertContains(
    panelBackground,
    ".shadow(color:",
    "title panel background should keep light depth without adding a heavy opaque fill"
)
assertContains(
    popover,
    "private func schedulePanelClose()",
    "title user-message panel must close via a short local grace delay"
)
assertContains(
    popover,
    "panelCloseTask?.cancel()",
    "title user-message panel must cancel pending closes when pointer enters title or panel"
)

assertNotContains(
    dashboard,
    "SessionTitleFrameReporter",
    "DashboardView should not measure the toolbar title frame for a root overlay"
)
assertNotContains(
    dashboard,
    "sessionTitleUserMessagesFlyout",
    "DashboardView should not render the title user-message panel as a root overlay"
)
assertNotContains(
    dashboard,
    "updateSessionTitleHover",
    "DashboardView should not own title hover state"
)
assertNotContains(
    dashboard,
    "sessionTitleFlyoutCloseTask",
    "DashboardView should not own title popover close scheduling"
)
assertNotContains(
    dashboard,
    "isSessionTitleHovering",
    "DashboardView should not change root state for title hover"
)
assertNotContains(
    dashboard,
    "sessionTitleFrame",
    "DashboardView should not store title geometry for hover popover placement"
)

assertContains(
    chatView,
    "@State private var highlightedMessageId: UUID?",
    "ChatView must track the message selected from the title popover"
)
assertContains(
    chatView,
    "@State private var highlightedMessageFlashOn = false",
    "ChatView must keep a flashing phase for selected-message emphasis"
)
assertContains(
    chatView,
    "private func jumpToUserMessage(_ messageId: UUID)",
    "ChatView must expose a jump handler for title popover selections"
)
assertContains(
    chatView,
    "chatScrollProxy?.scrollTo(messageId, anchor: .center)",
    "jump handler must scroll the chat timeline to the selected user message"
)
assertContains(
    chatView,
    "triggerUserMessageHighlight(messageId)",
    "jump handler must start selected user message highlighting after scroll"
)
assertContains(
    chatView,
    ".onChange(of: requestedUserMessageJumpId)",
    "ChatView must respond to title popover jump requests from DashboardView"
)
assertContains(
    chatView,
    "for step in 0..<6",
    "selected user message should flash a few times after jumping"
)
assertContains(
    chatView,
    "highlightedMessageId: highlightedMessageId",
    "ChatView must pass the selected-message id into the timeline surface"
)
assertContains(
    chatView,
    "highlightedMessageFlashOn: highlightedMessageFlashOn",
    "ChatView must pass the flashing phase into the timeline surface"
)
assertContains(
    timeline,
    "isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn",
    "ChatTimelineSurface must pass transient selected-message highlighting into ChatBubble"
)

assertContains(
    chatBubble,
    "let isJumpHighlighted: Bool",
    "ChatBubble must accept an explicit jump-highlight flag"
)
assertContains(
    chatBubble,
    "Color.gray.opacity(0.42)",
    "jump highlight must use a deeper gray background"
)
assertContains(
    chatBubble,
    "isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor",
    "user bubble background must switch to the deep gray flash color while highlighted"
)

print("Session title user messages popover source verification passed")
