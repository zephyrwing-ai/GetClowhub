#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let detailPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
let sharedButtonPath = root.appendingPathComponent("OpenClawInstaller/Views/Shared/CatalogActionButton.swift")
let projectPath = root.appendingPathComponent("OpenClawInstaller.xcodeproj/project.pbxproj")
let detail = try String(contentsOf: detailPath, encoding: .utf8)
let sharedButton = (try? String(contentsOf: sharedButtonPath, encoding: .utf8)) ?? ""
let project = try String(contentsOf: projectPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    sharedButton.contains("struct CatalogActionButton: View") &&
        sharedButton.contains("enum Tone") &&
        sharedButton.contains("enum State") &&
        sharedButton.contains("static let amber = Color(red: 0.72, green: 0.47, blue: 0.12)") &&
        sharedButton.contains("static let copper = Color(red: 0.66, green: 0.40, blue: 0.23)"),
    "Shared should define a reusable catalog action button with the Skills amber/copper palette."
)

require(
    sharedButton.contains("Capsule(style: .continuous)") &&
        sharedButton.contains(".font(.system(size: 13, weight: .medium))") &&
        sharedButton.contains(".frame(width: width, height: height)") &&
        sharedButton.contains("width: CGFloat = 92") &&
        sharedButton.contains("height: CGFloat = 30") &&
        sharedButton.contains("ProgressView()"),
    "Shared catalog action button should own the pill sizing, typography, capsule shape, and loading presentation."
)

require(
    project.contains("CatalogActionButton.swift in Sources") &&
        project.contains("CatalogActionButton.swift"),
    "Xcode project should include CatalogActionButton.swift in the Shared group and app target sources."
)

require(
    detail.contains("CatalogActionButton(") &&
        detail.contains("title: String(localized: \"Recruit\", bundle: languageManager.localizedBundle)") &&
        detail.contains("loadingTitle: String(localized: \"Recruiting...\", bundle: languageManager.localizedBundle)") &&
        detail.contains("completedTitle: String(localized: \"Recruited\", bundle: languageManager.localizedBundle)") &&
        detail.contains("state: recruitButtonState") &&
        detail.contains("action: installAgent"),
    "Marketplace detail should render recruitment through the shared catalog action button."
)

require(
    !detail.contains(".tint(isInstalled ? .green : .accentColor)") &&
        !detail.contains(".buttonStyle(.borderedProminent)") &&
        !detail.contains("MarketplaceRecruitButtonStyle") &&
        !detail.contains("MarketplaceRecruitPalette"),
    "Marketplace recruit button should not keep local blue or local private button styling."
)

print("Marketplace recruit button style verification passed")
