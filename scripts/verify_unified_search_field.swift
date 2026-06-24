#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sharedSearchPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Shared")
    .appendingPathComponent("UnifiedSearchField.swift")
let skillsPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("SkillsTabView.swift")
let pluginsPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("PluginsTabView.swift")
let marketplaceOverviewPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("MarketplaceOverviewView.swift")
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

let sharedSearch = read(sharedSearchPath)
let skills = read(skillsPath)
let plugins = read(pluginsPath)
let marketplaceOverview = read(marketplaceOverviewPath)
let dashboard = read(dashboardPath)
let project = read(projectPath)

require(
    sharedSearch.contains("struct UnifiedSearchField: View"),
    "Shared should define a reusable UnifiedSearchField component."
)
require(
    sharedSearch.contains("@Binding private var text: String") &&
        sharedSearch.contains("TextField(placeholder, text: $text)") &&
        sharedSearch.contains(#"Image(systemName: "magnifyingglass")"#) &&
        sharedSearch.contains(#"Image(systemName: "xmark.circle.fill")"#),
    "UnifiedSearchField should own the search icon, text field, and clear button."
)
require(
    sharedSearch.contains(".frame(height: height)") &&
        sharedSearch.contains("RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)") &&
        sharedSearch.contains(".stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)"),
    "UnifiedSearchField should centralize height, rounded background, and light/dark border styling."
)
require(
    skills.contains("UnifiedSearchField(placeholder: \"Search skills\", text: $searchText)") &&
        !skills.contains(#"TextField("Search skills", text: $searchText)"#),
    "Skills tab should use UnifiedSearchField instead of hand-written search chrome."
)
require(
    plugins.contains("UnifiedSearchField(placeholder: \"Search plugins\", text: $searchText)") &&
        !plugins.contains(#"TextField("Search plugins", text: $searchText)"#),
    "Plugins tab should use UnifiedSearchField instead of hand-written search chrome."
)
require(
    marketplaceOverview.contains("UnifiedSearchField(") &&
        marketplaceOverview.contains(#"String(localized: "Search agents...", bundle: languageManager.localizedBundle)"#),
    "Marketplace overview should use UnifiedSearchField with its localized placeholder."
)
require(
    dashboard.contains("UnifiedSearchField(") &&
        dashboard.contains(#"String(localized: "Search agents...", bundle: languageManager.localizedBundle)"#) &&
        !dashboard.contains(#"TextField("Search agents...", text: $marketplaceSearchText)"#),
    "Dashboard marketplace list should use UnifiedSearchField instead of hand-written search chrome."
)
require(
    project.contains("UnifiedSearchField.swift in Sources") &&
        project.contains("UnifiedSearchField.swift"),
    "Xcode project should include UnifiedSearchField.swift in the Shared group and app target sources."
)

print("Unified search field verification passed")
