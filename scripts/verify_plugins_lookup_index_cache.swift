import Foundation

let pluginsTabURL = URL(fileURLWithPath: "OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let pluginsTab = try String(contentsOf: pluginsTabURL, encoding: .utf8)

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func slice(from start: String, to end: String) -> String {
    guard let startRange = pluginsTab.range(of: start) else { return "" }
    guard let endRange = pluginsTab[startRange.upperBound...].range(of: end) else {
        return String(pluginsTab[startRange.lowerBound...])
    }
    return String(pluginsTab[startRange.lowerBound..<endRange.lowerBound])
}

let catalogSection = slice(
    from: "private func catalogSection",
    to: "private func installedSection"
)
let installedSection = slice(
    from: "private func installedSection",
    to: "private func matchesSearch"
)
let lookupIndex = slice(
    from: "private struct PluginLookupIndex",
    to: "private enum PluginLibrarySection"
)

require(
    pluginsTab.contains("private var pluginLookupIndex: PluginLookupIndex"),
    "PluginsTabView should expose one lookup-index value for each render pass."
)
require(
    pluginsTab.contains("let lookup = pluginLookupIndex"),
    "PluginsTabView content should build the lookup index once before rendering rows."
)
require(
    pluginsTab.contains("private struct PluginLookupIndex"),
    "Plugin lookup dictionaries should live in a stored index object."
)
require(
    lookupIndex.contains("let installedPluginsByID: [String: PluginInfo]") &&
        lookupIndex.contains("let installedPluginsByChannel: [String: PluginInfo]") &&
        lookupIndex.contains("let catalogItemsByName: [String: PluginCatalogItem]") &&
        lookupIndex.contains("let catalogItemsByPluginID: [String: PluginCatalogItem]"),
    "PluginLookupIndex should hold catalog and installed dictionaries as stored values."
)
require(
    !pluginsTab.contains("private var installedPluginsByID: [String: PluginInfo]") &&
        !pluginsTab.contains("private var installedPluginsByChannel: [String: PluginInfo]"),
    "Installed plugin dictionaries must not remain computed properties on PluginsTabView."
)
require(
    catalogSection.contains("lookup: PluginLookupIndex") &&
        catalogSection.contains("let installedPlugin = lookup.installedPlugin(for: item)") &&
        !catalogSection.contains("let installedPlugin = installedPlugin(for: item)"),
    "Catalog rows should query the prebuilt lookup index, not rebuild installed dictionaries per row."
)
require(
    installedSection.contains("lookup: PluginLookupIndex") &&
        installedSection.contains("let catalogItem = lookup.catalogItem(for: plugin)") &&
        !installedSection.contains("let catalogItem = catalogItem(for: plugin)"),
    "Installed rows should query the prebuilt lookup index, not rebuild catalog dictionaries per row."
)
require(
    pluginsTab.contains("private func filteredInstalledPlugins(using lookup: PluginLookupIndex)") &&
        pluginsTab.contains("private func customInstalledPlugins(from plugins: [PluginInfo], using lookup: PluginLookupIndex)") &&
        pluginsTab.contains("private func installedSections(from plugins: [PluginInfo], using lookup: PluginLookupIndex)"),
    "Installed plugin filtering and sectioning should reuse the same lookup index."
)
require(
    !pluginsTab.contains("private func installedPlugin(for item: PluginCatalogItem)") &&
        !pluginsTab.contains("private func catalogItem(for plugin: PluginInfo)"),
    "PluginsTabView should not keep instance lookup helpers that read computed dictionaries."
)

print("Plugins lookup index cache verification passed")
