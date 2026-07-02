import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let appSettings = read("OpenClawInstaller/Models/AppSettings.swift")
let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

let loadModelsForSettings = slice(
    viewModel,
    from: "func loadModelsForSettings() async",
    to: "    /// Save a persona file"
)
let composerPanel = slice(
    dashboard,
    from: "private struct ComposerModelPanel: View",
    to: "private extension View"
)
let composerOverlay = slice(
    dashboard,
    from: "ComposerModelPanel(",
    to: "                    .fixedSize(horizontal: true, vertical: false)"
)

require(
    appSettings.contains("struct ConfiguredProviderModelSource"),
    "AppSettings must expose all configured provider model sources instead of only active configuredModels"
)
require(
    appSettings.contains("func loadConfiguredProviderModelSources() -> [ConfiguredProviderModelSource]"),
    "AppSettingsManager must provide a config/app-state merged provider model source API"
)
require(
    appSettings.contains("customProviderSnapshotsKey"),
    "provider model source loading must include saved custom provider snapshots"
)
require(
    viewModel.contains("struct ProviderModelGroup"),
    "DashboardViewModel must define a provider model group view model"
)
require(
    viewModel.contains("@Published var availableModelGroups: [ProviderModelGroup]"),
    "DashboardViewModel must publish grouped models for the composer"
)
require(
    viewModel.contains("private func localProviderModelGroups() -> [ProviderModelGroup]"),
    "DashboardViewModel must derive grouped models from local config and provider presets"
)
require(
    viewModel.contains(#"displayName: "Custom""#),
    "custom and user-configured provider models must be grouped under Custom"
)
require(
    viewModel.contains("providerKeys.contains($0.key)") && !viewModel.contains(#"group.providerKey == "custom" && $0.key != "getclawhub""#),
    "Custom group must not absorb every non-GetClawHub CLI model; it can only merge already configured provider keys"
)
require(
    viewModel.contains(#"displayName: "GetClawHub""#),
    "official GetClawHub models must be grouped separately"
)
require(
    viewModel.contains("private func filterAllowedGetClawHubModels(_ models: [PresetModel]) -> [PresetModel]"),
    "GetClawHub group must apply membership allow-list to saved and preset models"
)
require(
    viewModel.contains("getclawhubModels = filterAllowedGetClawHubModels(getclawhubModels)") &&
        viewModel.contains("return filterAllowedGetClawHubModels(allPresetModels)"),
    "GetClawHub saved config and preset fallback must share the same allow-list filter"
)
require(
    loadModelsForSettings.contains("let localGroups = localProviderModelGroups()"),
    "loadModelsForSettings must start from local provider groups"
)
require(
    loadModelsForSettings.contains("mergeModelGroups(base: localGroups"),
    "loadModelsForSettings must merge CLI metadata into groups instead of replacing visible groups"
)
require(
    viewModel.contains("availableModelsForSettings = flattenModelGroups("),
    "legacy flat model list must be a projection of the grouped source"
)
require(
    composerOverlay.contains("modelGroups: viewModel.availableModelGroups"),
    "composer overlay must pass provider groups into the model panel"
)
require(
    composerPanel.contains("let modelGroups: [ProviderModelGroup]"),
    "ComposerModelPanel must receive grouped model data"
)
require(
    composerPanel.contains("ForEach(modelGroups)"),
    "ComposerModelPanel must render provider sections"
)
require(
    composerPanel.contains("group.displayName"),
    "ComposerModelPanel must show provider section headers"
)
require(
    !composerPanel.contains("providerSubtitle("),
    "ComposerModelPanel must not show underlying custom provider keys inside Custom group rows"
)
require(
    composerPanel.contains("allModelIds"),
    "ComposerModelPanel must preserve a current-model row when it is outside all groups"
)

print("Provider model groups verification passed")
