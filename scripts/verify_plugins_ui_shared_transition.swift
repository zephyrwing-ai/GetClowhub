import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let pluginsViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("PluginsTabView.swift")
let dashboardViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("DashboardView.swift")
let configViewURL = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("Views")
    .appendingPathComponent("Dashboard")
    .appendingPathComponent("ConfigTabView.swift")

let pluginsView = try String(contentsOf: pluginsViewURL, encoding: .utf8)
let dashboardView = try String(contentsOf: dashboardViewURL, encoding: .utf8)
let configView = try String(contentsOf: configViewURL, encoding: .utf8)
let pluginDetailOverlayView = section(
    in: dashboardView,
    from: "private func pluginDetailOverlay(for item: PluginDetailPresentationItem)",
    to: "private var installedSkillByName"
)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    !dashboardView.contains("pluginDetailNamespace"),
    "DashboardView should not keep a plugin detail namespace; Plugins should match the Skills sheet transition."
)
require(
    dashboardView.contains("@State private var selectedPluginDetailItem: PluginDetailPresentationItem?"),
    "DashboardView should own the selected plugin detail item like it owns selected skill details."
)
require(
    dashboardView.contains("private let pluginDetailAnimation"),
    "DashboardView should centralize the plugin detail spring animation."
)
require(
    dashboardView.contains("withAnimation(pluginDetailAnimation)"),
    "DashboardView should open and close plugin details with the shared spring animation."
)
require(
    dashboardView.contains("onOpenPluginDetail: presentPluginDetail"),
    "DashboardView should route plugin row clicks into the global plugin detail presenter."
)
require(
    dashboardView.contains("if let selectedPluginDetailItem, shouldShowPluginDetailOverlay"),
    "DashboardView should render the plugin detail overlay at the app overlay level."
)
require(
    dashboardView.contains("private var shouldShowPluginDetailOverlay: Bool"),
    "DashboardView should centralize plugin detail overlay visibility."
)
require(
    dashboardView.contains("private func pluginDetailOverlay(for item: PluginDetailPresentationItem)"),
    "DashboardView should implement the plugin detail overlay beside the skill detail overlay."
)
require(
    dashboardView.contains("PluginCatalogDetailSheet("),
    "DashboardView should host the plugin detail sheet."
)
require(
    pluginDetailOverlayView.contains(".background(.regularMaterial)"),
    "Plugin detail overlay should match the Skills detail material background modifier."
)
require(
    pluginDetailOverlayView.contains(".transition(.asymmetric("),
    "Plugin detail overlay should keep the Skills-style opacity and scale transition."
)
require(
    !pluginDetailOverlayView.contains("matchedGeometryEffect"),
    "Plugin detail overlay should not use matchedGeometryEffect because the Skills sheet does not use a shared element transition."
)
require(
    !pluginsView.contains("matchedGeometryEffect"),
    "Plugin list rows should not use matchedGeometryEffect; row clicks should open the same style sheet as Skills."
)
require(
    !pluginsView.contains("Namespace.ID"),
    "PluginsTabView should not accept a Namespace.ID after removing shared element transitions."
)
require(
    !configView.contains("pluginDetailNamespace"),
    "ConfigTabView should not pass a plugin detail namespace after removing shared element transitions."
)
require(
    pluginsView.contains("let onOpenPluginDetail: (PluginDetailPresentationItem) -> Void"),
    "PluginsTabView should emit detail presentation items instead of owning the overlay."
)
require(
    !dashboardView.contains("Color(NSColor.windowBackgroundColor).opacity"),
    "Plugin detail overlay should not add an extra translucent color layer over the Skills-style material card."
)
require(
    !pluginsView.contains("@State private var selectedDetailItem"),
    "PluginsTabView should not own selected detail state."
)
require(
    !pluginsView.contains("private var detailOverlay"),
    "PluginsTabView should not render the plugin detail overlay inside the scroll view."
)
require(
    !pluginsView.contains("detailBackdropOpacity"),
    "PluginsTabView should not carry overlay backdrop styling."
)

print("Plugins sheet transition verification passed")

func section(in text: String, from startMarker: String, to endMarker: String) -> String {
    guard let startRange = text.range(of: startMarker) else { return "" }
    guard let endRange = text[startRange.upperBound...].range(of: endMarker) else {
        return String(text[startRange.lowerBound...])
    }
    return String(text[startRange.lowerBound..<endRange.lowerBound])
}
