#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let dashboardPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let marketplacePath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceView.swift")
let overviewPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceOverviewView.swift")
let detailPath = root.appendingPathComponent("OpenClawInstaller/Views/Dashboard/MarketplaceDetailView.swift")
let modalPath = root.appendingPathComponent("OpenClawInstaller/Views/Shared/DashboardModalOverlay.swift")
let projectPath = root.appendingPathComponent("OpenClawInstaller.xcodeproj/project.pbxproj")

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ url: URL, _ label: String) -> String {
    guard let value = try? String(contentsOf: url, encoding: .utf8) else {
        fputs("FAIL: missing or unreadable \(label)\n", stderr)
        exit(1)
    }
    return value
}

let dashboard = read(dashboardPath, "DashboardView.swift")
let marketplace = read(marketplacePath, "MarketplaceView.swift")
let overview = read(overviewPath, "MarketplaceOverviewView.swift")
let detail = read(detailPath, "MarketplaceDetailView.swift")
let modal = read(modalPath, "DashboardModalOverlay.swift")
let project = read(projectPath, "project.pbxproj")

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let marketBranch = slice(
    dashboard,
    from: "case .market:",
    to: "case .tasksLogs:"
)
let marketplaceOverlay = slice(
    dashboard,
    from: "private func marketplaceDetailOverlay(for agent: MarketplaceAgent) -> some View",
    to: "private func presentPluginDetail"
)

require(
    modal.contains("struct DashboardModalOverlay<Content: View>: View") &&
        modal.contains("let isDismissDisabled: Bool") &&
        modal.contains("let onDismiss: () -> Void") &&
        modal.contains(".transition(.asymmetric("),
    "Dashboard modal chrome should be extracted into a reusable shared overlay component."
)
require(
    project.contains("DashboardModalOverlay.swift in Sources") &&
        project.contains("MarketplaceView.swift in Sources"),
    "New shared modal and Marketplace page files should be part of the Xcode target."
)
require(
    dashboard.contains("if let agent = viewModel.selectedMarketplaceAgent, shouldShowMarketplaceDetailOverlay") &&
        dashboard.contains("marketplaceDetailOverlay(for: agent)") &&
        dashboard.contains(".animation(marketplaceDetailAnimation, value: viewModel.selectedMarketplaceAgent?.id)") &&
        !marketBranch.contains("marketplaceDetailOverlay(for: agent)") &&
        !marketBranch.contains("MarketplaceDetailView("),
    "Marketplace detail should be mounted from the Dashboard root overlay, matching Skills and Plugins."
)
require(
    marketBranch.contains("MarketplaceView(") &&
        marketBranch.contains("selectedAgent: viewModel.selectedMarketplaceAgent") &&
        marketBranch.contains("onSelectAgent: onOpenMarketplaceDetail") &&
        !marketBranch.contains("MarketplaceOverviewView("),
    "Dashboard should render a MarketplaceView page container instead of owning marketplace list internals."
)
require(
    marketplace.contains("struct MarketplaceView: View") &&
        marketplace.contains("MarketplaceOverviewView(") &&
        marketplace.contains("selectedAgent: selectedAgent") &&
        marketplace.contains("onSelect: onSelectAgent"),
    "MarketplaceView should own page-level composition while MarketplaceOverviewView owns the grid/list."
)
require(
    overview.contains("let selectedAgent: MarketplaceAgent?") &&
        overview.contains("isSelected: selectedAgent?.id == agent.id") &&
        overview.contains("let isSelected: Bool") &&
        overview.contains("isSelected || isHovering"),
    "Marketplace overview cards should highlight from the same selected agent used by the detail overlay."
)
require(
    detail.contains("let onClose: () -> Void") &&
        detail.contains("Image(systemName: \"xmark\")") &&
        detail.contains(".disabled(isInstalling)") &&
        !detail.contains("Text(\"AgentsMarket\")"),
    "Marketplace detail should behave like a modal card with a close button, not a back-navigation page."
)
require(
    dashboard.contains("private let marketplaceDetailAnimation") &&
        dashboard.contains("private var shouldShowMarketplaceDetailOverlay: Bool") &&
        dashboard.contains("private func presentMarketplaceDetail(_ agent: MarketplaceAgent)") &&
        dashboard.contains("private func dismissMarketplaceDetail()") &&
        dashboard.contains("withAnimation(marketplaceDetailAnimation)") &&
        marketplaceOverlay.contains("DashboardModalOverlay(") &&
        marketplaceOverlay.contains("onDismiss: dismissMarketplaceDetail") &&
        !marketBranch.contains(".transition(.opacity.combined(with: .scale") &&
        !marketBranch.contains("withAnimation(.easeInOut(duration: 0.16))"),
    "Marketplace detail should use the same root-level animated modal pattern as Skills and Plugins."
)

print("Marketplace modal detail verification passed")
