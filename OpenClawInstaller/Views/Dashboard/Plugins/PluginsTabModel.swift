import Foundation
import Combine

@MainActor
final class PluginsTabModel: ObservableObject {
    @Published var plugins: [PluginInfo] = []
    @Published var isLoadingPlugins = false
    @Published var pluginCatalog: [PluginCatalogItem] = []
    @Published var isLoadingPluginCatalog = false
    @Published var installingCatalogPluginName: String?
    @Published var pluginCatalogError: String?
    @Published var isPerformingAction = false

    private let openclawService: OpenClawService
    private let notifySuccess: (String) -> Void
    private let notifyError: (String) -> Void
    private var hasLoadedPluginCatalog = false

    init(
        openclawService: OpenClawService,
        notifySuccess: @escaping (String) -> Void,
        notifyError: @escaping (String) -> Void
    ) {
        self.openclawService = openclawService
        self.notifySuccess = notifySuccess
        self.notifyError = notifyError
    }

    func loadPlugins() async {
        isLoadingPlugins = true
        let output = await openclawService.runCommand(
            "openclaw plugins list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        plugins = DashboardViewModel.parsePluginList(output: output)
            .sorted { a, b in
                if a.enabled != b.enabled { return a.enabled }
                return a.channel.localizedCaseInsensitiveCompare(b.channel) == .orderedAscending
            }
        isLoadingPlugins = false
    }

    func loadPluginMarket(forceSync: Bool = false) async {
        if hasLoadedPluginCatalog && !forceSync {
            await loadPlugins()
            return
        }

        guard !isLoadingPluginCatalog else { return }

        isLoadingPluginCatalog = true
        pluginCatalogError = nil

        let cacheGitURL = PluginCatalogService.defaultCacheURL.appendingPathComponent(".git")
        let shouldSync = forceSync || !FileManager.default.fileExists(atPath: cacheGitURL.path)
        let syncOutput: String?
        if shouldSync {
            syncOutput = await openclawService.runCommand(
                "\(PluginCatalogService.syncCommand()) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 120
            )
        } else {
            syncOutput = nil
        }

        do {
            pluginCatalog = try PluginCatalogService.parseCatalog(rootURL: PluginCatalogService.defaultCacheURL)
            hasLoadedPluginCatalog = true
        } catch {
            let detail = syncOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
            pluginCatalogError = detail?.isEmpty == false ? detail : error.localizedDescription
            pluginCatalog = []
            hasLoadedPluginCatalog = false
        }

        await loadPlugins()
        isLoadingPluginCatalog = false
    }

    func installCatalogPlugin(_ item: PluginCatalogItem) async {
        guard installingCatalogPluginName == nil else { return }
        guard item.isOpenClawInstallable else {
            notifyError("\(item.displayName) is not installable by OpenClaw.")
            return
        }

        installingCatalogPluginName = item.name
        let command = PluginCatalogService.installCommand(for: item)
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_PLUGIN_INSTALL_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 180
        )
        installingCatalogPluginName = nil

        if output?.contains("__OPENCLAW_PLUGIN_INSTALL_OK__") == true {
            await loadPlugins()
            notifySuccess("Installed plugin \(item.displayName)")
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError("Failed to install \(item.displayName): \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
        }
    }

    func enablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins enable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to enable \(plugin.channel): \(output)")
        } else {
            notifySuccess("\(plugin.channel) enabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func disablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins disable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to disable \(plugin.channel): \(output)")
        } else {
            notifySuccess("\(plugin.channel) disabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func installPlugin(spec: String, link: Bool = false) async {
        isPerformingAction = true
        let escapedSpec = spec.replacingOccurrences(of: "'", with: "'\\''")
        var cmd = "openclaw plugins install '\(escapedSpec)'"
        if link {
            cmd += " --link"
        }
        cmd += " 2>&1"
        let output = await openclawService.runCommand(cmd, timeout: 120)
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to install plugin: \(output)")
        } else {
            notifySuccess("Plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func installWeixinPlugin() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "npx -y @tencent-weixin/openclaw-weixin-cli@latest install 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to install Weixin plugin: \(output)")
        } else {
            notifySuccess("Weixin plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func uninstallPlugin(_ plugin: PluginInfo) async {
        guard plugin.origin == .global else {
            notifyError("Built-in plugins cannot be uninstalled. Use Disable instead.")
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        let output = await openclawService.runCommand(
            "openclaw plugins uninstall \(Self.shellQuote(plugin.pluginId)) --force 2>&1 && echo __OPENCLAW_PLUGIN_UNINSTALL_OK__"
        )
        guard output?.contains("__OPENCLAW_PLUGIN_UNINSTALL_OK__") == true else {
            let detail = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError("Failed to uninstall \(plugin.channel): \(detail?.isEmpty == false ? detail! : "unknown error")")
            await loadPlugins()
            return
        }

        do {
            _ = try PluginUninstallCleanup.removeGlobalInstallDirectory(
                pluginID: plugin.pluginId,
                source: plugin.source
            )
            notifySuccess("\(plugin.channel) uninstalled")
        } catch {
            notifyError("Failed to remove \(plugin.channel) files: \(error.localizedDescription)")
        }

        await loadPlugins()
    }

    func updatePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update \(plugin.pluginId) 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to update \(plugin.channel): \(output)")
        } else {
            notifySuccess("\(plugin.channel) updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func updateAllPlugins() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update --all 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            notifyError("Failed to update plugins: \(output)")
        } else {
            notifySuccess("All plugins updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
