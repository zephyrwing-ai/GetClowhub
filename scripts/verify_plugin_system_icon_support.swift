import Foundation

@main
struct VerifyPluginSystemIconSupport {
    static func main() throws {
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let catalogURL = URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-plugins-catalog").expandingTildeInPath)

        let itemModel = try read(projectURL.appendingPathComponent("OpenClawInstaller/Models/PluginCatalogItem.swift"))
        expect(itemModel.contains("let systemIconName: String?"), "PluginCatalogItem should store a system icon name")

        let catalogService = try read(projectURL.appendingPathComponent("OpenClawInstaller/Services/PluginCatalogService.swift"))
        expect(catalogService.contains("let systemIcon: String?"), "OpenClawPluginManifest should decode systemIcon")
        expect(catalogService.contains("systemIconName:"), "PluginCatalogService should pass systemIcon into PluginCatalogItem")
        expect(catalogService.contains("forKey: .systemIcon"), "OpenClawPluginManifest should read the systemIcon JSON key")

        let pluginsView = try read(projectURL.appendingPathComponent("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift"))
        expect(pluginsView.contains("systemIconName: item.systemIconName"), "catalog rows should pass systemIconName to PluginCatalogIcon")
        expect(pluginsView.contains("systemIconName: catalogItem?.systemIconName"), "installed rows should pass catalog systemIconName to PluginCatalogIcon")
        expect(pluginsView.contains("Image(systemName: systemIconName)"), "PluginCatalogIcon should render SF Symbols before file icons")

        let contextModeManifest = try read(catalogURL.appendingPathComponent("plugins/context-mode/openclaw.plugin.json"))
        expect(contextModeManifest.contains("\"systemIcon\": \"rectangle.compress.vertical\""), "Context Mode should declare the rectangle.compress.vertical SF Symbol")
        expect(contextModeManifest.contains("\"icon\": \"./assets/context-mode.svg\""), "Context Mode should retain the SVG icon for older app versions")

        let superpowersManifest = try read(catalogURL.appendingPathComponent("plugins/superpowers/openclaw.plugin.json"))
        expect(superpowersManifest.contains("\"icon\": \"./assets/superpowers-small.svg\""), "Superpowers should keep its upstream icon")
        expect(!superpowersManifest.contains("\"systemIcon\""), "Superpowers should not be converted to a system icon")

        print("Plugin system icon support verification passed")
    }

    private static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    @discardableResult
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) -> Bool {
        if condition() {
            return true
        }
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
