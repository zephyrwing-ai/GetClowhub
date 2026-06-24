#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let overlayPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Shared")
    .appendingPathComponent("CursorDotOverlay.swift")
let dashboardPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let projectPath = root
    .appendingPathComponent("OpenClawInstaller.xcodeproj")
    .appendingPathComponent("project.pbxproj")

func read(_ url: URL) -> String {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(url.path)\n", stderr)
        exit(1)
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let overlay = read(overlayPath)
let dashboard = read(dashboardPath)
let project = read(projectPath)
let dashboardRoot = slice(
    dashboard,
    from: "struct DashboardView: View",
    to: "private struct TitlebarSeparatorSuppressor"
)
let sidebarView = slice(
    dashboard,
    from: "struct SidebarView: View",
    to: "private struct AgentListRow"
)
let chatScrollContent = slice(
    dashboard,
    from: "private func chatScrollContent(proxy: ScrollViewProxy) -> some View",
    to: "/// Filtered slash commands based on current input"
)
let chatBubble = slice(
    dashboard,
    from: "struct ChatBubble: View",
    to: "private struct InlineUserMessageEditor: View"
)

require(
    overlay.contains("struct CursorDotOverlay: View") &&
        overlay.contains("struct CursorDotOverlayModifier: ViewModifier"),
    "Cursor dot should expose a reusable SwiftUI overlay and modifier."
)
require(
    overlay.contains("struct CursorDotConfiguration") &&
        overlay.contains("dotSize: CGFloat = 5") &&
        overlay.contains("ringSize: CGFloat = 20") &&
        overlay.contains("smoothing: CGFloat = 0.18"),
    "Cursor dot configuration should keep the fixed 5px dot, 20px ring, and trailing motion."
)
require(
    overlay.contains("NSViewRepresentable") &&
        overlay.contains("NSTrackingArea") &&
        overlay.contains("mouseMoved(with event: NSEvent)") &&
        overlay.contains("NSCursor.hide()") &&
        overlay.contains("NSCursor.unhide()"),
    "Cursor dot should use a narrow AppKit bridge for pointer tracking and native cursor visibility."
)
require(
    overlay.contains("func cursorDotDisabledRegion") &&
        overlay.contains("CursorDotDisabledPreferenceKey") &&
        overlay.contains("disabledFrames"),
    "Expensive message/WebView regions should be able to opt out of the cursor-dot overlay."
)
require(
    !overlay.contains("ringHoverSize") &&
        !overlay.contains("ringHoverColor") &&
        !overlay.contains("ringHoverFill") &&
        !overlay.contains("isHoveringTarget") &&
        !overlay.contains("CursorDotHoverPreferenceKey") &&
        !overlay.contains("cursorDotHoverTarget"),
    "Cursor dot should stay at the fixed default size and must not define hover expansion state."
)
require(
    !overlay.contains("contentView.hitTest") &&
        !overlay.contains("accessibilityRole()") &&
        !overlay.contains("isInteractiveTarget(at:") &&
        !overlay.contains("usesNativeCursor(at:"),
    "Cursor tracking should not run automatic AppKit hit-test or accessibility scans on every mouse move."
)
require(
    !overlay.contains("TimelineView(.animation)") &&
        !overlay.contains("@Published var ringLocation") &&
        overlay.contains("CAShapeLayer") &&
        overlay.contains("animationTimer") &&
        overlay.contains("startRingAnimationIfNeeded()") &&
        overlay.contains("stopRingAnimation()"),
    "Cursor dot visuals should be layer-driven and should not ask SwiftUI to recompute every animation frame."
)
require(
    overlay.contains("private func distance(from") &&
        overlay.contains("ringSnapDistance") &&
        overlay.contains("targetPointerLocation"),
    "Cursor ring animation should stop once the trailing ring catches the pointer."
)
require(
    !dashboardRoot.contains(".cursorDotOverlay(isEnabled: true)"),
    "Dashboard root should not install the cursor-dot overlay globally."
)
require(
    sidebarView.contains(".cursorDotOverlay(isEnabled: true)"),
    "SidebarView should be the only dashboard surface that installs the cursor-dot overlay."
)
require(
    !dashboard.contains(".cursorDotHoverTarget()"),
    "Dashboard controls should not request cursor-dot hover expansion."
)
require(
    !chatScrollContent.contains(".cursorDotDisabledRegion()"),
    "The central chat message scroll region should not need cursor-dot opt-out when the overlay is sidebar-scoped."
)
require(
    !chatBubble.contains(".cursorDotDisabledRegion()"),
    "Individual ChatBubble rows should not each emit cursor disabled frames; disable the central message region once."
)
require(
    project.contains("CursorDotOverlay.swift in Sources") &&
        project.contains("CursorDotOverlay.swift"),
    "Xcode project should include CursorDotOverlay.swift in the Shared group and app target sources."
)

print("Cursor dot overlay verification passed")
