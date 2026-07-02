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

let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let localizable = read("OpenClawInstaller/Localizable.xcstrings")
let settingsI18nZH = read("OpenClawInstaller/Resources/I18n/zh-Hans/settings.json")

require(
    config.contains("@EnvironmentObject var languageManager: LanguageManager"),
    "ConfigTabView should use the existing LanguageManager environment object"
)
require(
    config.contains("I18n.t("),
    "ConfigTabView should centralize settings UI localization through I18n.t(_:)"
)
require(
    !config.contains("String(localized:"),
    "ConfigTabView should not read Localizable.xcstrings directly; settings strings should flow through I18n resources"
)

let forbiddenLiteralPatterns = [
    #"Text\("(Profile|Preferences|Settings|Account|System|Configuration|Advanced|Gateway|Port|Auth Token|GetClawHub Official Service|Recommended|Membership|Budget|API Base URL|API Key|Available Models|Custom API Provider|Provider|Models|Reset|Save|Save & Restart|Open Providers Preset|Open Config File|You have unsaved changes)""#,
    #"Button\("(Manage|Log Out|Log In|Generate Key|Sync|Retry|Cancel|Switch)""#,
    #"\.alert\("Switch Provider""#
]

for pattern in forbiddenLiteralPatterns {
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(config.startIndex..<config.endIndex, in: config)
    require(regex.firstMatch(in: config, range: range) == nil, "ConfigTabView still has hardcoded settings UI text matching pattern: \(pattern)")
}

let requiredKeys = [
    "Settings",
    "Profile",
    "Preferences",
    "Persona",
    "Status",
    "Gateway",
    "API Key",
    "Provider",
    "Budget",
    "Models",
    "Channels",
    "Logs",
    "Account",
    "System",
    "Configuration",
    "Advanced",
    "Language",
    "Use your preferred app language.",
    "Appearance",
    "Choose a mode and preview how the workspace will feel.",
    "Accent",
    "Applies to controls and selected states.",
    "Port",
    "Gateway listening port",
    "Auth Token",
    "Authentication token for gateway access",
    "Hide",
    "Show",
    "GetClawHub Official Service",
    "Recommended",
    "Membership",
    "Manage",
    "(expires %@)",
    "%@ / month",
    "Available Models",
    "No matching models found in the official provider preset.",
    "%lld models available",
    "No API Key yet",
    "Generate Key",
    "Sync",
    "Syncing membership info...",
    "Sync failed: %@",
    "Retry",
    "Loading membership info...",
    "Log in to use GetClawHub AI service",
    "Log In",
    "Custom API Provider",
    "Use your own API Key",
    "Switch Provider",
    "Cancel",
    "Switch",
    "Switching provider will replace the current Base URL. API Key will be cleared. Continue?",
    "%lld models configured",
    "Fetch Models",
    "Fetch models from this provider or add them before saving.",
    "Reset",
    "Save",
    "Save & Restart",
    "Edit the full configuration file directly for advanced settings.",
    "Open Providers Preset",
    "Open Config File",
    "You have unsaved changes"
]

let data = Data(localizable.utf8)
guard
    let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
    let strings = catalog["strings"] as? [String: Any]
else {
    fputs("FAIL: could not parse Localizable.xcstrings as JSON\n", stderr)
    exit(1)
}

let i18nData = Data(settingsI18nZH.utf8)
guard let settingsI18n = try JSONSerialization.jsonObject(with: i18nData) as? [String: String] else {
    fputs("FAIL: could not parse unified zh-Hans settings i18n resource\n", stderr)
    exit(1)
}

for key in requiredKeys {
    guard let entry = strings[key] as? [String: Any] else {
        fputs("FAIL: missing settings localization key: \(key)\n", stderr)
        exit(1)
    }
    let localizations = entry["localizations"] as? [String: Any] ?? [:]
    for localeID in ["zh-Hans", "zh-Hant"] {
        guard
            let localization = localizations[localeID] as? [String: Any],
            let stringUnit = localization["stringUnit"] as? [String: Any],
            let value = stringUnit["value"] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            fputs("FAIL: \(key) is missing \(localeID) settings localization\n", stderr)
            exit(1)
        }
    }
    guard let value = settingsI18n[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fputs("FAIL: unified settings i18n resource is missing key: \(key)\n", stderr)
        exit(1)
    }
}

print("Settings localization verification passed")
