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

let app = read("OpenClawInstaller/OpenClawInstallerApp.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let localizable = read("OpenClawInstaller/Localizable.xcstrings")
let languageManager = read("OpenClawInstaller/Services/LanguageManager.swift")

require(
    app.contains("@StateObject private var languageManager = LanguageManager.shared"),
    "App entry should inject the existing LanguageManager.shared instance, not create a second LanguageManager."
)

require(
    !app.contains("@StateObject private var languageManager = LanguageManager()"),
    "App entry must not create a second LanguageManager instance."
)

let forbiddenDashboardPatterns = [
    "hasPrefix(\"zh\")",
    "isChinese ?",
    "let isChinese =",
    "private var isChinese:"
]

for pattern in forbiddenDashboardPatterns {
    require(
        !dashboard.contains(pattern),
        "DashboardView should not contain per-view Chinese/English branching: \(pattern)"
    )
}

let requiredLocalizedKeys = [
    "Understanding requirements...",
    "Starting task execution...",
    "Working",
    "Working for %@",
    "Done in %@",
    "%lldm %llds",
    "%llds"
]

for key in requiredLocalizedKeys {
    require(
        localizable.contains("\"\(key)\""),
        "Localizable.xcstrings should contain key: \(key)"
    )
}

func supportedLanguageIDs(from source: String) -> [String] {
    let pattern = #"Language\(id: "([^"]+)""#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
        guard let idRange = Range(match.range(at: 1), in: source) else { return nil }
        let id = String(source[idRange])
        return id == "system" ? nil : id
    }
}

let supportedLanguages = supportedLanguageIDs(from: languageManager)
require(!supportedLanguages.isEmpty, "LanguageManager should define supported language IDs.")

let dashboardLocalizedKeysRequiringFullCoverage = [
    "New chat",
    "Search chats",
    "Skills",
    "Plugins",
    "Automation",
    "AgentsMarket",
    "What should we build today?",
    "Ask Anything"
]

let localizableData = Data(localizable.utf8)
guard
    let catalog = try JSONSerialization.jsonObject(with: localizableData) as? [String: Any],
    let strings = catalog["strings"] as? [String: Any]
else {
    fputs("FAIL: could not parse Localizable.xcstrings as JSON\n", stderr)
    exit(1)
}

for key in dashboardLocalizedKeysRequiringFullCoverage {
    guard let entry = strings[key] as? [String: Any] else {
        fputs("FAIL: missing localized key: \(key)\n", stderr)
        exit(1)
    }
    let localizations = entry["localizations"] as? [String: Any] ?? [:]
    let missing = supportedLanguages.filter { languageID in
        guard
            let localization = localizations[languageID] as? [String: Any],
            let stringUnit = localization["stringUnit"] as? [String: Any],
            let value = stringUnit["value"] as? String
        else {
            return true
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    require(
        missing.isEmpty,
        "\(key) should have translations for every supported language; missing: \(missing.joined(separator: ", "))"
    )
}

print("Language localization architecture verification passed")
