#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fail("Could not read \(path)")
    }
    return text
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let dashboardViewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let assistantRenderer = read("OpenClawInstaller/Views/Dashboard/AssistantMessageRenderer.swift")

let removedPaths = [
    "OpenClawInstaller/Models/A2UICardPayload.swift",
    "OpenClawInstaller/Views/Dashboard/A2UICardView.swift"
]

for path in removedPaths {
    expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), "\(path) should be removed for this release")
}

for forbidden in [
    "A2UICardPayload",
    "A2UICardView",
    "A2UICardParser",
    "A2UIComponent",
    "AssistantA2UIRendering",
    "a2uiDisplayCardInstruction"
] {
    expect(!project.contains(forbidden), "Xcode project should not reference \(forbidden)")
    expect(!dashboardViewModel.contains(forbidden), "DashboardViewModel should not reference \(forbidden)")
    expect(!assistantRenderer.contains(forbidden), "AssistantMessageRenderer should not reference \(forbidden)")
}

expect(!assistantRenderer.contains("case a2ui"), "Assistant render model should not include an A2UI renderer case")
expect(!assistantRenderer.contains("logRenderMode(\"a2ui\")"), "Assistant renderer should not log A2UI render mode")

print("PASS: A2UI release removal verified")
