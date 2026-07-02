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

let viewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let fetchService = read("OpenClawInstaller/Services/ProviderModelFetchService.swift")

let loadModelsForSettings = slice(
    viewModel,
    from: "func loadModelsForSettings() async",
    to: "    /// Save a persona file"
)
let composerSelector = slice(
    dashboard,
    from: "struct ComposerModelSelector: View",
    to: "private struct ComposerModelPanel: View"
)
let modelConfigSection = slice(
    config,
    from: "struct ModelConfigSection: View",
    to: "// MARK: - Save Buttons"
)

require(
    fetchService.contains("struct ProviderModelFetchService"),
    "provider model fetch service must isolate network fetch logic from SwiftUI views"
)
require(
    fetchService.contains("/v1/models"),
    "provider model fetch service must call the OpenAI-compatible /v1/models endpoint"
)
require(
    fetchService.contains(#""Authorization""#) && fetchService.contains("Bearer"),
    "provider model fetch service must send bearer authorization when an API key is available"
)
require(
    fetchService.contains("URLSession.shared.data"),
    "provider model fetch service must use URLSession outside of SwiftUI views"
)
require(
    viewModel.contains("@Published var isFetchingProviderModels"),
    "dashboard view model must publish provider model fetch loading state"
)
require(
    viewModel.contains("@Published var providerModelFetchMessage"),
    "dashboard view model must publish provider model fetch result/error text"
)
require(
    viewModel.contains("func fetchModelsForSelectedProvider() async"),
    "dashboard view model must expose an explicit custom provider fetch action"
)
require(
    viewModel.contains("private func activeModelProviderKey() -> String"),
    "dashboard view model must compute the active model provider key"
)
require(
    viewModel.contains("private func modelsForActiveProvider(from models: [ModelOption]) -> [ModelOption]"),
    "dashboard view model must filter model choices to the active provider"
)
require(
    loadModelsForSettings.contains("let scopedModels = modelsForActiveProvider(from: models)"),
    "composer model choices must be provider-scoped before publishing"
)
require(
    loadModelsForSettings.contains("mergeModelOptions(base: localModels, overlay: scopedModels)"),
    "composer model choices must keep saved provider models when CLI returns empty or partial active-provider models"
)
require(
    loadModelsForSettings.contains("availableModelsForSettings = flattenModelGroups("),
    "legacy flat model choices must be projected from provider groups after refresh"
)
require(
    !composerSelector.contains("loadModelsForSettings()"),
    "composer selector must not fetch all models every time the menu opens"
)
require(
    modelConfigSection.contains("Fetch Models"),
    "custom provider settings must expose a Fetch Models action"
)
require(
    modelConfigSection.contains("fetchModelsForSelectedProvider"),
    "custom provider settings Fetch Models action must call the view model"
)
require(
    modelConfigSection.contains("editedConfiguredModels.count"),
    "custom provider settings must show the configured model count"
)
require(
    modelConfigSection.contains("isFetchingProviderModels"),
    "custom provider settings must reflect model fetch loading state"
)

print("Provider model fetch and filter verification passed")
