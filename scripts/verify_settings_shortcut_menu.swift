#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("ConfigTabView.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let config = try String(contentsOf: configURL, encoding: .utf8)

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

func offset(of needle: String, in haystack: String) -> String.Index {
    guard let range = haystack.range(of: needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
    return range.lowerBound
}

let sidebarMainList = slice(
    dashboard,
    from: "private var sidebarMainList: some View",
    to: "private func navRow"
)
let sidebarBottomBar = slice(
    dashboard,
    from: "private var sidebarBottomBar: some View",
    to: "// MARK: - Agents List"
)
let providerSettingsContent = slice(
    config,
    from: "case .provider:\n            settingsScroll {",
    to: "case .budget:"
)

require(
    !sidebarMainList.contains("navRow(.status"),
    "Status should move into the Settings page instead of staying as a main sidebar entry."
)
require(
    sidebarMainList.contains("navRow(.skills") &&
        sidebarMainList.contains("navRow(.plugins"),
    "Skills and Plugins should remain first-class entries in the main sidebar."
)
let searchChatsOffset = offset(of: "onOpenGlobalSessionSearch()", in: sidebarMainList)
let skillsOffset = offset(of: "navRow(.skills", in: sidebarMainList)
let pluginsOffset = offset(of: "navRow(.plugins", in: sidebarMainList)
let automationOffset = offset(of: "navRow(.tasksLogs", in: sidebarMainList)
let marketOffset = offset(of: "navRow(.market", in: sidebarMainList)
require(
    searchChatsOffset < skillsOffset &&
        skillsOffset < pluginsOffset &&
        pluginsOffset < automationOffset &&
        automationOffset < marketOffset,
    "Sidebar order should be Search chats, Skills, Plugins, Automation, AgentsMarket."
)
require(
    !sidebarMainList.contains("navRow(.budget") &&
        !sidebarMainList.contains("navRow(.billing") &&
        !sidebarMainList.contains("navRow(.config"),
    "Main sidebar should not expose Settings, Budget, or Billing as top-level management rows."
)
require(
    dashboard.contains("@State private var isSettingsShortcutMenuPresented = false") &&
        dashboard.contains("SettingsShortcutMenu(") &&
        sidebarBottomBar.contains(".popover(isPresented: $isSettingsShortcutMenuPresented"),
    "Sidebar bottom bar should expose one Settings button that opens the shortcut menu."
)
require(
    sidebarBottomBar.contains(#"Text("Settings")"#) &&
        !sidebarBottomBar.contains("sparkleUpdater.checkForUpdates") &&
        !sidebarBottomBar.contains("appAppearance = isDark ?"),
    "Sidebar bottom bar should contain only the Settings shortcut, not update or theme controls."
)
require(
    dashboard.contains("onOpenSettingsSection: openSettingsSection") &&
        dashboard.contains("private func openSettingsSection(_ section: SettingsPageSection)") &&
        dashboard.contains("selectedSettingsSection = section") &&
        dashboard.contains("selectedTab = .config"),
    "Settings shortcut menu should route specific sections into the independent Settings page."
)
require(
    dashboard.contains("authManager.logout()"),
    "Settings shortcut menu should call the existing logout flow."
)
require(
    dashboard.contains("BillingShortcutSummary") &&
        dashboard.contains("BudgetShortcutSummary") &&
        dashboard.contains("DefaultModelShortcutPicker"),
    "Shortcut menu should include Billing, Budget, and model quick-switch summaries."
)
require(
    !dashboard.contains("StatusShortcutSummary"),
    "Shortcut menu should not add a Status summary; Status belongs in the Settings page."
)
require(
    config.contains("enum SettingsPageSection") &&
        config.contains("@Binding var selectedSection: SettingsPageSection") &&
        config.contains("SettingsSectionSidebar") &&
        config.contains("case .profile") &&
        config.contains("case .status") &&
        config.contains("StatusTabView(viewModel: viewModel)") &&
        config.contains("case .budget") &&
        config.contains("case .skills") &&
        config.contains("case .plugins") &&
        config.contains("case .logs"),
    "ConfigTabView should become an independent Settings page with section navigation."
)
let officialProviderOffset = offset(of: "GetClawHubServiceSection(viewModel: viewModel)", in: providerSettingsContent)
let customProviderOffset = offset(of: "ModelConfigSection(viewModel: viewModel)", in: providerSettingsContent)
require(
    officialProviderOffset < customProviderOffset,
    "Provider settings should keep the official GetClawHub service option before the custom API provider."
)

print("Settings shortcut menu verification passed")
