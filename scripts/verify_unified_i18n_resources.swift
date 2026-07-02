#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: could not read \(path)\n", stderr)
        exit(1)
    }
    return text
}

func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        fputs("FAIL: missing slice start: \(start)\n", stderr)
        exit(1)
    }
    let tail = source[startRange.lowerBound...]
    guard let endRange = tail.range(of: end) else {
        fputs("FAIL: missing slice end: \(end)\n", stderr)
        exit(1)
    }
    return String(tail[..<endRange.lowerBound])
}

func jsonObject(_ path: String) -> [String: String] {
    let data = Data(read(path).utf8)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fputs("FAIL: invalid JSON string object in \(path)\n", stderr)
        exit(1)
    }
    return json
}

func placeholderSignature(_ value: String) -> [String] {
    let pattern = #"%(?:\d+\$)?(?:[-+#0 ]*)?(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?[@diuoxXfFeEgGaAcCsSp%]"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.matches(in: value, range: range).compactMap { match in
        guard let tokenRange = Range(match.range, in: value) else { return nil }
        let token = String(value[tokenRange])
        if token == "%%" {
            return nil
        }
        return token.replacingOccurrences(
            of: #"^%(\d+\$)"#,
            with: "%",
            options: .regularExpression
        )
    }
}

func supportedLanguageIDs(from source: String) -> [String] {
    let pattern = #"Language\(id:\s*\"([^\"]+)\""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
        guard let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }
}

let languageManager = read("OpenClawInstaller/Services/LanguageManager.swift")
let languages = supportedLanguageIDs(from: languageManager).filter { $0 != "system" }
require(!languages.isEmpty, "LanguageManager should expose supported languages")

require(exists("OpenClawInstaller/Services/I18nService.swift"), "I18nService.swift should exist")
let service = read("OpenClawInstaller/Services/I18nService.swift")
for token in ["enum I18n", "func t(", "func markdown(", "localeCandidates", "LanguageManager.shared.currentLocale.identifier", "String(format:"] {
    require(service.contains(token), "I18nService should contain \(token)")
}

let namespaces = ["common", "settings", "agents", "skills", "plugins"]
var englishResources: [String: [String: String]] = [:]
for namespace in namespaces {
    let path = "OpenClawInstaller/Resources/I18n/en/\(namespace).json"
    require(exists(path), "missing English i18n resource: \(path)")
    englishResources[namespace] = jsonObject(path)
}

for language in languages {
    for namespace in namespaces {
        let path = "OpenClawInstaller/Resources/I18n/\(language)/\(namespace).json"
        require(exists(path), "missing i18n resource: \(path)")
        let json = jsonObject(path)
        require(!json.isEmpty, "i18n resource should not be empty: \(path)")

        let english = englishResources[namespace] ?? [:]
        let missing = Set(english.keys).subtracting(json.keys)
        let extra = Set(json.keys).subtracting(english.keys)
        require(missing.isEmpty, "\(path) is missing keys: \(missing.sorted().prefix(8).joined(separator: ", "))")
        require(extra.isEmpty, "\(path) has keys not present in English fallback: \(extra.sorted().prefix(8).joined(separator: ", "))")

        for key in english.keys {
            let basePlaceholders = placeholderSignature(english[key] ?? "")
            let localizedPlaceholders = placeholderSignature(json[key] ?? "")
            require(
                basePlaceholders == localizedPlaceholders,
                "\(path) placeholder mismatch for \(key): expected \(basePlaceholders), got \(localizedPlaceholders)"
            )
        }
    }
}

let pbx = read("OpenClawInstaller.xcodeproj/project.pbxproj")
require(pbx.contains("I18nService.swift in Sources"), "Xcode project should compile I18nService.swift")
require(pbx.contains("I18n in Resources"), "Xcode project should bundle I18n resources")

let marketplace = read("OpenClawInstaller/Models/MarketplaceAgent.swift")
require(marketplace.contains("I18n.agentDisplay"), "MarketplaceAgent should localize display through unified I18n")
require(!marketplace.contains("marketplace_agents.i18n"), "MarketplaceAgent should not load the old marketplace_agents.i18n overlay directly")

let skillsView = read("OpenClawInstaller/Views/Dashboard/Skills/SkillsTabView.swift")
for token in ["@EnvironmentObject private var languageManager: LanguageManager", "I18n.skillDisplay", "I18n.t(\"skills.", "localizedSearchFields"] {
    require(skillsView.contains(token), "SkillsTabView should contain \(token)")
}
for forbidden in ["Text(\"Skills\")", "UnifiedSearchField(placeholder: \"Search skills\"", "Text(\"Install Skill\")", "Text(\"Description\")"] {
    require(!skillsView.contains(forbidden), "SkillsTabView still has hardcoded UI text: \(forbidden)")
}
let catalogSkillRow = slice(skillsView, from: "private struct CatalogSkillListRow: View", to: "private struct InstalledSkillListRow: View")
let installedSkillRow = slice(skillsView, from: "private struct InstalledSkillListRow: View", to: "private struct InstalledStatusMark: View")
require(catalogSkillRow.contains("let display = I18n.skillDisplay(for: item)"), "CatalogSkillListRow should resolve localized skill display once")
require(installedSkillRow.contains("let display = catalogItem.map { I18n.skillDisplay(for: $0) }"), "InstalledSkillListRow should resolve localized catalog display when available")
for forbidden in ["Text(item.displayName)", "Text(item.description)", "Text(catalogItem?.displayName ?? skill.name)", "Text(catalogItem?.description.nilIfBlank ?? skill.description.nilIfBlank ?? I18n.t(\"skills.fallback.installedSkill\"))"] {
    require(!(catalogSkillRow + installedSkillRow).contains(forbidden), "SkillsTabView catalog rows should use I18n.skillDisplay instead of raw catalog text: \(forbidden)")
}

let pluginsView = read("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
for token in ["@EnvironmentObject private var languageManager: LanguageManager", "I18n.pluginDisplay", "I18n.t(\"plugins.", "localizedSearchFields"] {
    require(pluginsView.contains(token), "PluginsTabView should contain \(token)")
}
for forbidden in ["Text(\"Plugins\")", "UnifiedSearchField(placeholder: \"Search plugins\"", "Text(\"Description\")", ".alert(\"Uninstall Plugin\""] {
    require(!pluginsView.contains(forbidden), "PluginsTabView still has hardcoded UI text: \(forbidden)")
}

let marketplaceOverview = read("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let marketplaceDetail = read("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
for token in ["I18n.t(\"agents.search.placeholder\")", "I18n.t(\"agents.empty.noMatching\")", "I18n.t(\"agents.action.recruit\")"] {
    require((marketplaceOverview + marketplaceDetail).contains(token), "AgentsMarket views should contain \(token)")
}
for forbidden in ["String(localized: \"Search agents", "String(localized: \"No matching agents", "String(localized: \"Recruit\"", "String(localized: \"Persona Content\""] {
    require(!(marketplaceOverview + marketplaceDetail).contains(forbidden), "AgentsMarket still has hardcoded localized UI through old entry: \(forbidden)")
}

let settingsShortcutPanel = read("OpenClawInstaller/Views/Dashboard/SettingsShortcutPanel.swift")
for forbidden in ["Text(\"Settings\")", "Text(\"Local user\")", "Label(\"Model\"", "Button(\"Configure\")", "Text(\"No models loaded\")", "Text(\"No billing data yet\")", "Text(\"No local budget rule\")", "Button(\"Edit budget rules\")"] {
    require(!settingsShortcutPanel.contains(forbidden), "SettingsShortcutPanel still has hardcoded UI text: \(forbidden)")
}

let dashboardView = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
for token in ["I18n.skillDisplay", "localizedSkillDescription", "localizedSkillHelp", "loadSkillMarket()"] {
    require(dashboardView.contains(token), "DashboardView skill surfaces should contain \(token)")
}
require(dashboardView.split(separator: "\n").filter { $0.contains("Task { await viewModel.loadSkills() }") || $0.contains("await viewModel.loadSkills()") }.isEmpty, "DashboardView skill display surfaces should load the catalog through loadSkillMarket() before rendering localized skill descriptions")
for forbidden in ["Text(skill.description)", ".help(skill.description.isEmpty ? skill.name : skill.description)"] {
    require(!dashboardView.contains(forbidden), "DashboardView skill surfaces should not show raw skill descriptions when a catalog localization exists: \(forbidden)")
}

print("Unified i18n resources verification passed")
