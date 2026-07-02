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

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let zhAgentsI18nPath = "OpenClawInstaller/Resources/I18n/zh-Hans/agents.json"
let zhAgentsI18nText = read(zhAgentsI18nPath)
let zhAgentsI18nData = Data(zhAgentsI18nText.utf8)

let agentsPath = "OpenClawInstaller/Resources/marketplace_agents.json"
let agentsText = read(agentsPath)
let agentsData = Data(agentsText.utf8)

guard let zhAgentsI18n = try JSONSerialization.jsonObject(with: zhAgentsI18nData) as? [String: String] else {
    fputs("FAIL: \(zhAgentsI18nPath) must be a JSON object of strings\n", stderr)
    exit(1)
}

guard let agents = try JSONSerialization.jsonObject(with: agentsData) as? [[String: Any]] else {
    fputs("FAIL: \(agentsPath) must be a JSON array\n", stderr)
    exit(1)
}

require(!zhAgentsI18n.isEmpty, "unified zh-Hans agents i18n resource should not be empty")
for key in [
    "agents.search.placeholder",
    "agents.empty.noMatching",
    "agents.detail.vibe",
    "agents.detail.personaContent",
    "agents.action.recruit",
    "agents.action.recruiting",
    "agents.action.recruited",
    "agents.alert.recruitFailed"
] {
    require(zhAgentsI18n[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, "missing AgentsMarket UI i18n key: \(key)")
}

func slug(_ value: String) -> String {
    let lower = value.lowercased()
    var result = ""
    var previousWasSeparator = true
    for scalar in lower.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            result.unicodeScalars.append(scalar)
            previousWasSeparator = false
        } else if !previousWasSeparator {
            result.append(".")
            previousWasSeparator = true
        }
    }
    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return trimmed.isEmpty ? "item" : trimmed
}

let requiredFields = ["name", "division", "description", "vibe", "specialty", "whenToUse", "content"]

for agent in agents {
    guard let agentID = agent["id"] as? String else {
        fputs("FAIL: every marketplace agent must have an id\n", stderr)
        exit(1)
    }
    let prefix = "agents.\(slug(agentID))"
    for field in requiredFields {
        guard let sourceValue = agent[field] as? String, !sourceValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continue
        }
        let key = "\(prefix).\(field)"
        guard let localizedValue = zhAgentsI18n[key], !localizedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fputs("FAIL: unified agents i18n is missing \(key)\n", stderr)
            exit(1)
        }
        if field != "content" {
            require(localizedValue != sourceValue, "\(key) still matches the English source text")
        }
    }
}

let model = read("OpenClawInstaller/Models/MarketplaceAgent.swift")
require(model.contains("localizedDisplay(localeID:"), "MarketplaceAgent should expose localizedDisplay(localeID:) for views")
require(model.contains("I18n.agentDisplay"), "MarketplaceCatalog should localize display through unified I18n")
require(!model.contains("marketplace_agents.i18n"), "MarketplaceCatalog should not load marketplace_agents.i18n.json directly")
require(model.contains("localeID: String"), "Marketplace content conversion should accept an explicit locale")

let overview = read("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let detail = read("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
require(overview.contains("I18n.t(\"agents.search.placeholder\")"), "MarketplaceOverviewView should localize search placeholder through I18n")
require(overview.contains("I18n.t(\"agents.empty.noMatching\")"), "MarketplaceOverviewView should localize empty state through I18n")
require(detail.contains("I18n.t(\"agents.action.recruit\")"), "MarketplaceDetailView should localize recruit action through I18n")
require(detail.contains("display.content"), "MarketplaceDetailView should show localized persona display content")

for (path, source) in [
    ("MarketplaceOverviewView.swift", overview),
    ("MarketplaceDetailView.swift", detail)
] {
    require(!source.contains("Text(agent.name)"), "\(path) should render localized display name")
    require(!source.contains("Text(agent.division)"), "\(path) should render localized display division")
    require(!source.contains("Text(agent.description)"), "\(path) should render localized display description")
    require(!source.contains("Text(agent.vibe)"), "\(path) should render localized display vibe")
}

require(dashboard.contains("localizedDisplay(localeID:"), "Dashboard marketplace rows should render localized marketplace display text")

let designManager = read("OpenClawInstaller/Services/DesignSystemManager.swift")
require(designManager.contains("prepareWorkspace"), "DesignSystemManager should prepare a workspace with selected design-system docs")
require(designManager.contains("DESIGN_SYSTEMS_INDEX.md"), "DesignSystemManager should write a lightweight design-system index")
require(designManager.contains("DESIGN_SYSTEMS_SELECTION.md"), "DesignSystemManager should write selection diagnostics")

let collab = read("OpenClawInstaller/ViewModels/CollabViewModel.swift")
let marketplaceDetail = detail

for (path, source) in [
    ("CollabViewModel.swift", collab),
    ("MarketplaceDetailView.swift", marketplaceDetail)
] {
    require(source.contains("prepareWorkspace"), "\(path) should use DesignSystemManager.prepareWorkspace for awesome-design-system")
    require(!source.contains("copyItem(atPath: designSystemsSourcePath, toPath: designSystemsDestPath)"), "\(path) must not copy the entire DesignSystems directory")
}

let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
require(project.contains("I18n in Resources"), "Xcode project should bundle unified I18n resources")

print("Marketplace i18n and DesignSystems workspace verification passed")
