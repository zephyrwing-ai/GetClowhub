#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let configURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("ConfigTabView.swift")

let config = try String(contentsOf: configURL, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let settingsSidebar = slice(
    config,
    from: "private struct SettingsSectionSidebar: View",
    to: "private struct SettingsSectionRow: View"
)

require(
    config.contains("private struct SettingsSectionRow: View"),
    "Settings sidebar should use a dedicated row view so the full hit area is enforced in one place."
)

let settingsRow = slice(
    config,
    from: "private struct SettingsSectionRow: View",
    to: "private struct SettingsCard<Content: View>: View"
)

require(
    settingsRow.contains("let isSelected: Bool") &&
        settingsRow.contains("let action: () -> Void"),
    "Settings section row should receive selected state and selection action explicitly."
)

require(
    settingsRow.contains(".frame(maxWidth: .infinity, alignment: .leading)") &&
        settingsRow.contains(".contentShape(Rectangle())") &&
        settingsRow.contains(".buttonStyle(.plain)"),
    "Settings section row should make the entire visible row hit-testable, not only the icon and text."
)

require(
    settingsRow.contains("RoundedRectangle(cornerRadius: 8, style: .continuous)") &&
        settingsRow.contains("isSelected ? Color.primary.opacity(0.10) : Color.clear"),
    "Settings section row should preserve the existing selected-row visual treatment."
)

require(
    settingsSidebar.contains("SettingsSectionRow(") &&
        settingsSidebar.contains("section: section") &&
        settingsSidebar.contains("isSelected: selectedSection == section") &&
        settingsSidebar.contains("selectedSection = section"),
    "Settings sidebar should route every section through the full-width row component."
)

print("Settings page sidebar hit-area verification passed")
