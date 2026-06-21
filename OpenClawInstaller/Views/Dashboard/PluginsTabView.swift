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
    let iconURL: URL?

    static func fromCatalog(_ item: PluginCatalogItem, installedPlugin: PluginInfo?) -> PluginDetailPresentationItem {
        PluginDetailPresentationItem(
            id: "catalog-\(item.id)",
            name: item.name,
            displayName: item.displayName,
            description: item.description,
            documentationMarkdown: item.longDescription,
            sourceTitle: item.source.title,
            catalogItem: item,
            installedPlugin: installedPlugin,
            iconURL: item.iconURL
        )
    }

    static func fromInstalled(_ plugin: PluginInfo, catalogItem: PluginCatalogItem?) -> PluginDetailPresentationItem {
        let section = PluginLibrarySection.section(for: plugin, catalogItem: catalogItem)
        let description = catalogItem?.description.nilIfBlank
            ?? "Installed OpenClaw plugin"

        return PluginDetailPresentationItem(
            id: "installed-\(plugin.pluginId)",
            name: catalogItem?.name ?? plugin.pluginId,
            displayName: catalogItem?.displayName ?? plugin.channel,
            description: description,
            documentationMarkdown: catalogItem?.longDescription.nilIfBlank ?? Self.installedPluginMarkdown(plugin),
            sourceTitle: section.title,
            catalogItem: catalogItem,
            installedPlugin: plugin,
            iconURL: catalogItem?.iconURL
        )
    }

    private static func installedPluginMarkdown(_ plugin: PluginInfo) -> String {
        """
        **Plugin ID:** `\(plugin.pluginId)`

        **Status:** \(plugin.enabled ? "Loaded" : "Disabled")

        **Source:** `\(plugin.source.isEmpty ? "Unknown" : plugin.source)`

        **Version:** \(plugin.version.isEmpty ? "Unknown" : plugin.version)
        """
    }
}

struct PluginsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenPluginDetail: (PluginDetailPresentationItem) -> Void
    @State private var searchText = ""
    @State private var displayMode: PluginDisplayMode = .recommend
    @State private var showInstallSheet = false

    private enum PluginDisplayMode: String, CaseIterable {
        case recommend = "Recommend"
        case all = "All"
        case installed = "Installed"
    }

    private struct InstalledSection: Identifiable {
        let id: PluginLibrarySection
        let title: String
        let items: [PluginInfo]
    }

    private var hasGlobalPlugins: Bool {
        viewModel.plugins.contains { $0.origin == .global }
    }

    private var catalogItemsByName: [String: PluginCatalogItem] {
        firstCatalogItems { $0.name }
    }

    private var catalogItemsByPluginID: [String: PluginCatalogItem] {
        firstCatalogItems { $0.openClawPluginID }
    }

    private var installedPluginsByID: [String: PluginInfo] {
        firstInstalledPlugins { $0.pluginId }
    }

    private var installedPluginsByChannel: [String: PluginInfo] {
        firstInstalledPlugins { $0.channel }
    }

    private var filteredCatalogItems: [PluginCatalogItem] {
        viewModel.pluginCatalog.filter { item in
            matchesSearch(
                name: item.displayName,
                description: item.description,
                metadata: [item.name, item.openClawPluginID, item.category] + item.capabilities + item.keywords
            )
        }
    }

    private var filteredRecommendedCatalogItems: [PluginCatalogItem] {
        filteredCatalogItems.filter(\.isRecommended)
    }

    private var filteredBuiltInCatalogItems: [PluginCatalogItem] {
        filteredCatalogItems.filter { !$0.isRecommended }
    }

    private var filteredInstalledPlugins: [PluginInfo] {
        viewModel.plugins.filter { plugin in
            let catalogItem = catalogItem(for: plugin)
            return matchesSearch(
                name: catalogItem?.displayName ?? plugin.channel,
                description: catalogItem?.description ?? plugin.pluginId,
                metadata: [plugin.pluginId, plugin.source, plugin.version, catalogItem?.category ?? ""]
            )
        }
    }

    private var customInstalledPlugins: [PluginInfo] {
        filteredInstalledPlugins.filter { catalogItem(for: $0) == nil }
    }

    private var installedSections: [InstalledSection] {
        PluginLibrarySection.allCases.compactMap { section in
            let items = filteredInstalledPlugins.filter {
                PluginLibrarySection.section(for: $0, catalogItem: catalogItem(for: $0)) == section
            }
            guard !items.isEmpty else { return nil }
            return InstalledSection(id: section, title: section.title, items: items)
        }
    }

    var body: some View {
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
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.loadPluginMarket()
        }
        .sheet(isPresented: $showInstallSheet) {
            InstallPluginSheet(
                viewModel: viewModel,
                isPresented: $showInstallSheet
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plugins")
                    .font(.system(size: 24, weight: .semibold))
                Text("Install curated OpenClaw plugins from the GetClowHub catalog")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.pluginCatalog.isEmpty || !viewModel.plugins.isEmpty {
                Text("\(viewModel.plugins.count) installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchAndActions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                TextField("Search plugins", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
            )

            if hasGlobalPlugins {
                Button {
                    Task { await viewModel.updateAllPlugins() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoadingPlugins || viewModel.isPerformingAction)
                .help("Update installed plugins")
            }

            Button {
                showInstallSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPerformingAction)
            .help("Install custom plugin")

            Button {
                Task { await viewModel.loadPluginMarket(forceSync: true) }
            } label: {
                if viewModel.isLoadingPluginCatalog {
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
            .disabled(viewModel.isLoadingPluginCatalog || viewModel.isLoadingPlugins)
            .help("Refresh plugins")
        }
    }

    private var modePicker: some View {
        Picker("", selection: $displayMode) {
            ForEach(PluginDisplayMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 284)
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .recommend:
            recommendedPluginsContent
        case .all:
            allPluginsContent
        case .installed:
            installedPluginsContent
        }
    }

    @ViewBuilder
    private var recommendedPluginsContent: some View {
        if viewModel.isLoadingPluginCatalog && viewModel.pluginCatalog.isEmpty {
            PluginLoadingStateView(text: "Loading plugin catalog...")
        } else if let error = viewModel.pluginCatalogError, viewModel.pluginCatalog.isEmpty {
            EmptyPluginStateView(
                systemImage: "exclamationmark.triangle",
                title: "Could not load plugin catalog",
                detail: error
            )
        } else if filteredRecommendedCatalogItems.isEmpty {
            EmptyPluginStateView(
                systemImage: "puzzlepiece",
                title: viewModel.pluginCatalog.isEmpty ? "No recommended plugins" : "No matching recommended plugins",
                detail: nil
            )
        } else {
            catalogSection(
                title: PluginLibrarySection.recommend.title,
                items: filteredRecommendedCatalogItems
            )
        }
    }

    @ViewBuilder
    private var allPluginsContent: some View {
        if viewModel.isLoadingPluginCatalog && viewModel.pluginCatalog.isEmpty {
            PluginLoadingStateView(text: "Loading plugin catalog...")
        } else if let error = viewModel.pluginCatalogError,
                  viewModel.pluginCatalog.isEmpty,
                  customInstalledPlugins.isEmpty {
            EmptyPluginStateView(
                systemImage: "exclamationmark.triangle",
                title: "Could not load plugin catalog",
                detail: error
            )
        } else if filteredCatalogItems.isEmpty && customInstalledPlugins.isEmpty {
            EmptyPluginStateView(
                systemImage: "puzzlepiece",
                title: viewModel.pluginCatalog.isEmpty && viewModel.plugins.isEmpty ? "No plugins found" : "No matching plugins",
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                if !filteredRecommendedCatalogItems.isEmpty {
                    catalogSection(
                        title: PluginLibrarySection.recommend.title,
                        items: filteredRecommendedCatalogItems
                    )
                }

                if !filteredBuiltInCatalogItems.isEmpty {
                    catalogSection(
                        title: PluginLibrarySection.builtIn.title,
                        items: filteredBuiltInCatalogItems
                    )
                }

                if !customInstalledPlugins.isEmpty {
                    installedSection(
                        title: PluginLibrarySection.custom.title,
                        items: customInstalledPlugins
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var installedPluginsContent: some View {
        if viewModel.isLoadingPlugins && viewModel.plugins.isEmpty {
            PluginLoadingStateView(text: "Loading installed plugins...")
        } else if installedSections.isEmpty {
            EmptyPluginStateView(
                systemImage: "checkmark.circle",
                title: viewModel.plugins.isEmpty ? "No installed plugins" : "No matching installed plugins",
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(installedSections) { section in
                    installedSection(title: section.title, items: section.items)
                }
            }
        }
    }

    private func catalogSection(title: String, items: [PluginCatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PluginSectionHeader(title: title, count: items.count)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let installedPlugin = installedPlugin(for: item)

                    CatalogPluginListRow(
                        item: item,
                        installedPlugin: installedPlugin,
                        isInstalling: viewModel.installingCatalogPluginName == item.name,
                        onInstall: {
                            Task { await viewModel.installCatalogPlugin(item) }
                        },
                        onOpen: {
                            onOpenPluginDetail(PluginDetailPresentationItem.fromCatalog(item, installedPlugin: installedPlugin))
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

    private func installedSection(title: String, items: [PluginInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PluginSectionHeader(title: title, count: items.count)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, plugin in
                    let catalogItem = catalogItem(for: plugin)

                    InstalledPluginListRow(
                        plugin: plugin,
                        catalogItem: catalogItem,
                        onOpen: {
                            onOpenPluginDetail(PluginDetailPresentationItem.fromInstalled(plugin, catalogItem: catalogItem))
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

    private func installedPlugin(for item: PluginCatalogItem) -> PluginInfo? {
        installedPluginsByID[lookupKey(item.openClawPluginID)]
            ?? installedPluginsByID[lookupKey(item.name)]
            ?? installedPluginsByChannel[lookupKey(item.name)]
    }

    private func catalogItem(for plugin: PluginInfo) -> PluginCatalogItem? {
        catalogItemsByPluginID[lookupKey(plugin.pluginId)]
            ?? catalogItemsByName[lookupKey(plugin.pluginId)]
            ?? catalogItemsByName[lookupKey(plugin.channel)]
    }

    private func firstCatalogItems(key: (PluginCatalogItem) -> String) -> [String: PluginCatalogItem] {
        var result: [String: PluginCatalogItem] = [:]
        for item in viewModel.pluginCatalog where result[lookupKey(key(item))] == nil {
            result[lookupKey(key(item))] = item
        }
        return result
    }

    private func firstInstalledPlugins(key: (PluginInfo) -> String) -> [String: PluginInfo] {
        var result: [String: PluginInfo] = [:]
        for plugin in viewModel.plugins where result[lookupKey(key(plugin))] == nil {
            result[lookupKey(key(plugin))] = plugin
        }
        return result
    }

    private func lookupKey(_ value: String) -> String {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let slashIndex = lower.lastIndex(of: "/") else { return lower }
        return String(lower[lower.index(after: slashIndex)...])
    }

    private func matchesSearch(name: String, description: String, metadata: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = ([name, description] + metadata)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
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
        HStack(spacing: 14) {
            PluginCatalogIcon(iconURL: item.iconURL, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.description)
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
                    .help("Unavailable")
            } else {
                Button(action: onInstall) {
                    if isInstalling {
                        Text("Installing...")
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
                .help("Install")
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
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHovered)
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
        HStack(spacing: 14) {
            PluginCatalogIcon(iconURL: catalogItem?.iconURL, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogItem?.displayName ?? plugin.channel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(catalogItem?.description.nilIfBlank ?? plugin.pluginId)
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
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHovered)
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
            .help(plugin.enabled ? "Loaded" : "Disabled")
    }
}

private struct PluginCatalogIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let iconURL: URL?
    let size: CGFloat

    var body: some View {
        let customImage = resolvedCustomImage
        let isUsingDefaultIcon = customImage == nil

        Group {
            if let image = customImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("PluginIcon")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .padding(6)
        .background(isUsingDefaultIcon ? pluginDefaultIconBackground : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resolvedCustomImage: NSImage? {
        guard let iconURL else { return nil }
        return NSImage(contentsOf: iconURL)
    }

    private var pluginDefaultIconBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.32)
            : Color(NSColor.controlBackgroundColor)
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
                        PluginDetailChip(title: installedPlugin == nil ? "Not installed" : "Installed")
                        if let installedPlugin {
                            PluginDetailChip(title: installedPlugin.enabled ? "Loaded" : "Disabled")
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
                    .help("Close")
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

            Text("Description")
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
        .alert("Uninstall Plugin", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                onUninstall()
            }
        } message: {
            Text("Are you sure you want to uninstall '\(installedPlugin?.channel ?? item.displayName)'?")
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
                    Text("Installing...")
                        .frame(width: 92, height: 30)
                } else if item.catalogItem?.isOpenClawInstallable == false {
                    Text("Unavailable")
                        .frame(width: 92, height: 30)
                } else {
                    Text("Install")
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(PluginPillButtonStyle(tone: .install, isDisabled: isInstalling || item.catalogItem?.isOpenClawInstallable == false))
            .disabled(isInstalling || item.catalogItem?.isOpenClawInstallable == false)
        } else if let installedPlugin {
            if installedPlugin.origin == .global {
                Button(action: onUpdate) {
                    Text("Update")
                        .frame(width: 76, height: 30)
                }
                .buttonStyle(PluginPillButtonStyle(tone: .neutral, isDisabled: isPerformingAction))
                .disabled(isPerformingAction)

                Button(role: .destructive) {
                    showUninstallConfirm = true
                } label: {
                    Text("Uninstall")
                        .frame(width: 86, height: 30)
                }
                .buttonStyle(PluginPillButtonStyle(tone: .destructive, isDisabled: isPerformingAction))
                .disabled(isPerformingAction)
            }

            Button(action: installedPlugin.enabled ? onDisable : onEnable) {
                Text(installedPlugin.enabled ? "Disable" : "Enable")
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
}

enum PluginPreset: String, CaseIterable {
    case custom = "Custom"
    case dingtalk = "DingTalk"
    case weixin = "Weixin"

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
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool

    @State private var installMethod: InstallMethod = .npm
    @State private var selectedPreset: PluginPreset = .custom
    @State private var packageName = ""
    @State private var filePath = ""
    @State private var dirPath = ""
    @State private var isInstalling = false

    private var currentSpec: String {
        switch installMethod {
        case .npm: return packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .file: return filePath
        case .link: return dirPath
        }
    }

    private var isPresetAlreadyInstalled: Bool {
        guard selectedPreset != .custom else { return false }
        let keywords = selectedPreset.matchKeywords
        return viewModel.plugins.contains { plugin in
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
        return !currentSpec.isEmpty && !isInstalling && !viewModel.isPerformingAction
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "Install Plugin", bundle: LanguageManager.shared.localizedBundle))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Cancel", bundle: LanguageManager.shared.localizedBundle)) {
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
                        Text(String(localized: "Install Method", bundle: LanguageManager.shared.localizedBundle))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $installMethod) {
                            ForEach(InstallMethod.allCases, id: \.self) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Method-specific input
                    switch installMethod {
                    case .npm:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Quick Select", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Picker("", selection: $selectedPreset) {
                                ForEach(PluginPreset.allCases, id: \.self) { preset in
                                    Text(preset.rawValue).tag(preset)
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
                            Text(String(localized: "Package Name", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            TextField(String(localized: "e.g. @openclaw/discord", bundle: LanguageManager.shared.localizedBundle), text: $packageName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(selectedPreset == .weixin)

                            if isPresetAlreadyInstalled {
                                Label(String(localized: "\(selectedPreset.rawValue) plugin is already installed", bundle: LanguageManager.shared.localizedBundle), systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                    case .file:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Plugin File", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField(String(localized: "Select a plugin file...", bundle: LanguageManager.shared.localizedBundle), text: $filePath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button(String(localized: "Browse", bundle: LanguageManager.shared.localizedBundle)) {
                                    browseFile()
                                }
                            }

                            Text(String(localized: "Supported: .ts .js .zip .tgz .tar.gz", bundle: LanguageManager.shared.localizedBundle))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                    case .link:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "Plugin Directory", bundle: LanguageManager.shared.localizedBundle))
                                .font(.subheadline)
                                .fontWeight(.medium)

                            HStack {
                                TextField(String(localized: "Select a plugin directory...", bundle: LanguageManager.shared.localizedBundle), text: $dirPath)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(true)

                                Button(String(localized: "Browse", bundle: LanguageManager.shared.localizedBundle)) {
                                    browseDirectory()
                                }
                            }

                            Text(String(localized: "Select a local plugin directory for development linking", bundle: LanguageManager.shared.localizedBundle))
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
                    Text(String(localized: "Installing...", bundle: LanguageManager.shared.localizedBundle))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(String(localized: "Install", bundle: LanguageManager.shared.localizedBundle)) {
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

    private func browseDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK, let url = panel.url {
            dirPath = url.path
        }
    }

    private func performInstall() {
        isInstalling = true
        let spec = currentSpec
        let isLink = installMethod == .link
        let isWeixin = selectedPreset == .weixin
        Task {
            if isWeixin {
                await viewModel.installWeixinPlugin()
            } else {
                await viewModel.installPlugin(spec: spec, link: isLink)
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
            viewModel: DashboardViewModel(
                openclawService: OpenClawService(
                    commandExecutor: CommandExecutor(
                        permissionManager: PermissionManager()
                    )
                ),
                settings: AppSettingsManager(),
                systemEnvironment: SystemEnvironment(
                    commandExecutor: CommandExecutor(
                        permissionManager: PermissionManager()
                    )
                ),
                commandExecutor: CommandExecutor(
                    permissionManager: PermissionManager()
                )
            ),
            onOpenPluginDetail: { _ in }
        )
    }
}

#Preview {
    PluginsTabPreviewWrapper()
        .frame(width: 700, height: 600)
}
