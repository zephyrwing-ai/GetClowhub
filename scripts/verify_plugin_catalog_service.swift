import Foundation

@main
struct VerifyPluginCatalogService {
    static func main() throws {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("getclawhub-plugin-catalog-test-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: rootURL) }

        func write(_ relativePath: String, _ content: String) throws {
            let url = rootURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        try write(".agents/plugins/marketplace.json", """
        {
          "name": "getclawhub-plugins",
          "interface": { "displayName": "GetClowHub Plugins" },
          "plugins": [
            {
              "name": "alpha",
              "path": "./plugins/alpha",
              "tags": [],
              "category": "Productivity"
            },
            {
              "name": "beta",
              "source": {
                "source": "local",
                "path": "./plugins/beta"
              },
              "tags": ["recommend"],
              "category": "Developer Tools"
            },
            {
              "name": "gamma",
              "path": "./plugins/gamma",
              "recommended": true,
              "category": "Productivity"
            }
          ]
        }
        """)

        try write("plugins/alpha/package.json", """
        {
          "name": "@getclowhub/alpha",
          "version": "1.0.0",
          "openclaw": { "extensions": ["./index.ts"] }
        }
        """)
        try write("plugins/alpha/openclaw.plugin.json", """
        {
          "id": "alpha",
          "displayName": "Alpha Plugin",
          "description": "Alpha short",
          "longDescription": "Alpha long",
          "version": "1.0.0",
          "developerName": "GetClowHub",
          "category": "Productivity",
          "capabilities": ["Read", "Write"],
          "systemIcon": "rectangle.compress.vertical",
          "icon": "./assets/icon.png",
          "configSchema": { "type": "object", "properties": {} }
        }
        """)
        try write("plugins/alpha/index.ts", "export default function() {}\n")
        try write("plugins/alpha/assets/icon.png", "not-a-real-png")

        try write("plugins/beta/package.json", """
        {
          "name": "@getclowhub/beta",
          "version": "1.0.0",
          "openclaw": { "extensions": ["./index.ts"] }
        }
        """)
        try write("plugins/beta/openclaw.plugin.json", """
        {
          "id": "beta",
          "displayName": "Beta Plugin",
          "description": "Beta short",
          "longDescription": "Beta long",
          "version": "1.0.0",
          "developerName": "GetClowHub",
          "category": "Developer Tools"
        }
        """)
        try write("plugins/beta/index.ts", "export default function() {}\n")

        try write("plugins/gamma/package.json", """
        {
          "name": "@getclowhub/gamma",
          "version": "1.0.0",
          "openclaw": { "extensions": ["./index.ts"] }
        }
        """)
        try write("plugins/gamma/openclaw.plugin.json", """
        {
          "id": "gamma",
          "displayName": "Gamma Plugin",
          "description": "Gamma short",
          "longDescription": "Gamma long",
          "version": "1.0.0",
          "developerName": "GetClowHub",
          "category": "Productivity"
        }
        """)
        try write("plugins/gamma/index.ts", "export default function() {}\n")

        let items = try PluginCatalogService.parseCatalog(rootURL: rootURL)
        expect(items.count == 3, "expected three plugin catalog items")

        let alpha = items.first { $0.name == "alpha" }
        let beta = items.first { $0.name == "beta" }
        let gamma = items.first { $0.name == "gamma" }
        expect(alpha != nil, "expected alpha plugin")
        expect(beta != nil, "expected beta plugin")
        expect(gamma != nil, "expected gamma plugin")
        expect(alpha?.source == .all, "alpha should come from all-tagged catalog entries")
        expect(beta?.source == .recommend, "beta should come from recommend-tagged catalog entries")
        expect(beta?.isRecommended == true, "beta should be recommended")
        expect(gamma?.source == .recommend, "gamma should come from recommended marketplace entries")
        expect(gamma?.isRecommended == true, "gamma should be recommended")
        expect(alpha?.displayName == "Alpha Plugin", "alpha display name should use manifest interface")
        expect(alpha?.description == "Alpha short", "alpha description should use short description")
        expect(alpha?.longDescription == "Alpha long", "alpha long description should parse")
        expect(alpha?.openClawPluginID == "alpha", "alpha should use openclaw.plugin.json id")
        expect(alpha?.isOpenClawInstallable == true, "alpha should be installable")
        expect(alpha?.systemIconName == "rectangle.compress.vertical", "alpha system icon should parse from manifest")
        expect(alpha?.iconURL != nil, "alpha icon should resolve from manifest")

        expect(
            PluginCatalogService.defaultCacheURL.path.hasSuffix("/.openclaw/getclowhub-plugins-catalog"),
            "plugin catalog should cache under the user's .openclaw directory"
        )

        let command = PluginCatalogService.installCommand(for: beta!, cacheURL: rootURL)
        expect(command.contains("openclaw plugins install"), "install command should call openclaw")
        expect(command.contains("plugins/beta"), "install command should point at cached beta directory")

        let syncCommand = PluginCatalogService.syncCommand(cacheURL: rootURL)
        expect(syncCommand.contains("git clone --depth 1"), "sync command should clone the remote catalog when the cache is missing")
        expect(syncCommand.contains("fetch origin main"), "sync command should fetch origin/main for existing plugin caches")
        expect(syncCommand.contains("reset --hard origin/main"), "sync command should let the remote plugin catalog overwrite the local cache")
        expect(syncCommand.contains("clean -fd"), "sync command should remove stale local cache files that no longer exist upstream")
        expect(!syncCommand.contains("rsync"), "sync command should not mirror plugin catalog into the app source tree")
        expect(syncCommand.contains("GetClawHubPlugins"), "sync command should stay bound to the user's plugin origin repository")

        print("Plugin catalog service verification passed")
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
