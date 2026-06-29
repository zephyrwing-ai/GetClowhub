#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let settingsPanelURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("SettingsShortcutPanel.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let settingsPanel = try String(contentsOf: settingsPanelURL, encoding: .utf8)

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

let bottomBar = slice(
    dashboard,
    from: "private var sidebarBottomBar: some View",
    to: "// MARK: - Agents List"
)

require(
    bottomBar.contains("SettingsShortcutPanelButton(") &&
        !bottomBar.contains("SettingsShortcutPanelHost(") &&
        !bottomBar.contains("SettingsShortcutMenu("),
    "Dashboard sidebar bottom bar should only compose the extracted Settings shortcut button."
)

require(
    !dashboard.contains("private struct SettingsShortcutPanelHost") &&
        !dashboard.contains("private final class SettingsShortcutPanelCoordinator") &&
        !dashboard.contains("private struct SettingsShortcutMenu: View") &&
        !dashboard.contains("private struct SettingsShortcutExpandableRow"),
    "Settings shortcut panel internals should be extracted out of DashboardView.swift."
)

require(
    !settingsPanel.contains(".popover(isPresented:"),
    "Settings shortcut should not use SwiftUI popover because it renders the unwanted arrow."
)

let panelHost = slice(
    settingsPanel,
    from: "private struct SettingsShortcutPanelHost",
    to: "private struct SettingsShortcutMenu: View"
)

require(
    panelHost.contains("NSViewRepresentable") &&
        panelHost.contains("SettingsShortcutPanelCoordinator") &&
        panelHost.contains("NSPanel(") &&
        panelHost.contains("styleMask: [.borderless, .nonactivatingPanel]") &&
        panelHost.contains("panel.backgroundColor = .clear") &&
        panelHost.contains("panel.appearance = NSAppearance(named: .aqua)") &&
        panelHost.contains("DispatchQueue.main.async"),
    "Settings shortcut panel should use a small AppKit bridge with deferred presentation and a stable light appearance."
)

require(
    panelHost.contains("panelFrame(relativeTo sourceView: NSView)") &&
        panelHost.contains("window.convertToScreen") &&
        panelHost.contains("x: sidebarMaxX") &&
        panelHost.contains("windowFrameOnScreen") &&
        panelHost.contains("availableHeight"),
    "Settings shortcut panel should position its left edge on the sidebar divider and constrain height inside the app window."
)

let menu = slice(
    settingsPanel,
    from: "private struct SettingsShortcutMenu: View",
    to: "private struct SettingsShortcutActionRow"
)

require(
    menu.contains("SettingsShortcutLiquidDropBackground(cornerRadius: SettingsShortcutPanelMetrics.cornerRadius)") &&
        menu.contains("ScrollView(.vertical") &&
        menu.contains(".scrollIndicators(.automatic)") &&
        menu.contains(".clipShape(SettingsShortcutPanelMetrics.panelShape)") &&
        menu.contains(".frame(width: SettingsShortcutPanelMetrics.width"),
    "Settings shortcut panel content should draw its own rounded frame and scroll internally when space is constrained."
)

require(
    settingsPanel.contains("enum SettingsShortcutPanelMetrics") &&
        settingsPanel.contains("static let cornerRadius: CGFloat = 22") &&
        settingsPanel.contains("static let maxHeight: CGFloat = 560"),
    "Settings shortcut panel metrics should centralize the larger rounded glass frame."
)

require(
    settingsPanel.contains("RadialGradient") &&
        settingsPanel.contains(".blendMode(.plusLighter)") &&
        settingsPanel.contains(".strokeBorder") &&
        settingsPanel.contains("SettingsShortcutLiquidDropBackground") &&
        settingsPanel.contains(".fill(.ultraThinMaterial)") &&
        settingsPanel.contains("SettingsShortcutColors.glassBase") &&
        settingsPanel.contains("SettingsShortcutColors.glassHighlight") &&
        settingsPanel.contains("SettingsShortcutColors.glassShadow"),
    "Settings shortcut background should use a balanced liquid-glass base, visible border, and soft neutral shadow."
)

require(
    !settingsPanel.contains("Color.black.opacity") &&
        !settingsPanel.contains("controlBackgroundColor") &&
        !settingsPanel.contains("Color.white.opacity(0.82)"),
    "Settings shortcut glass should avoid dark overlays, system control backgrounds, and heavy white overlays that destroy contrast."
)

require(
    settingsPanel.contains("enum SettingsShortcutColors") &&
        settingsPanel.contains("static let primaryText = SwiftUI.Color(red:") &&
        settingsPanel.contains("static let secondaryText = SwiftUI.Color(red:") &&
        settingsPanel.contains("static let tertiaryText = SwiftUI.Color(red:") &&
        menu.contains(".foregroundStyle(SettingsShortcutColors.primaryText)") &&
        settingsPanel.contains("case .normal: return SettingsShortcutColors.primaryText") &&
        settingsPanel.contains("SettingsShortcutColors.secondaryText"),
    "Settings shortcut content should set explicit readable foreground colors instead of relying on material vibrancy."
)

require(
    !settingsPanel.contains("@State private var scroll") &&
        !settingsPanel.contains("scrollPosition") &&
        !settingsPanel.contains("onScroll"),
    "Settings shortcut scrolling should remain local to the scroll view and not bind scroll offset into SwiftUI state."
)

require(
    settingsPanel.contains("SettingsShortcutExpandableRow") &&
        settingsPanel.contains("SettingsShortcutRowContent") &&
        settingsPanel.contains(".contentShape(Rectangle())") &&
        !menu.contains("DisclosureGroup(isExpanded: $isBillingExpanded)") &&
        !menu.contains("DisclosureGroup(isExpanded: $isBudgetExpanded)"),
    "Billing and Budget should use full-width custom rows instead of native DisclosureGroup hit targets."
)

let expandableRow = slice(
    settingsPanel,
    from: "private struct SettingsShortcutExpandableRow<Content: View>: View",
    to: "private struct SettingsShortcutLiquidDropBackground: View"
)

require(
    expandableRow.contains(".clipped()"),
    "Expandable Billing and Budget content should clip during collapse to avoid ghosting."
)

print("Settings shortcut panel verification passed")
