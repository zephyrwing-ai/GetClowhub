import Foundation

@main
struct VerifySuperpowersPluginCatalog {
    static func main() throws {
        let catalogURL = URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-plugins-catalog").expandingTildeInPath)
        let items = try PluginCatalogService.parseCatalog(rootURL: catalogURL)
        let superpowersItems = items.filter { $0.name == "superpowers" }

        expect(superpowersItems.count == 1, "Superpowers should appear as one plugin catalog item")
        guard let item = superpowersItems.first else { return }

        expect(item.source == .recommend, "Superpowers should be tagged as recommended")
        expect(item.displayName == "Superpowers", "Superpowers display name should parse")
        expect(item.version == "6.1.0", "Superpowers version should match upstream package")
        expect(item.isOpenClawInstallable, "Superpowers should be OpenClaw installable")
        expect(item.iconURL?.lastPathComponent == "superpowers-small.svg", "Superpowers should use its own icon")
        expect(item.relativePath == "plugins/superpowers", "Superpowers should install from the plugin directory")

        let pluginURL = catalogURL.appendingPathComponent(item.relativePath)
        let skillsURL = pluginURL.appendingPathComponent("skills")
        let skills = try FileManager.default.contentsOfDirectory(
            at: skillsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        expect(skills.count >= 10, "Superpowers should preserve upstream bundled skills")
        expect(FileManager.default.fileExists(atPath: pluginURL.appendingPathComponent(".codex-plugin/plugin.json").path), "Superpowers should preserve upstream Codex plugin manifest")
        expect(FileManager.default.fileExists(atPath: pluginURL.appendingPathComponent("openclaw.plugin.json").path), "Superpowers should include OpenClaw catalog manifest")
        expect(FileManager.default.fileExists(atPath: pluginURL.appendingPathComponent("openclaw.adapter.js").path), "Superpowers should include OpenClaw adapter")

        print("Superpowers plugin catalog verification passed")
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
