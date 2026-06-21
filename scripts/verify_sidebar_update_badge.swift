#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Missing file: \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ text: String, from start: String, to end: String) -> String {
    guard let startRange = text.range(of: start),
          let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
        fatalError("Unable to locate slice markers")
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}

let updater = read("OpenClawInstaller/Services/SparkleUpdater.swift")
let app = read("OpenClawInstaller/OpenClawInstallerApp.swift")
let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let topHeader = slice(
    dashboard,
    from: "private var sidebarTopHeader: some View",
    to: "// MARK: - Sidebar Main List"
)

require(
    updater.contains("hasCheckedLatestVersionThisLaunch"),
    "SparkleUpdater should remember that the launch-time silent check already ran"
)
require(
    updater.contains("func checkLatestVersionOnLaunch() async"),
    "SparkleUpdater should expose a launch-only silent version check"
)
require(
    app.contains("Task { await sparkleUpdater.checkLatestVersionOnLaunch() }"),
    "OpenClawInstallerApp should start the launch-time silent version check"
)
require(
    topHeader.contains("sparkleUpdater.updateAvailable"),
    "Sidebar top header should react to updateAvailable"
)
require(
    topHeader.contains("sparkleUpdater.checkForUpdates()"),
    "Sidebar top header update badge should open Sparkle's update flow"
)
require(
    topHeader.contains("sparkleUpdater.latestVersion"),
    "Sidebar top header should show the remote version next to GetClawHub"
)
require(
    topHeader.contains("arrow.up.circle.fill"),
    "Sidebar top header update badge should use the upgrade icon"
)

print("PASS: sidebar update badge wiring verified")
