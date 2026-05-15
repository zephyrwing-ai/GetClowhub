import Combine
import Foundation
import AppKit

/// Represents the editable fields from ~/.openclaw/openclaw.json
struct AppSettings: Equatable {
    var gatewayPort: Int = 18789
    var gatewayAuthToken: String = ""
    var modelBaseUrl: String = ""
    var modelApiKey: String = ""
    var selectedProviderKey: String = "aliyun-codingplan"
    var providerApi: String = "openai-completions"
    var configuredModels: [PresetModel] = []
    var activeServiceSource: String = "custom" // "getclawhub" or "custom"

    static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.gatewayPort == rhs.gatewayPort
            && lhs.gatewayAuthToken == rhs.gatewayAuthToken
            && lhs.modelBaseUrl == rhs.modelBaseUrl
            && lhs.modelApiKey == rhs.modelApiKey
            && lhs.selectedProviderKey == rhs.selectedProviderKey
            && lhs.providerApi == rhs.providerApi
            && lhs.configuredModels == rhs.configuredModels
            && lhs.activeServiceSource == rhs.activeServiceSource
    }
}

@MainActor
class AppSettingsManager: ObservableObject {
    @Published var settings: AppSettings

    private let configPath: String

    init() {
        self.configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        self.settings = AppSettings()
        loadFromFile()
    }

    // MARK: - Read from openclaw.json

    /// Load settings from ~/.openclaw/openclaw.json
    func loadFromFile() {
        guard let dict = readConfigDict() else { return }

        var newSettings = AppSettings()

        // gateway.port
        if let gateway = dict["gateway"] as? [String: Any],
           let port = gateway["port"] as? Int {
            newSettings.gatewayPort = port
        }

        // gateway.auth.token
        if let gateway = dict["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any],
           let token = auth["token"] as? String {
            newSettings.gatewayAuthToken = token
        }

        // Provider key, baseUrl, apiKey, api, models
        if let models = dict["models"] as? [String: Any],
           let providers = models["providers"] as? [String: Any] {
            // Determine active service source — getclawhub takes priority
            let hasGetclawhub = providers["getclawhub"] != nil
            let hasCustom = providers.keys.contains(where: { $0 != "getclawhub" })
            if hasGetclawhub {
                newSettings.activeServiceSource = "getclawhub"
            } else if hasCustom {
                newSettings.activeServiceSource = "custom"
            }

            // Load the user's custom provider (non-getclawhub)
            if let firstKey = providers.keys.first(where: { $0 != "getclawhub" }),
               let firstProvider = providers[firstKey] as? [String: Any] {
                newSettings.selectedProviderKey = firstKey
                if let baseUrl = firstProvider["baseUrl"] as? String {
                    newSettings.modelBaseUrl = baseUrl
                }
                if let apiKey = firstProvider["apiKey"] as? String {
                    newSettings.modelApiKey = apiKey
                }
                if let api = firstProvider["api"] as? String {
                    newSettings.providerApi = api
                }
                if let modelArray = firstProvider["models"] as? [[String: Any]] {
                    newSettings.configuredModels = modelArray.compactMap { Self.parseModelDict($0) }
                }
            }
        }

        // Only publish if changed, to avoid unnecessary SwiftUI re-renders
        if newSettings != settings {
            settings = newSettings
        }
    }

    // MARK: - Write to openclaw.json

    /// Save edited fields back to ~/.openclaw/openclaw.json
    /// Creates the full models.providers node if it doesn't exist.
    func saveToFile() -> Bool {
        var dict = readConfigDict() ?? [:]

        // Update gateway section
        var gateway = dict["gateway"] as? [String: Any] ?? [:]
        gateway["port"] = settings.gatewayPort
        gateway["mode"] = gateway["mode"] as? String ?? "local"

        var auth = gateway["auth"] as? [String: Any] ?? [:]
        // Avoid landing `mode = "none"`: in that mode the gateway returns
        // sharedAuthOk=false and rejects unpaired operator clients with NOT_PAIRED.
        // "token" is the lowest-friction value that still keeps unpaired clients usable.
        auth["mode"] = (auth["mode"] as? String) ?? "token"
        auth["token"] = settings.gatewayAuthToken
        gateway["auth"] = auth

        dict["gateway"] = gateway

        // Build the provider entry
        let providerKey = settings.selectedProviderKey.isEmpty ? "custom" : settings.selectedProviderKey

        let modelsArray: [[String: Any]] = settings.configuredModels.map { model in
            var m: [String: Any] = [
                "id": model.id,
                "name": model.name,
                "reasoning": model.reasoning,
                "input": model.input,
                "contextWindow": model.contextWindow,
                "maxTokens": model.maxTokens
            ]
            m["cost"] = [
                "input": model.cost.input,
                "output": model.cost.output,
                "cacheRead": model.cost.cacheRead,
                "cacheWrite": model.cost.cacheWrite
            ]
            return m
        }

        let providerEntry: [String: Any] = [
            "baseUrl": settings.modelBaseUrl,
            "apiKey": settings.modelApiKey,
            "api": settings.providerApi,
            "models": modelsArray
        ]

        // Build models node — only keep the active provider
        var modelsNode = dict["models"] as? [String: Any] ?? [:]
        modelsNode["mode"] = "merge"

        if settings.activeServiceSource == "getclawhub" {
            // GetClawHub selected: read getclawhub provider from existing config (written by MembershipManager),
            // remove all other providers
            let existingProviders = modelsNode["providers"] as? [String: Any] ?? [:]
            if let hubProvider = existingProviders["getclawhub"] {
                modelsNode["providers"] = ["getclawhub": hubProvider]
            } else {
                modelsNode["providers"] = [String: Any]()
            }
        } else {
            // Custom selected: write only the user's custom provider, remove getclawhub
            modelsNode["providers"] = [providerKey: providerEntry]
        }
        dict["models"] = modelsNode

        // Build agents.defaults
        var agents = dict["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]

        // Collect the active provider key and its model IDs for reuse below
        let activeProviderKey: String
        let activeModelIds: [String]

        if settings.activeServiceSource == "getclawhub" {
            activeProviderKey = "getclawhub"
            let existingProviders = (dict["models"] as? [String: Any])?["providers"] as? [String: Any] ?? [:]
            if let hubProvider = existingProviders["getclawhub"] as? [String: Any],
               let hubModels = hubProvider["models"] as? [[String: Any]] {
                activeModelIds = hubModels.compactMap { $0["id"] as? String }
            } else {
                activeModelIds = []
            }
        } else {
            activeProviderKey = providerKey
            activeModelIds = settings.configuredModels.map { $0.id }
        }

        if let firstModelId = activeModelIds.first {
            let fallbackId = activeModelIds.first(where: { $0 != firstModelId })
            var modelDict: [String: Any] = ["primary": "\(activeProviderKey)/\(firstModelId)"]
            if let fb = fallbackId {
                modelDict["fallbacks"] = ["\(activeProviderKey)/\(fb)"]
            }
            defaults["model"] = modelDict
        }

        var modelsMapping: [String: Any] = [:]
        for mid in activeModelIds {
            modelsMapping["\(activeProviderKey)/\(mid)"] = [String: Any]()
        }
        defaults["models"] = modelsMapping

        // Update imageModel — only image-capable models, fallback is one model different from primary
        let imageModelIds: [String]
        if settings.activeServiceSource == "getclawhub" {
            let existingProviders = (dict["models"] as? [String: Any])?["providers"] as? [String: Any] ?? [:]
            if let hubProvider = existingProviders["getclawhub"] as? [String: Any],
               let hubModels = hubProvider["models"] as? [[String: Any]] {
                imageModelIds = hubModels.compactMap { m in
                    guard let mid = m["id"] as? String,
                          let input = m["input"] as? [String],
                          input.contains("image") else { return nil }
                    return mid
                }
            } else {
                imageModelIds = []
            }
        } else {
            imageModelIds = settings.configuredModels.filter { $0.input.contains("image") }.map { $0.id }
        }
        if let firstImageId = imageModelIds.first {
            let imageFallbackId = imageModelIds.first(where: { $0 != firstImageId })
            var imageDict: [String: Any] = ["primary": "\(activeProviderKey)/\(firstImageId)"]
            if let fb = imageFallbackId {
                imageDict["fallbacks"] = ["\(activeProviderKey)/\(fb)"]
            }
            defaults["imageModel"] = imageDict
        } else {
            defaults.removeValue(forKey: "imageModel")
        }

        agents["defaults"] = defaults

        // Update agents.list — replace model refs that point to removed providers
        let activeProviderKeys = Set((modelsNode["providers"] as? [String: Any] ?? [:]).keys)
        if var agentList = agents["list"] as? [[String: Any]] {
            let defaultModel = activeModelIds.first.map { "\(activeProviderKey)/\($0)" } ?? ""
            for i in agentList.indices {
                guard let model = agentList[i]["model"] as? String,
                      let slash = model.firstIndex(of: "/") else { continue }
                let modelProvider = String(model[model.startIndex..<slash])
                if !activeProviderKeys.contains(modelProvider) {
                    agentList[i]["model"] = defaultModel
                }
            }
            agents["list"] = agentList
        }

        dict["agents"] = agents

        return writeConfigDict(dict)
    }

    // MARK: - Open config file in editor

    func openConfigFile() {
        let url = URL(fileURLWithPath: configPath)
        if FileManager.default.fileExists(atPath: configPath) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - GetClawHub Provider

    /// Write (or update) the `getclawhub` provider entry in openclaw.json.
    /// Called by MembershipManager; does not touch other providers.
    static func writeGetClawHubProvider(apiKey: String, models: [PresetModel], baseUrl: String = "https://ai.getclawhub.com/v1") {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let fm = FileManager.default

        // Ensure directory exists
        let dirPath = NSString("~/.openclaw").expandingTildeInPath
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        var dict: [String: Any] = [:]
        if fm.fileExists(atPath: configPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        // Build getclawhub provider entry with full model details (same as custom provider)
        let modelEntries: [[String: Any]] = models.map { model in
            var m: [String: Any] = [
                "id": model.id,
                "name": model.name,
                "reasoning": model.reasoning,
                "input": model.input,
                "contextWindow": model.contextWindow,
                "maxTokens": model.maxTokens
            ]
            m["cost"] = [
                "input": model.cost.input,
                "output": model.cost.output,
                "cacheRead": model.cost.cacheRead,
                "cacheWrite": model.cost.cacheWrite
            ]
            return m
        }

        let providerEntry: [String: Any] = [
            "baseUrl": baseUrl,
            "apiKey": apiKey,
            "api": "openai-completions",
            "models": modelEntries
        ]

        var modelsNode = dict["models"] as? [String: Any] ?? [:]
        modelsNode["mode"] = "merge"
        // Replace all providers with only getclawhub
        modelsNode["providers"] = ["getclawhub": providerEntry]
        dict["models"] = modelsNode

        // Update agents.defaults: model, models, imageModel
        let modelIds = models.map { $0.id }
        var agents = dict["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]

        if let firstId = modelIds.first {
            let fallbackId = modelIds.first(where: { $0 != firstId })
            var modelDict: [String: Any] = ["primary": "getclawhub/\(firstId)"]
            if let fb = fallbackId {
                modelDict["fallbacks"] = ["getclawhub/\(fb)"]
            }
            defaults["model"] = modelDict
        }
        // imageModel — only models with image input, fallback is one different from primary
        let imageModelIds = models.filter { $0.input.contains("image") }.map { $0.id }
        if let firstImageId = imageModelIds.first {
            let imageFallbackId = imageModelIds.first(where: { $0 != firstImageId })
            var imageDict: [String: Any] = ["primary": "getclawhub/\(firstImageId)"]
            if let fb = imageFallbackId {
                imageDict["fallbacks"] = ["getclawhub/\(fb)"]
            }
            defaults["imageModel"] = imageDict
        } else {
            defaults.removeValue(forKey: "imageModel")
        }
        var modelsMapping: [String: Any] = [:]
        for mid in modelIds {
            modelsMapping["getclawhub/\(mid)"] = [String: Any]()
        }
        defaults["models"] = modelsMapping
        agents["defaults"] = defaults

        // Update agents.list — replace refs to removed providers
        if var agentList = agents["list"] as? [[String: Any]] {
            let defaultModel = modelIds.first.map { "getclawhub/\($0)" } ?? ""
            for i in agentList.indices {
                guard let model = agentList[i]["model"] as? String,
                      let slash = model.firstIndex(of: "/") else { continue }
                let modelProvider = String(model[model.startIndex..<slash])
                if modelProvider != "getclawhub" {
                    agentList[i]["model"] = defaultModel
                }
            }
            agents["list"] = agentList
        }
        dict["agents"] = agents

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
        }
    }

    // MARK: - Helpers

    /// Get the provider name (for display)
    func providerName() -> String {
        if !settings.selectedProviderKey.isEmpty {
            return settings.selectedProviderKey
        }
        guard let dict = readConfigDict(),
              let models = dict["models"] as? [String: Any],
              let providers = models["providers"] as? [String: Any],
              let firstKey = providers.keys.first else {
            return "unknown"
        }
        return firstKey
    }

    private func readConfigDict() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: configPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func writeConfigDict(_ dict: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Parse a model dictionary from JSON into PresetModel
    private static func parseModelDict(_ dict: [String: Any]) -> PresetModel? {
        guard let id = dict["id"] as? String else { return nil }
        let name = dict["name"] as? String ?? id
        let reasoning = dict["reasoning"] as? Bool ?? false
        let input = dict["input"] as? [String] ?? ["text"]
        let contextWindow = dict["contextWindow"] as? Int ?? 128000
        let maxTokens = dict["maxTokens"] as? Int ?? 8192

        var cost = PresetModelCost()
        if let costDict = dict["cost"] as? [String: Any] {
            cost.input = costDict["input"] as? Double ?? 0
            cost.output = costDict["output"] as? Double ?? 0
            cost.cacheRead = costDict["cacheRead"] as? Double ?? 0
            cost.cacheWrite = costDict["cacheWrite"] as? Double ?? 0
        }

        return PresetModel(
            id: id,
            name: name,
            reasoning: reasoning,
            input: input,
            cost: cost,
            contextWindow: contextWindow,
            maxTokens: maxTokens
        )
    }
}
