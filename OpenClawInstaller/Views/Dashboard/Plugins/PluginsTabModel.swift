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
        let display = I18n.pluginDisplay(for: item)
        guard item.isOpenClawInstallable else {
            notifyError(I18n.format("plugins.toast.notInstallable", display.displayName))
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
            notifySuccess(I18n.format("plugins.toast.installed", display.displayName))
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError(I18n.format("plugins.toast.installFailed", display.displayName, trimmed?.isEmpty == false ? trimmed! : I18n.t("common.error.unknown")))
        }
    }

    func enablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins enable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            notifyError(I18n.format("plugins.toast.enableFailed", plugin.channel, output))
        } else {
            notifySuccess(I18n.format("plugins.toast.enabled", plugin.channel))
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func disablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins disable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            notifyError(I18n.format("plugins.toast.disableFailed", plugin.channel, output))
        } else {
            notifySuccess(I18n.format("plugins.toast.disabled", plugin.channel))
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
            notifyError(I18n.format("plugins.toast.customInstallFailed", output))
        } else {
            notifySuccess(I18n.t("plugins.toast.customInstalled"))
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
            notifyError(I18n.format("plugins.toast.weixinInstallFailed", output))
        } else {
            notifySuccess(I18n.t("plugins.toast.weixinInstalled"))
        }
        await loadPlugins()
        isPerformingAction = false
    }

    func uninstallPlugin(_ plugin: PluginInfo) async {
        guard plugin.origin == .global else {
            notifyError(I18n.t("plugins.toast.builtInUninstall"))
            return
        }
        isPerformingAction = true
        defer { isPerformingAction = false }

        let output = await openclawService.runCommand(
            "openclaw plugins uninstall \(Self.shellQuote(plugin.pluginId)) --force 2>&1 && echo __OPENCLAW_PLUGIN_UNINSTALL_OK__"
        )
        guard output?.contains("__OPENCLAW_PLUGIN_UNINSTALL_OK__") == true else {
            let detail = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            notifyError(I18n.format("plugins.toast.uninstallFailed", plugin.channel, detail?.isEmpty == false ? detail! : I18n.t("common.error.unknown")))
            await loadPlugins()
            return
        }

        do {
            _ = try PluginUninstallCleanup.removeGlobalInstallDirectory(
                pluginID: plugin.pluginId,
                source: plugin.source
            )
            notifySuccess(I18n.format("plugins.toast.uninstalled", plugin.channel))
        } catch {
            notifyError(I18n.format("plugins.toast.removeFilesFailed", plugin.channel, error.localizedDescription))
        }

        await loadPlugins()
    }

    func updatePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update \(plugin.pluginId) 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            notifyError(I18n.format("plugins.toast.updateFailed", plugin.channel, output))
        } else {
            notifySuccess(I18n.format("plugins.toast.updated", plugin.channel))
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
            notifyError(I18n.format("plugins.toast.updateAllFailed", output))
        } else {
            notifySuccess(I18n.t("plugins.toast.allUpdated"))
        }
        await loadPlugins()
        isPerformingAction = false
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
