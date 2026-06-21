import Foundation

@main
struct VerifyPluginCatalogOpenClawAdapters {
    static func main() throws {
        let cacheURL = PluginCatalogService.defaultCacheURL
        let items = try PluginCatalogService.parseCatalog(rootURL: cacheURL)
        expect(!items.isEmpty, "plugin catalog should not be empty")

        var failures: [String] = []
        let marketplaceURL = cacheURL
            .appendingPathComponent(".agents")
            .appendingPathComponent("plugins")
            .appendingPathComponent("marketplace.json")
        if let marketplaceText = try? String(contentsOf: marketplaceURL, encoding: .utf8),
           marketplaceText.range(of: "codex", options: [.caseInsensitive]) != nil {
            failures.append("marketplace.json should not contain Codex user-facing wording")
        }

        for item in items {
            let pluginURL = cacheURL.appendingPathComponent(item.relativePath)
            let packageURL = pluginURL.appendingPathComponent("package.json")
            let manifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")
            let sourceManifestURL = pluginURL
                .appendingPathComponent(".codex-plugin")
                .appendingPathComponent("plugin.json")
            var runtimeURLs: [URL] = []
            if let packageData = try? Data(contentsOf: packageURL),
               let packageJSON = try? JSONSerialization.jsonObject(with: packageData) as? [String: Any],
               let openclaw = packageJSON["openclaw"] as? [String: Any],
               let extensions = openclaw["extensions"] as? [String] {
                runtimeURLs = extensions.map { pluginURL.appendingPathComponent($0) }
            }

            if !FileManager.default.fileExists(atPath: packageURL.path) {
                failures.append("\(item.name): missing package.json")
            }
            if !FileManager.default.fileExists(atPath: manifestURL.path) {
                failures.append("\(item.name): missing openclaw.plugin.json")
            }
            if FileManager.default.fileExists(atPath: sourceManifestURL.path) {
                failures.append("\(item.name): should not keep .codex-plugin/plugin.json in the OpenClaw catalog")
            }
            if runtimeURLs.isEmpty {
                failures.append("\(item.name): package.json does not expose OpenClaw extensions")
            }
            for runtimeURL in runtimeURLs where !FileManager.default.fileExists(atPath: runtimeURL.path) {
                failures.append("\(item.name): missing OpenClaw extension \(runtimeURL.lastPathComponent)")
            }
            if !item.isOpenClawInstallable {
                failures.append("\(item.name): catalog item is not OpenClaw installable")
            }

            let userFacingURLs = [packageURL, manifestURL] + runtimeURLs
            for url in userFacingURLs where FileManager.default.fileExists(atPath: url.path) {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if text.range(of: "codex", options: [.caseInsensitive]) != nil {
                    failures.append("\(item.name): user-facing OpenClaw adapter mentions Codex in \(url.lastPathComponent)")
                }
            }
        }

        let installCommands = items.map { PluginCatalogService.installCommand(for: $0, cacheURL: cacheURL) }
        if installCommands.contains(where: { $0.range(of: "codex", options: [.caseInsensitive]) != nil }) {
            failures.append("install commands should not use Codex")
        }
        if installCommands.contains(where: { !$0.contains("openclaw plugins install") }) {
            failures.append("install commands should use openclaw plugins install")
        }

        if !failures.isEmpty {
            fputs("FAIL:\n\(failures.prefix(25).joined(separator: "\n"))\n", stderr)
            if failures.count > 25 {
                fputs("... \(failures.count - 25) more failures\n", stderr)
            }
            exit(1)
        }

        print("Verified \(items.count) plugin catalog items expose OpenClaw adapters")
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
