import Foundation

enum PluginCatalogService {
    static let repositoryURL = "https://github.com/zephyrwing-ai/GetClawHubPlugins"
    static let repositoryIdentifier = "zephyrwing-ai/GetClawHubPlugins"

    static var defaultCacheURL: URL {
        URL(fileURLWithPath: NSString("~/.openclaw/getclowhub-plugins-catalog").expandingTildeInPath)
    }

    static func syncCommand(cacheURL: URL = defaultCacheURL) -> String {
        let cachePath = shellQuote(cacheURL.path)
        let parentPath = shellQuote(cacheURL.deletingLastPathComponent().path)
        let repo = shellQuote(repositoryURL)
        return """
        mkdir -p \(parentPath); \
        if [ -d \(cachePath)/.git ]; then \
        git -C \(cachePath) fetch origin main && git -C \(cachePath) reset --hard origin/main && git -C \(cachePath) clean -fd; \
        else rm -rf \(cachePath) && git clone --depth 1 \(repo) \(cachePath); fi
        """
    }

    static func installCommand(for item: PluginCatalogItem, cacheURL: URL = defaultCacheURL) -> String {
        let pluginURL = cacheURL.appendingPathComponent(item.relativePath)
        return "openclaw plugins install \(shellQuote(pluginURL.path))"
    }

    static func parseCatalog(rootURL: URL) throws -> [PluginCatalogItem] {
        let pluginsURL = rootURL.appendingPathComponent("plugins")
        guard FileManager.default.fileExists(atPath: pluginsURL.path) else {
            throw PluginCatalogError.missingPluginsDirectory
        }

        let marketplaceItems = parseMarketplaceCatalog(rootURL: rootURL)
        if !marketplaceItems.isEmpty {
            return sortCatalogItems(marketplaceItems)
        }

        let scannedItems = pluginDirectories(in: pluginsURL).compactMap { pluginURL -> CatalogEntry? in
            guard let item = parsePlugin(rootURL: rootURL, pluginURL: pluginURL, source: .all) else {
                return nil
            }
            return CatalogEntry(item: item, order: nil)
        }

        return sortCatalogItems(scannedItems)
    }

    private static func parseMarketplaceCatalog(rootURL: URL) -> [CatalogEntry] {
        let manifestURL = rootURL
            .appendingPathComponent(".agents")
            .appendingPathComponent("plugins")
            .appendingPathComponent("marketplace.json")
        guard let manifest: PluginMarketplaceManifest = decodeJSON(manifestURL) else {
            return []
        }

        var itemsByName: [String: CatalogEntry] = [:]
        for (index, entry) in manifest.plugins.enumerated() {
            guard let pluginURL = pluginURL(for: entry, rootURL: rootURL),
                  let item = parsePlugin(
                    rootURL: rootURL,
                    pluginURL: pluginURL,
                    source: entry.catalogSource
                  ) else {
                continue
            }

            let catalogEntry = CatalogEntry(item: item, order: entry.order ?? index)
            if let existingEntry = itemsByName[item.name],
               shouldKeep(existingEntry, over: catalogEntry) {
                continue
            }
            itemsByName[item.name] = catalogEntry
        }

        return Array(itemsByName.values)
    }

    private static func pluginURL(for entry: PluginMarketplaceEntry, rootURL: URL) -> URL? {
        let fallbackName = entry.name?.nilIfBlank ?? entry.id?.nilIfBlank
        guard var path = entry.path?.nilIfBlank
            ?? entry.source?.path?.nilIfBlank
            ?? fallbackName.map({ "plugins/\($0)" }) else {
            return nil
        }

        while path.hasPrefix("./") {
            path.removeFirst(2)
        }

        guard !path.hasPrefix("/"), !path.contains("://") else {
            return nil
        }

        let rootPath = rootURL.standardizedFileURL.path
        let pluginURL = rootURL.appendingPathComponent(path).standardizedFileURL
        guard pluginURL.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return pluginURL
    }

    private static func pluginDirectories(in rootURL: URL) -> [URL] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories
            .filter { (try? isDirectory($0)) == true }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private static func parsePlugin(
        rootURL: URL,
        pluginURL: URL,
        source: PluginCatalogSource
    ) -> PluginCatalogItem? {
        let packageURL = pluginURL.appendingPathComponent("package.json")
        let openClawManifestURL = pluginURL.appendingPathComponent("openclaw.plugin.json")

        let packageManifest: PackageManifest? = decodeJSON(packageURL)
        let openClawManifest: OpenClawPluginManifest? = decodeJSON(openClawManifestURL)

        let folderName = pluginURL.lastPathComponent
        let name = (openClawManifest?.id)?.nilIfBlank
            ?? unscopedPackageName(packageManifest?.name)
            ?? folderName
        let openClawPluginID = (openClawManifest?.id)?.nilIfBlank
            ?? unscopedPackageName(packageManifest?.name)
            ?? name
        let displayName = (openClawManifest?.displayName)?.nilIfBlank
            ?? (openClawManifest?.name)?.nilIfBlank
            ?? displayNameForPlugin(name)
        let description = (openClawManifest?.description)?.nilIfBlank
            ?? (packageManifest?.description)?.nilIfBlank
            ?? "OpenClaw plugin"
        let longDescription = (openClawManifest?.longDescription)?.nilIfBlank
            ?? readMarkdownSummary(in: pluginURL)
            ?? description
        let version = (openClawManifest?.version)?.nilIfBlank
            ?? (packageManifest?.version)?.nilIfBlank
            ?? ""
        let developerName = (openClawManifest?.developerName)?.nilIfBlank
            ?? ""
        let category = (openClawManifest?.category)?.nilIfBlank
            ?? categoryFromOpenClawManifest(openClawManifest, packageManifest: packageManifest)
        let capabilities = openClawManifest?.capabilities ?? []
        let keywords = openClawManifest?.keywords ?? packageManifest?.keywords ?? []
        let relativePath = relativePath(from: rootURL, to: pluginURL)
        let systemIconName = (openClawManifest?.systemIcon)?.nilIfBlank
        let iconURL = preferredIconURL(in: pluginURL, iconPath: openClawManifest?.icon)
        let hasExtensions = packageManifest?.openclaw?.extensions.isEmpty == false
        let isInstallable = hasExtensions && FileManager.default.fileExists(atPath: openClawManifestURL.path)

        return PluginCatalogItem(
            id: name,
            name: name,
            displayName: displayName,
            description: description,
            longDescription: longDescription,
            version: version,
            developerName: developerName,
            category: category,
            capabilities: capabilities,
            keywords: keywords,
            relativePath: relativePath,
            source: source,
            systemIconName: systemIconName,
            iconURL: iconURL,
            repositoryURL: (openClawManifest?.repositoryURL)?.nilIfBlank,
            homepageURL: (openClawManifest?.homepageURL)?.nilIfBlank,
            openClawPluginID: openClawPluginID,
            isOpenClawInstallable: isInstallable
        )
    }

    private static func decodeJSON<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func preferredIconURL(in pluginURL: URL, iconPath: String?) -> URL? {
        if let candidate = iconPath?.nilIfBlank {
            if let url = assetURL(from: candidate, relativeTo: pluginURL) {
                return url
            }
        }

        let assetsURL = pluginURL.appendingPathComponent("assets")
        guard let enumerator = FileManager.default.enumerator(
            at: assetsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let imageFiles = enumerator.compactMap { entry -> URL? in
            guard let file = entry as? URL,
                  ["png", "jpg", "jpeg", "webp", "svg"].contains(file.pathExtension.lowercased()) else {
                return nil
            }
            return file
        }

        return imageFiles.sorted { lhs, rhs in
            imageRank(lhs) < imageRank(rhs)
        }.first
    }

    private static func assetURL(from value: String, relativeTo pluginURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return nil }
        let url = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : pluginURL.appendingPathComponent(trimmed)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func imageRank(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        if name == "icon.png" || name == "logo.png" { return 0 }
        if name.hasSuffix(".png") { return 1 }
        if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") { return 2 }
        if name.hasSuffix(".webp") { return 3 }
        if name.hasSuffix(".svg") { return 4 }
        return 5
    }

    private static func categoryFromOpenClawManifest(
        _ manifest: OpenClawPluginManifest?,
        packageManifest: PackageManifest?
    ) -> String {
        if manifest?.channels.isEmpty == false {
            return "Communication"
        }
        if manifest?.kind == "memory" {
            return "Memory"
        }
        if packageManifest?.openclaw?.channel != nil {
            return "Communication"
        }
        return "Productivity"
    }

    private static func readMarkdownSummary(in pluginURL: URL) -> String? {
        let candidates = ["README.md", "readme.md"]
        for candidate in candidates {
            let url = pluginURL.appendingPathComponent(candidate)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func unscopedPackageName(_ packageName: String?) -> String? {
        guard let packageName = packageName?.nilIfBlank else { return nil }
        if let slashIndex = packageName.lastIndex(of: "/") {
            return String(packageName[packageName.index(after: slashIndex)...])
        }
        return packageName
    }

    private static func displayNameForPlugin(_ name: String) -> String {
        name
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func relativePath(from rootURL: URL, to childURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let childPath = childURL.standardizedFileURL.path
        let prefix = rootPath + "/"
        guard childPath.hasPrefix(prefix) else {
            return childURL.lastPathComponent
        }
        return String(childPath.dropFirst(prefix.count))
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func sourceSortRank(_ source: PluginCatalogSource) -> Int {
        switch source {
        case .recommend:
            return 0
        case .all:
            return 1
        }
    }

    private static func shouldKeep(_ existingEntry: CatalogEntry, over newEntry: CatalogEntry) -> Bool {
        let existingRank = sourceSortRank(existingEntry.item.source)
        let newRank = sourceSortRank(newEntry.item.source)
        if existingRank != newRank {
            return existingRank < newRank
        }

        switch (existingEntry.order, newEntry.order) {
        case let (existing?, new?):
            return existing <= new
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return existingEntry.item.displayName.localizedCaseInsensitiveCompare(newEntry.item.displayName) != .orderedDescending
        }
    }

    private static func sortCatalogItems(_ entries: [CatalogEntry]) -> [PluginCatalogItem] {
        entries.sorted { lhs, rhs in
            if lhs.item.source != rhs.item.source {
                return sourceSortRank(lhs.item.source) < sourceSortRank(rhs.item.source)
            }

            switch (lhs.order, rhs.order) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.item.displayName.localizedCaseInsensitiveCompare(rhs.item.displayName) == .orderedAscending
            }
        }
        .map(\.item)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum PluginUninstallCleanup {
    static var defaultExtensionsRoot: URL {
        URL(fileURLWithPath: NSString("~/.openclaw/extensions").expandingTildeInPath)
    }

    static func globalInstallURL(
        pluginID: String,
        source: String,
        extensionsRoot: URL = defaultExtensionsRoot
    ) -> URL? {
        guard source.hasPrefix("global:") else {
            return nil
        }

        let relativeSource = String(source.dropFirst("global:".count))
        let sourceDirectory = relativeSource
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
            .flatMap(\.nilIfBlank)
        let directoryName = sourceDirectory ?? pluginID.nilIfBlank

        guard let directoryName,
              directoryName != ".",
              directoryName != "..",
              !directoryName.contains("/"),
              !directoryName.contains("\\") else {
            return nil
        }

        let rootURL = extensionsRoot.standardizedFileURL
        let candidateURL = rootURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .standardizedFileURL
        guard candidateURL.path.hasPrefix(rootURL.path + "/") else {
            return nil
        }
        return candidateURL
    }

    @discardableResult
    static func removeGlobalInstallDirectory(
        pluginID: String,
        source: String,
        extensionsRoot: URL = defaultExtensionsRoot,
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard let installURL = globalInstallURL(
            pluginID: pluginID,
            source: source,
            extensionsRoot: extensionsRoot
        ) else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: installURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        guard isDirectory.boolValue else {
            throw CocoaError(.fileReadUnknown)
        }

        try fileManager.removeItem(at: installURL)
        return installURL
    }
}

private struct CatalogEntry {
    let item: PluginCatalogItem
    let order: Int?
}

private struct PluginMarketplaceManifest: Decodable {
    let plugins: [PluginMarketplaceEntry]
}

private struct PluginMarketplaceEntry: Decodable {
    let id: String?
    let name: String?
    let path: String?
    let source: Source?
    let tags: [String]?
    let recommended: Bool?
    let order: Int?

    var catalogSource: PluginCatalogSource {
        if recommended == true {
            return .recommend
        }

        if normalizedTags.contains("recommend") {
            return .recommend
        }

        if normalizedPathComponents.contains("recommend") {
            return .recommend
        }

        return .all
    }

    private var normalizedTags: Set<String> {
        Set((tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    private var normalizedPathComponents: Set<String> {
        let path = self.path ?? source?.path ?? ""
        let components = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map { String($0).lowercased() }
        return Set(components)
    }

    struct Source: Decodable {
        let path: String?
    }
}

private enum PluginCatalogError: LocalizedError {
    case missingPluginsDirectory

    var errorDescription: String? {
        switch self {
        case .missingPluginsDirectory:
            return "Plugin catalog is missing the plugins directory."
        }
    }
}

private struct PackageManifest: Decodable {
    let name: String?
    let version: String?
    let description: String?
    let keywords: [String]?
    let openclaw: OpenClawPackageMetadata?
}

private struct OpenClawPackageMetadata: Decodable {
    let extensions: [String]
    let channel: OpenClawChannelMetadata?
}

private struct OpenClawChannelMetadata: Decodable {}

private struct OpenClawPluginManifest: Decodable {
    let id: String?
    let name: String?
    let displayName: String?
    let description: String?
    let longDescription: String?
    let version: String?
    let developerName: String?
    let category: String?
    let capabilities: [String]
    let keywords: [String]
    let systemIcon: String?
    let icon: String?
    let homepageURL: String?
    let repositoryURL: String?
    let kind: String?
    let channels: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName
        case description
        case longDescription
        case version
        case developerName
        case category
        case capabilities
        case keywords
        case systemIcon
        case icon
        case homepageURL
        case repositoryURL
        case kind
        case channels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        longDescription = try container.decodeIfPresent(String.self, forKey: .longDescription)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        developerName = try container.decodeIfPresent(String.self, forKey: .developerName)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        systemIcon = try container.decodeIfPresent(String.self, forKey: .systemIcon)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        homepageURL = try container.decodeIfPresent(String.self, forKey: .homepageURL)
        repositoryURL = try container.decodeIfPresent(String.self, forKey: .repositoryURL)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? []
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
