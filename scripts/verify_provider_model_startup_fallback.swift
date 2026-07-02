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
let appSettings = read("OpenClawInstaller/Models/AppSettings.swift")

let initializerBlock = slice(
    viewModel,
    from: "// Initialize edited values from real config",
    to: "// Forward nested ObservableObject changes"
)
let syncFields = slice(
    viewModel,
    from: "func syncEditedFieldsFromSettings()",
    to: "    /// Reload from disk and sync fields."
)
let loadModelsForSettings = slice(
    viewModel,
    from: "func loadModelsForSettings() async",
    to: "    /// Save a persona file"
)
require(
    initializerBlock.contains("refreshAvailableModelsForCurrentProvider()"),
    "DashboardViewModel init must hydrate composer models from saved provider models before any CLI refresh"
)
require(
    syncFields.contains("refreshAvailableModelsForCurrentProvider()"),
    "syncEditedFieldsFromSettings must hydrate availableModelsForSettings from configuredModels after reload/save"
)
require(
    loadModelsForSettings.contains("let localModels = localModelOptionsForActiveProvider()"),
    "loadModelsForSettings must compute local provider fallback before reading CLI models"
)
require(
    loadModelsForSettings.contains("mergeModelOptions(base: localModels, overlay: scopedModels)"),
    "loadModelsForSettings must merge same-provider CLI metadata into local models instead of replacing the list"
)
require(
    !loadModelsForSettings.contains("availableModelsForSettings = scopedModels.isEmpty ? localModels : scopedModels"),
    "loadModelsForSettings must not shrink saved custom/official models to a partial non-empty CLI result"
)
require(
    viewModel.contains("private func mergeModelOptions(base: [ModelOption], overlay: [ModelOption]) -> [ModelOption]"),
    "DashboardViewModel must provide a provider-scoped merge helper for local models plus CLI metadata"
)
require(
    viewModel.contains("private func localModelOptionsForActiveProvider() -> [ModelOption]"),
    "DashboardViewModel must expose one local provider-model fallback used by init, sync, and CLI refresh"
)

let localFallback = slice(
    viewModel,
    from: "private func localModelOptionsForActiveProvider()",
    to: "    private func activeModelProviderKey()"
)

require(
    localFallback.contains(#"activeModelProviderKey() == "getclawhub""#),
    "local fallback must treat official GetClawHub as a first-class provider"
)
require(
    localFallback.contains(#"presetManager.findProvider(byKey: "getclawhub")?.models"#),
    "official provider fallback must use bundled/local provider preset models when config models are missing"
)
require(
    appSettings.contains(#"if newSettings.activeServiceSource == "getclawhub""#),
    "AppSettings.loadFromFile must populate configuredModels for the active official provider"
)
require(
    appSettings.contains(#"providers["getclawhub"] as? [String: Any]"#),
    "AppSettings.loadFromFile must read GetClawHub provider models from openclaw.json when present"
)

print("Provider model startup fallback verification passed")
