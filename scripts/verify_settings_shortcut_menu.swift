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
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("ConfigTabView.swift")

let dashboard = try String(contentsOf: dashboardURL, encoding: .utf8)
let settingsPanel = try String(contentsOf: settingsPanelURL, encoding: .utf8)
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
let officialServiceSection = slice(
    config,
    from: "struct GetClawHubServiceSection: View",
    to: "#endif"
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
    dashboard.contains("SettingsShortcutPanelButton(") &&
        !dashboard.contains("SettingsShortcutPanelHost(") &&
        !dashboard.contains("SettingsShortcutMenu(") &&
        settingsPanel.contains("SettingsShortcutPanelHost(") &&
        settingsPanel.contains("SettingsShortcutMenu(") &&
        !sidebarBottomBar.contains(".popover(isPresented:"),
    "Sidebar bottom bar should expose one Settings button that opens the arrowless shortcut panel."
)
require(
    sidebarBottomBar.contains("SettingsShortcutPanelButton(") &&
        !sidebarBottomBar.contains("SettingsSectionRow(") &&
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
    settingsPanel.contains("authManager.logout()"),
    "Settings shortcut menu should call the existing logout flow."
)
require(
    settingsPanel.contains("BillingShortcutSummary") &&
        settingsPanel.contains("BudgetShortcutSummary") &&
        settingsPanel.contains("DefaultModelShortcutPicker"),
    "Shortcut menu should include Billing, Budget, and model quick-switch summaries."
)
require(
    !settingsPanel.contains("StatusShortcutSummary"),
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
        config.contains("case .models") &&
        config.contains("case .channels") &&
        config.contains("case .logs"),
    "ConfigTabView should keep account, system, configuration, models, channels, and logs Settings sections."
)
require(
    !config.contains("case .skills") &&
        !config.contains("case .plugins") &&
        !config.contains("case .cron") &&
        !config.contains("SkillsTabView(viewModel: viewModel") &&
        !config.contains("PluginsTabView(") &&
        !config.contains("CronTabView(viewModel: viewModel"),
    "Settings should not duplicate main sidebar entries for Skills, Plugins, or Automation/Cron."
)
let officialProviderOffset = offset(of: "GetClawHubServiceSection(viewModel: viewModel)", in: providerSettingsContent)
let customProviderOffset = offset(of: "ModelConfigSection(viewModel: viewModel)", in: providerSettingsContent)
require(
    officialProviderOffset < customProviderOffset,
    "Provider settings should keep the official GetClawHub service option before the custom API provider."
)
require(
    officialServiceSection.contains("Available Models") &&
        officialServiceSection.contains("officialAvailableModels") &&
        officialServiceSection.contains("activeOfficialModelAllowList") &&
        officialServiceSection.contains("availableModelsView"),
    "Official GetClawHub provider settings should show the usable model list."
)
require(
    officialServiceSection.contains("@State private var areModelsExpanded = false") &&
        officialServiceSection.contains("officialModelSummary") &&
        officialServiceSection.contains("areModelsExpanded.toggle()") &&
        officialServiceSection.contains("if areModelsExpanded") &&
        officialServiceSection.contains(".frame(maxHeight: 260)"),
    "Official GetClawHub model list should be collapsed by default and expand into a height-limited list."
)

print("Settings shortcut menu verification passed")
