#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let overviewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let detailPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")

let overview = try String(contentsOf: overviewPath, encoding: .utf8)
let detail = try String(contentsOf: detailPath, encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    overview.contains("enum MarketplacePageLayout") &&
        overview.contains("static let contentMaxWidth: CGFloat = 760") &&
        overview.contains("static let horizontalPadding: CGFloat = 24"),
    "Marketplace should centralize the same content width and horizontal padding used by Skills and Plugins."
)
require(
    overview.contains(".frame(maxWidth: MarketplacePageLayout.contentMaxWidth, alignment: .leading)") &&
        overview.contains(".padding(.horizontal, MarketplacePageLayout.horizontalPadding)") &&
        overview.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)"),
    "Marketplace overview should center a constrained content column inside the full page."
)
require(
    detail.contains(".frame(width: 640)") &&
        detail.contains(".clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))") &&
        detail.contains(".shadow("),
    "Marketplace detail should render as a centered modal card, not a full-width page."
)
require(
    !overview.contains(".padding(.horizontal, 24)") &&
        !detail.contains(".padding(32)"),
    "Marketplace layout should not keep older full-width page padding that bypasses the shared page column."
)

print("Marketplace centered layout verification passed")
