import SwiftUI
import AppKit
import MarkdownUI
import UniformTypeIdentifiers

struct PluginDetailPresentationItem: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let documentationMarkdown: String
    let sourceTitle: String
    let catalogItem: PluginCatalogItem?
    let installedPlugin: PluginInfo?
    let systemIconName: String?
    let iconURL: URL?

    @MainActor
    static func fromCatalog(_ item: PluginCatalogItem, installedPlugin: PluginInfo?) -> PluginDetailPresentationItem {
        let display = I18n.pluginDisplay(for: item)
        return PluginDetailPresentationItem(
            id: "catalog-\(item.id)",
            name: item.name,
            displayName: display.displayName,
            description: display.description,
            documentationMarkdown: display.longDescription,
            sourceTitle: item.source.localizedTitle,
            catalogItem: item,
            installedPlugin: installedPlugin,
            systemIconName: item.systemIconName,
            iconURL: item.iconURL
        )
    }

    @MainActor
    static func fromInstalled(_ plugin: PluginInfo, catalogItem: PluginCatalogItem?) -> PluginDetailPresentationItem {
        let section = PluginLibrarySection.section(for: plugin, catalogItem: catalogItem)
        let localizedCatalog = catalogItem.map { I18n.pluginDisplay(for: $0) }
        let description = localizedCatalog?.description.nilIfBlank
            ?? I18n.t("plugins.fallback.installedPlugin")

        return PluginDetailPresentationItem(
            id: "installed-\(plugin.pluginId)",
            name: catalogItem?.name ?? plugin.pluginId,
            displayName: localizedCatalog?.displayName ?? plugin.channel,
            description: description,
            documentationMarkdown: localizedCatalog?.longDescription.nilIfBlank ?? Self.installedPluginMarkdown(plugin),
            sourceTitle: section.localizedTitle,
            catalogItem: catalogItem,
            installedPlugin: plugin,
            systemIconName: catalogItem?.systemIconName,
            iconURL: catalogItem?.iconURL
        )
    }

    @MainActor
    private static func installedPluginMarkdown(_ plugin: PluginInfo) -> String {
        """
        **Plugin ID:** `\(plugin.pluginId)`

        **Status:** \(plugin.enabled ? I18n.t("catalog.status.loaded") : I18n.t("catalog.status.disabled"))

        **Source:** `\(plugin.source.isEmpty ? I18n.t("common.value.unknown") : plugin.source)`

        **Version:** \(plugin.version.isEmpty ? I18n.t("common.value.unknown") : plugin.version)
        """
    }
}

struct PluginsTabView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: PluginsTabModel
    @State private var searchText = ""
    @State private var displayMode: PluginDisplayMode = .recommend
    @State private var showInstallSheet = false
    @State private var selectedPluginDetailItem: PluginDetailPresentationItem?

    private enum PluginDisplayMode: String, CaseIterable {
        case recommend = "Recommend"
        case all = "All"
        case installed = "Installed"

        @MainActor
        var localizedTitle: String {
            switch self {
            case .recommend: return I18n.t("catalog.section.recommend")
            case .all: return I18n.t("catalog.section.all")
            case .installed: return I18n.t("catalog.section.installed")
            }
        }
    }

    private struct InstalledSection: Identifiable {
        let id: PluginLibrarySection
        let title: String
        let items: [PluginInfo]
    }

    private var hasGlobalPlugins: Bool {
        model.plugins.contains { $0.origin == .global }
    }

    private var pluginLookupIndex: PluginLookupIndex {
        PluginLookupIndex(
            catalogItems: model.pluginCatalog,
            installedPlugins: model.plugins
        )
    }

    private var filteredCatalogItems: [PluginCatalogItem] {
        model.pluginCatalog.filter { item in
            let display = I18n.pluginDisplay(for: item)
            return matchesSearch(
                fields: I18n.localizedSearchFields(
                    [display.displayName, display.description, display.longDescription, display.category] + display.capabilities,
                    originals: [item.displayName, item.description, item.longDescription, item.name, item.openClawPluginID, item.category] + item.capabilities + item.keywords
                )
            )
        }
    }

    private var filteredRecommendedCatalogItems: [PluginCatalogItem] {
        filteredCatalogItems.filter(\.isRecommended)
    }

    private var filteredBuiltInCatalogItems: [PluginCatalogItem] {
        filteredCatalogItems.filter { !$0.isRecommended }
    }

    private func filteredInstalledPlugins(using lookup: PluginLookupIndex) -> [PluginInfo] {
        model.plugins.filter { plugin in
            let catalogItem = lookup.catalogItem(for: plugin)
            let display = catalogItem.map { I18n.pluginDisplay(for: $0) }
            return matchesSearch(
                fields: I18n.localizedSearchFields(
                    [
                        display?.displayName ?? plugin.channel,
                        display?.description ?? plugin.pluginId,
                        display?.longDescription ?? "",
                        display?.category ?? ""
                    ],
                    originals: [
                        catalogItem?.displayName ?? plugin.channel,
                        catalogItem?.description ?? plugin.pluginId,
                        catalogItem?.longDescription ?? "",
                        plugin.pluginId,
                        plugin.source,
                        plugin.version,
                        catalogItem?.category ?? ""
                    ]
                )
            )
        }
    }

    private func customInstalledPlugins(from plugins: [PluginInfo], using lookup: PluginLookupIndex) -> [PluginInfo] {
        plugins.filter { lookup.catalogItem(for: $0) == nil }
    }

    private func installedSections(from plugins: [PluginInfo], using lookup: PluginLookupIndex) -> [InstalledSection] {
        PluginLibrarySection.allCases.compactMap { section in
            let items = plugins.filter {
                PluginLibrarySection.section(for: $0, catalogItem: lookup.catalogItem(for: $0)) == section
            }
            guard !items.isEmpty else { return nil }
            return InstalledSection(id: section, title: section.localizedTitle, items: items)
        }
    }

    init(
        openclawService: OpenClawService,
        notifySuccess: @escaping (String) -> Void = { _ in },
        notifyError: @escaping (String) -> Void = { _ in }
    ) {
        _model = StateObject(
            wrappedValue: PluginsTabModel(
                openclawService: openclawService,
                notifySuccess: notifySuccess,
                notifyError: notifyError
            )
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchAndActions
                    modePicker
                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
            }

            if let selectedPluginDetailItem {
                pluginDetailOverlay(for: selectedPluginDetailItem)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await model.loadPluginMarket()
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallPluginSheet(
                model: model,
                isPresented: $showInstallSheet
            )
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: selectedPluginDetailItem?.id)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(I18n.t("plugins.title"))
                    .font(.system(size: 24, weight: .semibold))
                Text(I18n.t("plugins.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.pluginCatalog.isEmpty || !model.plugins.isEmpty {
                Text(I18n.format("catalog.count.installed", Int64(model.plugins.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchAndActions: some View {
        HStack(spacing: 10) {
            UnifiedSearchField(placeholder: I18n.t("plugins.search.placeholder"), text: $searchText)

            if hasGlobalPlugins {
                Button {
                    Task { await model.updateAllPlugins() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingPlugins || model.isPerformingAction)
                .help(I18n.t("plugins.help.updateInstalled"))
            }

            Button {
                showInstallSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(model.isPerformingAction)
            .help(I18n.t("plugins.help.installCustom"))

            Button {
                Task { await model.loadPluginMarket(forceSync: true) }
            } label: {
                if model.isLoadingPluginCatalog {
                    Text("...")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingPluginCatalog || model.isLoadingPlugins)
            .help(I18n.t("plugins.help.refresh"))
        }
    }

    private var modePicker: some View {
        Picker("", selection: $displayMode) {
            ForEach(PluginDisplayMode.allCases, id: \.self) { mode in
                Text(mode.localizedTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 284)
    }

    @ViewBuilder
    private var content: some View {
        let lookup = pluginLookupIndex
        let installedPlugins = filteredInstalledPlugins(using: lookup)
        let customPlugins = customInstalledPlugins(from: installedPlugins, using: lookup)
        let sections = installedSections(from: installedPlugins, using: lookup)

        switch displayMode {
        case .recommend:
            recommendedPluginsContent(lookup: lookup)
        case .all:
            allPluginsContent(customPlugins: customPlugins, lookup: lookup)
        case .installed:
            installedPluginsContent(sections: sections, lookup: lookup)
        }
    }

    @ViewBuilder
    private func recommendedPluginsContent(lookup: PluginLookupIndex) -> some View {
        if model.isLoadingPluginCatalog && model.pluginCatalog.isEmpty {
            PluginLoadingStateView(text: I18n.t("plugins.loading.catalog"))
        } else if let error = model.pluginCatalogError, model.pluginCatalog.isEmpty {
            EmptyPluginStateView(
                systemImage: "exclamationmark.triangle",
                title: I18n.t("plugins.empty.catalogLoadFailed"),
                detail: error
            )
        } else if filteredRecommendedCatalogItems.isEmpty {
            EmptyPluginStateView(
                systemImage: "puzzlepiece",
                title: model.pluginCatalog.isEmpty ? I18n.t("plugins.empty.noRecommended") : I18n.t("plugins.empty.noMatchingRecommended"),
                detail: nil
            )
        } else {
            catalogSection(
                title: PluginLibrarySection.recommend.localizedTitle,
                items: filteredRecommendedCatalogItems,
                lookup: lookup
            )
        }
    }

    @ViewBuilder
    private func allPluginsContent(customPlugins: [PluginInfo], lookup: PluginLookupIndex) -> some View {
        if model.isLoadingPluginCatalog && model.pluginCatalog.isEmpty {
            PluginLoadingStateView(text: I18n.t("plugins.loading.catalog"))
        } else if let error = model.pluginCatalogError,
                  model.pluginCatalog.isEmpty,
                  customPlugins.isEmpty {
            EmptyPluginStateView(
                systemImage: "exclamationmark.triangle",
                title: I18n.t("plugins.empty.catalogLoadFailed"),
                detail: error
            )
        } else if filteredCatalogItems.isEmpty && customPlugins.isEmpty {
            EmptyPluginStateView(
                systemImage: "puzzlepiece",
                title: model.pluginCatalog.isEmpty && model.plugins.isEmpty ? I18n.t("plugins.empty.noPlugins") : I18n.t("plugins.empty.noMatchingPlugins"),
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                if !filteredRecommendedCatalogItems.isEmpty {
                    catalogSection(
                        title: PluginLibrarySection.recommend.localizedTitle,
                        items: filteredRecommendedCatalogItems,
                        lookup: lookup
                    )
                }

                if !filteredBuiltInCatalogItems.isEmpty {
                    catalogSection(
                        title: PluginLibrarySection.builtIn.localizedTitle,
                        items: filteredBuiltInCatalogItems,
                        lookup: lookup
                    )
                }

                if !customPlugins.isEmpty {
                    installedSection(
                        title: PluginLibrarySection.custom.localizedTitle,
                        items: customPlugins,
                        lookup: lookup
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func installedPluginsContent(sections: [InstalledSection], lookup: PluginLookupIndex) -> some View {
        if model.isLoadingPlugins && model.plugins.isEmpty {
            PluginLoadingStateView(text: I18n.t("plugins.loading.installed"))
        } else if sections.isEmpty {
            EmptyPluginStateView(
                systemImage: "checkmark.circle",
                title: model.plugins.isEmpty ? I18n.t("plugins.empty.noInstalled") : I18n.t("plugins.empty.noMatchingInstalled"),
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(sections) { section in
                    installedSection(title: section.title, items: section.items, lookup: lookup)
                }
            }
        }
    }

    private func catalogSection(title: String, items: [PluginCatalogItem], lookup: PluginLookupIndex) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PluginSectionHeader(title: title, count: items.count)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let installedPlugin = lookup.installedPlugin(for: item)

                    CatalogPluginListRow(
                        item: item,
                        installedPlugin: installedPlugin,
                        isInstalling: model.installingCatalogPluginName == item.name,
                        onInstall: {
                            Task { await model.installCatalogPlugin(item) }
                        },
                        onOpen: {
                            presentPluginDetail(PluginDetailPresentationItem.fromCatalog(item, installedPlugin: installedPlugin))
                        }
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func installedSection(title: String, items: [PluginInfo], lookup: PluginLookupIndex) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PluginSectionHeader(title: title, count: items.count)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, plugin in
                    let catalogItem = lookup.catalogItem(for: plugin)

                    InstalledPluginListRow(
                        plugin: plugin,
                        catalogItem: catalogItem,
                        onOpen: {
                            presentPluginDetail(PluginDetailPresentationItem.fromInstalled(plugin, catalogItem: catalogItem))
                        }
                    )

                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func matchesSearch(fields: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = fields
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
    }

    private func presentPluginDetail(_ item: PluginDetailPresentationItem) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            selectedPluginDetailItem = item
        }
    }

    private func dismissPluginCatalogDetail() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            selectedPluginDetailItem = nil
        }
    }

    private func resolvedPluginDetailInstalledPlugin(for item: PluginDetailPresentationItem) -> PluginInfo? {
        let lookup = pluginLookupIndex
        if let catalogItem = item.catalogItem {
            return lookup.installedPlugin(for: catalogItem)
        }
        if let installedPlugin = item.installedPlugin {
            return lookup.installedPluginsByID[PluginLookupIndex.lookupKey(installedPlugin.pluginId)]
                ?? lookup.installedPluginsByChannel[PluginLookupIndex.lookupKey(installedPlugin.channel)]
                ?? installedPlugin
        }
        return nil
    }

    private func pluginDetailOverlay(for item: PluginDetailPresentationItem) -> some View {
        let installedPlugin = resolvedPluginDetailInstalledPlugin(for: item)
        let isDark = colorScheme == .dark

        return GeometryReader { _ in
            ZStack {
                Color.black
                    .opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if model.installingCatalogPluginName == nil && !model.isPerformingAction {
                            dismissPluginCatalogDetail()
                        }
                    }

                PluginCatalogDetailSheet(
                    item: item,
                    installedPlugin: installedPlugin,
                    isInstalling: item.catalogItem.map { model.installingCatalogPluginName == $0.name } ?? false,
                    isPerformingAction: model.isPerformingAction,
                    onInstall: {
                        if let catalogItem = item.catalogItem {
                            Task { await model.installCatalogPlugin(catalogItem) }
                        }
                    },
                    onEnable: {
                        if let installedPlugin {
                            Task { await model.enablePlugin(installedPlugin) }
                        }
                    },
                    onDisable: {
                        if let installedPlugin {
                            Task { await model.disablePlugin(installedPlugin) }
                        }
                    },
                    onUpdate: {
                        if let installedPlugin {
                            Task { await model.updatePlugin(installedPlugin) }
                        }
                    },
                    onUninstall: {
                        if let installedPlugin {
                            Task { await model.uninstallPlugin(installedPlugin) }
                        }
                    },
                    onClose: dismissPluginCatalogDetail
                )
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 28, x: 0, y: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.16 : 0.08), lineWidth: 1)
                )
                .padding(28)
                .onTapGesture {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
        ))
    }
}

private struct PluginLookupIndex {
    let catalogItemsByName: [String: PluginCatalogItem]
    let catalogItemsByPluginID: [String: PluginCatalogItem]
    let installedPluginsByID: [String: PluginInfo]
    let installedPluginsByChannel: [String: PluginInfo]

    init(catalogItems: [PluginCatalogItem], installedPlugins: [PluginInfo]) {
        catalogItemsByName = Self.firstCatalogItems(catalogItems) { $0.name }
        catalogItemsByPluginID = Self.firstCatalogItems(catalogItems) { $0.openClawPluginID }
        installedPluginsByID = Self.firstInstalledPlugins(installedPlugins) { $0.pluginId }
        installedPluginsByChannel = Self.firstInstalledPlugins(installedPlugins) { $0.channel }
    }

    func installedPlugin(for item: PluginCatalogItem) -> PluginInfo? {
        installedPluginsByID[Self.lookupKey(item.openClawPluginID)]
            ?? installedPluginsByID[Self.lookupKey(item.name)]
            ?? installedPluginsByChannel[Self.lookupKey(item.name)]
    }

    func catalogItem(for plugin: PluginInfo) -> PluginCatalogItem? {
        catalogItemsByPluginID[Self.lookupKey(plugin.pluginId)]
            ?? catalogItemsByName[Self.lookupKey(plugin.pluginId)]
            ?? catalogItemsByName[Self.lookupKey(plugin.channel)]
    }

    private static func firstCatalogItems(
        _ items: [PluginCatalogItem],
        key: (PluginCatalogItem) -> String
    ) -> [String: PluginCatalogItem] {
        var result: [String: PluginCatalogItem] = [:]
        for item in items where result[lookupKey(key(item))] == nil {
            result[lookupKey(key(item))] = item
        }
        return result
    }

    private static func firstInstalledPlugins(
        _ plugins: [PluginInfo],
        key: (PluginInfo) -> String
    ) -> [String: PluginInfo] {
        var result: [String: PluginInfo] = [:]
        for plugin in plugins where result[lookupKey(key(plugin))] == nil {
            result[lookupKey(key(plugin))] = plugin
        }
        return result
    }

    static func lookupKey(_ value: String) -> String {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let slashIndex = lower.lastIndex(of: "/") else { return lower }
        return String(lower[lower.index(after: slashIndex)...])
    }
}

private enum PluginLibrarySection: CaseIterable, Identifiable {
    case recommend
    case builtIn
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .recommend:
            return "Recommend"
        case .builtIn:
            return "Built-in"
        case .custom:
            return "Custom"
        }
    }

    @MainActor
    var localizedTitle: String {
        switch self {
        case .recommend:
            return I18n.t("catalog.section.recommend")
        case .builtIn:
            return I18n.t("catalog.section.builtIn")
        case .custom:
            return I18n.t("catalog.section.custom")
        }
    }

    static func section(for plugin: PluginInfo, catalogItem: PluginCatalogItem?) -> PluginLibrarySection {
        guard let catalogItem else { return .custom }
        return catalogItem.isRecommended ? .recommend : .builtIn
    }
}

private struct PluginSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.10))
                .clipShape(Capsule())
        }
    }
}

private struct CatalogPluginListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let item: PluginCatalogItem
    let installedPlugin: PluginInfo?
    let isInstalling: Bool
    let onInstall: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let display = I18n.pluginDisplay(for: item)

        HStack(spacing: 14) {
            PluginCatalogIcon(systemIconName: item.systemIconName, iconURL: item.iconURL, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(display.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(display.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if let installedPlugin {
                PluginStatusMark(plugin: installedPlugin)
            } else if !item.isOpenClawInstallable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .help(I18n.t("catalog.status.unavailable"))
            } else {
                Button(action: onInstall) {
                    if isInstalling {
                        Text(I18n.t("catalog.action.installing"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 74, height: 28)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PluginInstallPalette.amber)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(PluginInstallPalette.iconBackground(colorScheme: colorScheme, isHovered: isHovered))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(PluginInstallPalette.iconBorder(isHovered: isHovered), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isInstalling)
                .help(I18n.t("catalog.action.install"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(isHovered ? 0.075 : 0)
            : Color.black.opacity(isHovered ? 0.065 : 0)
    }
}

private struct InstalledPluginListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let plugin: PluginInfo
    let catalogItem: PluginCatalogItem?
    let onOpen: () -> Void

    var body: some View {
        let display = catalogItem.map { I18n.pluginDisplay(for: $0) }

        HStack(spacing: 14) {
            PluginCatalogIcon(systemIconName: catalogItem?.systemIconName, iconURL: catalogItem?.iconURL, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(display?.displayName ?? plugin.channel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(display?.description.nilIfBlank ?? plugin.pluginId)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            PluginStatusMark(plugin: plugin)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(isHovered ? 0.075 : 0)
            : Color.black.opacity(isHovered ? 0.065 : 0)
    }
}

private struct PluginStatusMark: View {
    let plugin: PluginInfo

    var body: some View {
        Image(systemName: plugin.enabled ? "checkmark" : "minus.circle.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(plugin.enabled ? .primary : .secondary)
            .frame(width: 28, height: 28)
            .help(plugin.enabled ? I18n.t("catalog.status.loaded") : I18n.t("catalog.status.disabled"))
    }
}

private struct PluginCatalogIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    private let defaultSystemIconName = "powerplug.portrait"

    let systemIconName: String?
    let iconURL: URL?
    let size: CGFloat

    var body: some View {
        let customImage = resolvedCustomImage
        let isUsingSystemIcon = systemIconName?.nilIfBlank != nil
        let isUsingDefaultIcon = !isUsingSystemIcon && customImage == nil

        Group {
            if let systemIconName = systemIconName?.nilIfBlank {
                Image(systemName: systemIconName)
                    .font(.system(size: size * 0.72, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            } else if let image = customImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: defaultSystemIconName)
                    .font(.system(size: size * 0.72, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .padding(6)
        .background(isUsingDefaultIcon ? pluginDefaultIconBackground : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resolvedCustomImage: NSImage? {
        guard let iconURL else { return nil }
        return PluginIconImageCache.shared.image(for: iconURL)
    }

    private var pluginDefaultIconBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.32)
            : Color(NSColor.controlBackgroundColor)
    }
}

private final class PluginIconImageCache {
    static let shared = PluginIconImageCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {}

    func image(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct PluginLoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }
}

private struct EmptyPluginStateView: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }
}

struct PluginCatalogDetailSheet: View {
    let item: PluginDetailPresentationItem
    let installedPlugin: PluginInfo?
    let isInstalling: Bool
    let isPerformingAction: Bool
    let onInstall: () -> Void
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onClose: () -> Void

    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        PluginDetailChip(title: item.sourceTitle)
                        PluginDetailChip(title: installedPlugin == nil ? I18n.t("catalog.status.notInstalled") : I18n.t("catalog.status.installed"))
                        if let installedPlugin {
                            PluginDetailChip(title: installedPlugin.enabled ? I18n.t("catalog.status.loaded") : I18n.t("catalog.status.disabled"))
                        }
                        if let catalogItem = item.catalogItem, !catalogItem.version.isEmpty {
                            PluginDetailChip(title: "v\(catalogItem.version)")
                        }
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    actionControls

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(I18n.t("catalog.action.close"))
                }
            }
            .padding(.bottom, 16)

            Text(item.description)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.bottom, 20)

            Text(I18n.t("catalog.detail.description"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ScrollView {
                Markdown(detailMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
            }
            .frame(height: 344)
            .background(Color(NSColor.textBackgroundColor).opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(28)
        .frame(width: 640)
        .alert(I18n.t("plugins.alert.uninstallTitle"), isPresented: $showUninstallConfirm) {
            Button(I18n.t("catalog.action.cancel"), role: .cancel) {}
            Button(I18n.t("catalog.action.uninstall"), role: .destructive) {
                onUninstall()
            }
        } message: {
            Text(I18n.format("plugins.alert.uninstallMessage", installedPlugin?.channel ?? item.displayName))
        }
    }

    private var detailMarkdown: String {
        let lines = item.documentationMarkdown.components(separatedBy: .newlines)
        var firstContentIndex = 0
        var hasTrimmedHeading = false

        while firstContentIndex < lines.count {
            let trimmed = lines[firstContentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                firstContentIndex += 1
                continue
            }
            if trimmed.hasPrefix("#") {
                firstContentIndex += 1
                hasTrimmedHeading = true
                continue
            }
            break
        }

        let body = lines
            .dropFirst(firstContentIndex)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return body.isEmpty && hasTrimmedHeading ? item.description : (body.isEmpty ? item.description : body)
    }

    @ViewBuilder
    private var actionControls: some View {
        if installedPlugin == nil {
            Button(action: onInstall) {
                if isInstalling {
                    Text(I18n.t("catalog.action.installing"))
                        .frame(width: 92, height: 30)
                } else if item.catalogItem?.isOpenClawInstallable == false {
                    Text(I18n.t("catalog.status.unavailable"))
                        .frame(width: 92, height: 30)
                } else {
                    Text(I18n.t("catalog.action.install"))
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(PluginPillButtonStyle(tone: .install, isDisabled: isInstalling || item.catalogItem?.isOpenClawInstallable == false))
            .disabled(isInstalling || item.catalogItem?.isOpenClawInstallable == false)
        } else if let installedPlugin {
            if installedPlugin.origin == .global {
                Button(action: onUpdate) {
                    Text(I18n.t("catalog.action.update"))
                        .frame(width: 76, height: 30)
                }
                .buttonStyle(PluginPillButtonStyle(tone: .neutral, isDisabled: isPerformingAction))
                .disabled(isPerformingAction)

                Button(role: .destructive) {
                    showUninstallConfirm = true
                } label: {
                    Text(I18n.t("catalog.action.uninstall"))
                        .frame(width: 86, height: 30)
                }
                .buttonStyle(PluginPillButtonStyle(tone: .destructive, isDisabled: isPerformingAction))
                .disabled(isPerformingAction)
            }

            Button(action: installedPlugin.enabled ? onDisable : onEnable) {
                Text(installedPlugin.enabled ? I18n.t("catalog.action.disable") : I18n.t("catalog.action.enable"))
                    .frame(width: 82, height: 30)
            }
            .buttonStyle(PluginPillButtonStyle(tone: installedPlugin.enabled ? .neutral : .install, isDisabled: isPerformingAction))
            .disabled(isPerformingAction)
        }
    }
}

private struct PluginDetailChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private enum PluginInstallPalette {
    static let amber = Color(red: 0.82, green: 0.50, blue: 0.12)

    static func iconBackground(colorScheme: ColorScheme, isHovered: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.13 : 0.08)
        }
        return amber.opacity(isHovered ? 0.16 : 0.11)
    }

    static func iconBorder(isHovered: Bool) -> Color {
        amber.opacity(isHovered ? 0.42 : 0.24)
    }
}

private struct PluginPillButtonStyle: ButtonStyle {
    enum Tone {
        case install
        case neutral
        case destructive
    }

    @Environment(\.colorScheme) private var colorScheme

    let tone: Tone
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.58 : 1)
    }

    private var foregroundColor: Color {
        switch tone {
        case .install:
            return colorScheme == .dark ? Color(red: 0.98, green: 0.78, blue: 0.45) : Color(red: 0.55, green: 0.32, blue: 0.04)
        case .neutral:
            return .primary
        case .destructive:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .install:
            return PluginInstallPalette.amber.opacity(colorScheme == .dark ? 0.20 : 0.13)
        case .neutral:
            return Color.secondary.opacity(colorScheme == .dark ? 0.15 : 0.10)
        case .destructive:
            return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .install:
            return PluginInstallPalette.amber.opacity(colorScheme == .dark ? 0.38 : 0.28)
        case .neutral:
            return Color.primary.opacity(0.10)
        case .destructive:
            return Color.red.opacity(0.24)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Install Plugin Sheet

enum InstallMethod: String, CaseIterable {
    case npm = "npm"
    case file = "File"
    case link = "Link"

    @MainActor
    var localizedTitle: String {
        switch self {
        case .npm:
            return I18n.t("plugins.install.method.npm")
        case .file:
            return I18n.t("plugins.install.method.file")
        case .link:
            return I18n.t("plugins.install.method.link")
        }
    }
}

enum PluginPreset: String, CaseIterable {
    case custom = "Custom"
    case dingtalk = "DingTalk"
    case weixin = "Weixin"

    @MainActor
    var localizedTitle: String {
        switch self {
        case .custom:
            return I18n.t("plugins.install.preset.custom")
        case .dingtalk:
            return "DingTalk"
        case .weixin:
            return "Weixin"
        }
    }

    var packageName: String? {
        switch self {
        case .custom: return nil
        case .dingtalk: return "@openclaw-china/dingtalk"
        case .weixin: return "@tencent-weixin/openclaw-weixin-cli@latest"
        }
    }

    /// Keywords to match against installed plugin's pluginId, channel name, or source
    var matchKeywords: [String] {
        switch self {
        case .custom: return []
        case .dingtalk: return ["dingtalk", "@openclaw-china/dingtalk"]
        case .weixin: return ["weixin", "openclaw-weixin", "@tencent-weixin/openclaw-weixin"]
        }
    }
}

struct InstallPluginSheet: View {
    @ObservedObject var model: PluginsTabModel
    @Binding var isPresented: Bool

    @State private var installMethod: InstallMethod = .npm
    @State private var selectedPreset: PluginPreset = .custom
    @State private var packageName = ""
    @State private var filePath = ""
    @State private var linkSpec = ""
    @State private var isInstalling = false

    private var currentSpec: String {
        switch installMethod {
        case .npm: return packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .file: return filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link: return linkSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var isPresetAlreadyInstalled: Bool {
        guard installMethod == .npm else { return false }
        guard selectedPreset != .custom else { return false }
        let keywords = selectedPreset.matchKeywords
        return model.plugins.contains { plugin in
            let id = plugin.pluginId.lowercased()
            let name = plugin.channel.lowercased()
            let source = plugin.source.lowercased()
            return keywords.contains { keyword in
                id.contains(keyword) || name.contains(keyword) || source.contains(keyword)
            }
        }
    }

    private var canInstall: Bool {
        if isPresetAlreadyInstalled { return false }
        return !currentSpec.isEmpty && !isInstalling && !model.isPerformingAction
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(I18n.t("plugins.install.title"))
                    .font(.headline)
                Spacer()
                Button(I18n.t("catalog.action.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Install method picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text(I18n.t("plugins.install.method"))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $installMethod) {
                            ForEach(InstallMethod.allCases, id: \.self) { method in
                                Text(method.localizedTitle).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Method-specific input
                    switch installMethod {
                    case .npm:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(I18n.t("plugins.install.quickSelect"))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Picker("", selection: $selectedPreset) {
                                ForEach(PluginPreset.allCases, id: \.self) { preset in
                                    Text(preset.localizedTitle).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedPreset) { newValue in
                                if let name = newValue.packageName {
                                    packageName = name
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(I18n.t("plugins.install.packageName"))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(I18n.t("plugins.install.packagePlaceholder"), text: $packageName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(selectedPreset == .weixin)

                            if isPresetAlreadyInstalled {
                                Label(I18n.format("plugins.install.presetAlreadyInstalled", selectedPreset.localizedTitle), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                    case .file:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(I18n.t("plugins.install.pluginFile"))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField(I18n.t("plugins.install.filePlaceholder"), text: $filePath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button(I18n.t("plugins.install.browse")) {
                                    browseFile()
                                }
                            }

                            Text(I18n.t("plugins.install.supportedFileTypes"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    case .link:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(I18n.t("plugins.install.pluginLink"))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(I18n.t("plugins.install.linkPlaceholder"), text: $linkSpec)
                                .textFieldStyle(.roundedBorder)

                            Text(I18n.t("plugins.install.linkHelp"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(I18n.t("plugins.install.installing"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(I18n.t("catalog.action.install")) {
                    performInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            }
            .padding(16)
        }
        .frame(width: 480, height: 320)
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "ts")!,
            .init(filenameExtension: "js")!,
            .init(filenameExtension: "zip")!,
            .init(filenameExtension: "tgz")!,
            .init(filenameExtension: "gz")!
        ].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
        }
    }

    private func performInstall() {
        isInstalling = true
        let spec = currentSpec
        let isWeixin = installMethod == .npm && selectedPreset == .weixin
        Task {
            if isWeixin {
                await model.installWeixinPlugin()
            } else {
                await model.installPlugin(spec: spec)
            }
            await MainActor.run {
                isInstalling = false
                isPresented = false
            }
        }
    }
}

private struct PluginsTabPreviewWrapper: View {
    var body: some View {
        PluginsTabView(
            openclawService: OpenClawService(
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            )
        )
    }
}

#Preview {
    PluginsTabPreviewWrapper()
        .frame(width: 700, height: 600)
}
