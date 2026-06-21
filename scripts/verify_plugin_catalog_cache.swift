import Foundation

@main
struct VerifyPluginCatalogCache {
    static func main() throws {
        let cacheURL = PluginCatalogService.defaultCacheURL
        let items = try PluginCatalogService.parseCatalog(rootURL: cacheURL)
        let recommendedItems = items.filter(\.isRecommended)
        let iconItems = items.filter { $0.iconURL != nil }
        let legacyPathItems = items.filter {
            $0.relativePath.hasPrefix("plugins/All/") ||
            $0.relativePath.hasPrefix("plugins/recommend/")
        }

        expect(items.count >= 50, "expected the plugin cache to expose the remote marketplace catalog")
        expect(!recommendedItems.isEmpty, "expected the plugin cache marketplace JSON to tag recommended plugins")
        expect(!iconItems.isEmpty, "expected plugin icons to resolve from repository assets")
        expect(legacyPathItems.isEmpty, "plugin cache should not use legacy plugins/All or plugins/recommend paths")

        print("Plugin catalog cache verification passed")
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
