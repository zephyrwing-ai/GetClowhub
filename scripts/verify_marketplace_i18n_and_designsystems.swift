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

let i18nPath = "OpenClawInstaller/Resources/marketplace_agents.i18n.json"
let i18nText = read(i18nPath)
let i18nData = Data(i18nText.utf8)

guard let overlay = try JSONSerialization.jsonObject(with: i18nData) as? [String: Any] else {
    fputs("FAIL: \(i18nPath) must be a JSON object\n", stderr)
    exit(1)
}

let allowedFields = Set(["name", "division", "description", "vibe", "specialty", "whenToUse"])
require(!overlay.isEmpty, "marketplace i18n overlay should contain at least one agent translation")

for (agentID, localeValue) in overlay {
    guard let locales = localeValue as? [String: Any], !locales.isEmpty else {
        fputs("FAIL: \(agentID) should map to locale objects\n", stderr)
        exit(1)
    }

    for (localeID, fieldValue) in locales {
        guard let fields = fieldValue as? [String: Any], !fields.isEmpty else {
            fputs("FAIL: \(agentID).\(localeID) should map to localized display fields\n", stderr)
            exit(1)
        }

        for key in fields.keys {
            require(allowedFields.contains(key), "\(agentID).\(localeID) contains unsupported field \(key); runtime content must not be localized")
        }
    }
}

let model = read("OpenClawInstaller/Models/MarketplaceAgent.swift")
require(model.contains("localizedDisplay(localeID:"), "MarketplaceAgent should expose localizedDisplay(localeID:) for views")
require(model.contains("marketplace_agents.i18n"), "MarketplaceCatalog should load marketplace_agents.i18n.json")
require(!model.contains("localizedContent"), "Marketplace i18n must not introduce localized runtime content")

let overview = read("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let detail = read("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

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
require(project.contains("marketplace_agents.i18n.json in Resources"), "Xcode project should bundle marketplace_agents.i18n.json")

print("Marketplace i18n and DesignSystems workspace verification passed")
