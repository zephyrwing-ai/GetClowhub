import SwiftUI
import AppKit
import MarkdownUI

struct SkillDetailPresentationItem: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let documentationMarkdown: String
    let sourceTitle: String
    let catalogItem: SkillCatalogItem?
    let iconURL: URL?

    @MainActor
    static func fromCatalog(_ item: SkillCatalogItem) -> SkillDetailPresentationItem {
        let display = I18n.skillDisplay(for: item)
        return SkillDetailPresentationItem(
            id: "catalog-\(item.id)",
            name: item.name,
            displayName: display.displayName,
            description: display.description,
            documentationMarkdown: display.content,
            sourceTitle: item.isRecommended ? I18n.t("catalog.section.recommend") : I18n.t("catalog.section.catalog"),
            catalogItem: item,
            iconURL: item.iconURL
        )
    }

    @MainActor
    static func fromInstalled(_ skill: SkillInfo, catalogItem: SkillCatalogItem?) -> SkillDetailPresentationItem {
        let sourceTitle: String
        if catalogItem?.isRecommended == true {
            sourceTitle = I18n.t("catalog.section.recommend")
        } else if catalogItem != nil {
            sourceTitle = I18n.t("catalog.section.catalog")
        } else {
            sourceTitle = I18n.t("catalog.section.custom")
        }
        let localizedCatalog = catalogItem.map { I18n.skillDisplay(for: $0) }
        let description = localizedCatalog?.description.nilIfBlank
            ?? skill.description.nilIfBlank
            ?? I18n.t("skills.fallback.installedSkill")

        return SkillDetailPresentationItem(
            id: "installed-\(skill.name)",
            name: skill.name,
            displayName: localizedCatalog?.displayName ?? skill.name,
            description: description,
            documentationMarkdown: localizedCatalog?.content.nilIfBlank ?? description,
            sourceTitle: sourceTitle,
            catalogItem: catalogItem,
            iconURL: catalogItem?.iconURL
        )
    }
}

struct SkillsTabView: View {
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: SkillsTabModel
    @State private var searchText = ""
    @State private var displayMode: SkillDisplayMode = .recommend
    @State private var showManualInstallSheet = false
    @State private var selectedSkillDetailItem: SkillDetailPresentationItem?
    @State private var skillPendingRemoval: SkillInfo?

    private enum SkillDisplayMode: String, CaseIterable {
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

    private var installedSkillsByName: [String: SkillInfo] {
        SkillNameIndex.firstByName(model.skills) { $0.name }
    }

    private var catalogItemsByName: [String: SkillCatalogItem] {
        SkillNameIndex.firstByName(model.skillCatalog) { $0.name }
    }

    private var filteredCatalogItems: [SkillCatalogItem] {
        model.skillCatalog.filter { item in
            let display = I18n.skillDisplay(for: item)
            return matchesSearch(
                fields: I18n.localizedSearchFields(
                    [display.displayName, display.description, display.content],
                    originals: [item.displayName, item.description, item.documentationMarkdown, item.name, item.isRecommended ? "recommended" : "", item.tags.joined(separator: " ")]
                )
            )
        }
    }

    private var filteredRecommendedCatalogItems: [SkillCatalogItem] {
        filteredCatalogItems.filter(\.isRecommended)
    }

    private var filteredCustomInstalledSkills: [SkillInfo] {
        filteredInstalledSkills.filter { catalogItemsByName[$0.name] == nil }
    }

    private var filteredInstalledSkills: [SkillInfo] {
        model.skills.filter { skill in
            let catalogItem = catalogItemsByName[skill.name]
            let display = catalogItem.map { I18n.skillDisplay(for: $0) }
            return matchesSearch(
                fields: I18n.localizedSearchFields(
                    [
                        display?.displayName ?? skill.name,
                        display?.description ?? skill.description,
                        display?.content ?? ""
                    ],
                    originals: [
                        catalogItem?.displayName ?? skill.name,
                        catalogItem?.description ?? skill.description,
                        catalogItem?.documentationMarkdown ?? "",
                        skill.name,
                        skill.source,
                        catalogItem?.isRecommended == true ? "recommended" : "",
                        catalogItem?.tags.joined(separator: " ") ?? ""
                    ]
                )
            )
        }
    }

    init(
        openclawService: OpenClawService,
        notifySuccess: @escaping (String) -> Void = { _ in },
        notifyError: @escaping (String) -> Void = { _ in }
    ) {
        _model = StateObject(
            wrappedValue: SkillsTabModel(
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

            if showManualInstallSheet {
                manualInstallOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let selectedSkillDetailItem {
                skillDetailOverlay(for: selectedSkillDetailItem)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await model.loadSkillMarket()
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: selectedSkillDetailItem?.id)
        .alert(item: $skillPendingRemoval) { skill in
            Alert(
                title: Text(I18n.t("skills.alert.removeTitle")),
                message: Text(I18n.format("skills.alert.removeMessage", skill.name)),
                primaryButton: .destructive(Text(I18n.t("catalog.action.remove", fallback: "Remove"))) {
                    Task { await model.removeSkill(skill) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(I18n.t("skills.title"))
                    .font(.system(size: 24, weight: .semibold))
                Text(I18n.t("skills.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.skillCatalog.isEmpty || !model.skills.isEmpty {
                Text(I18n.format("catalog.count.installed", Int64(model.skills.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchAndActions: some View {
        HStack(spacing: 10) {
            UnifiedSearchField(placeholder: I18n.t("skills.search.placeholder"), text: $searchText)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showManualInstallSheet = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(I18n.t("skills.help.installFromRepository"))

            Button {
                Task { await model.loadSkillMarket(forceSync: true) }
            } label: {
                if model.isLoadingSkillCatalog {
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
            .disabled(model.isLoadingSkillCatalog)
            .help(I18n.t("skills.help.refresh"))
        }
    }

    private var modePicker: some View {
        Picker("", selection: $displayMode) {
            ForEach(SkillDisplayMode.allCases, id: \.self) { mode in
                Text(mode.localizedTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 284)
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .recommend:
            recommendedSkillsContent
        case .all:
            allSkillsContent
        case .installed:
            installedSkillsContent
        }
    }

    @ViewBuilder
    private var recommendedSkillsContent: some View {
        if model.isLoadingSkillCatalog && model.skillCatalog.isEmpty {
            LoadingStateView(text: I18n.t("skills.loading.catalog"))
        } else if let error = model.skillCatalogError, model.skillCatalog.isEmpty {
            EmptySkillStateView(
                systemImage: "exclamationmark.triangle",
                title: I18n.t("skills.empty.catalogLoadFailed"),
                detail: error
            )
        } else if filteredRecommendedCatalogItems.isEmpty {
            EmptySkillStateView(
                systemImage: "bolt",
                title: model.skillCatalog.isEmpty ? I18n.t("skills.empty.noRecommended") : I18n.t("skills.empty.noMatchingRecommended"),
                detail: nil
            )
        } else {
            catalogSkillSection(
                title: I18n.t("catalog.section.recommend"),
                items: filteredRecommendedCatalogItems
            )
        }
    }

    @ViewBuilder
    private var allSkillsContent: some View {
        if model.isLoadingSkillCatalog && model.skillCatalog.isEmpty {
            LoadingStateView(text: I18n.t("skills.loading.catalog"))
        } else if let error = model.skillCatalogError, model.skillCatalog.isEmpty {
            EmptySkillStateView(
                systemImage: "exclamationmark.triangle",
                title: I18n.t("skills.empty.catalogLoadFailed"),
                detail: error
            )
        } else if filteredCatalogItems.isEmpty && filteredCustomInstalledSkills.isEmpty {
            EmptySkillStateView(
                systemImage: "bolt.slash",
                title: model.skillCatalog.isEmpty ? I18n.t("skills.empty.noSkills") : I18n.t("skills.empty.noMatchingSkills"),
                detail: nil
            )
        } else {
            allSkillSection(
                catalogItems: filteredCatalogItems,
                customSkills: filteredCustomInstalledSkills
            )
        }
    }

    private var manualInstallOverlay: some View {
        ZStack {
            Color.black
                .opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !model.isInstallingManualSkill else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showManualInstallSheet = false
                    }
                }

            ManualSkillInstallSheet(
                isInstalling: model.isInstallingManualSkill,
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showManualInstallSheet = false
                    }
                },
                onInstall: { repository in
                    Task {
                        let didInstall = await model.installManualSkill(repository: repository)
                        if didInstall {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showManualInstallSheet = false
                            }
                        }
                    }
                }
            )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.42 : 0.16), radius: 24, x: 0, y: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
            )
            .padding(28)
        }
    }

    private func allSkillSection(catalogItems: [SkillCatalogItem], customSkills: [SkillInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SkillSectionHeader(title: I18n.t("catalog.section.all"), count: catalogItems.count + customSkills.count)

            LazyVStack(spacing: 0) {
                ForEach(Array(catalogItems.enumerated()), id: \.element.id) { index, item in
                    CatalogSkillListRow(
                        item: item,
                        installedSkill: installedSkillsByName[item.name],
                        isInstalling: model.installingCatalogSkillName == item.name,
                        onInstall: {
                            Task { await model.installCatalogSkill(item) }
                        },
                        onOpen: {
                            presentSkillDetail(SkillDetailPresentationItem.fromCatalog(item))
                        }
                    )

                    if index < catalogItems.count - 1 || !customSkills.isEmpty {
                        Divider()
                            .padding(.leading, 56)
                    }
                }

                ForEach(Array(customSkills.enumerated()), id: \.element.name) { index, skill in
                    InstalledSkillListRow(
                        skill: skill,
                        catalogItem: nil,
                        onOpen: {
                            presentSkillDetail(
                                SkillDetailPresentationItem.fromInstalled(
                                    skill,
                                    catalogItem: nil
                                )
                            )
                        }
                    )

                    if index < customSkills.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }

    private func catalogSkillSection(title: String, items: [SkillCatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SkillSectionHeader(title: title, count: items.count)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    CatalogSkillListRow(
                        item: item,
                        installedSkill: installedSkillsByName[item.name],
                        isInstalling: model.installingCatalogSkillName == item.name,
                        onInstall: {
                            Task { await model.installCatalogSkill(item) }
                        },
                        onOpen: {
                            presentSkillDetail(SkillDetailPresentationItem.fromCatalog(item))
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

    @ViewBuilder
    private var installedSkillsContent: some View {
        if model.isLoadingSkills && model.skills.isEmpty {
            LoadingStateView(text: I18n.t("skills.loading.installed"))
        } else if filteredInstalledSkills.isEmpty {
            EmptySkillStateView(
                systemImage: "checkmark.circle",
                title: model.skills.isEmpty ? I18n.t("skills.empty.noInstalled") : I18n.t("skills.empty.noMatchingInstalled"),
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SkillSectionHeader(title: I18n.t("catalog.section.installed"), count: filteredInstalledSkills.count)

                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredInstalledSkills.enumerated()), id: \.offset) { index, skill in
                        InstalledSkillListRow(
                            skill: skill,
                            catalogItem: catalogItemsByName[skill.name],
                            onOpen: {
                                presentSkillDetail(
                                    SkillDetailPresentationItem.fromInstalled(
                                        skill,
                                        catalogItem: catalogItemsByName[skill.name]
                                    )
                                )
                            }
                        )

                        if index < filteredInstalledSkills.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
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

    private func presentSkillDetail(_ item: SkillDetailPresentationItem) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            selectedSkillDetailItem = item
        }
    }

    private func dismissSkillCatalogDetail() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) {
            selectedSkillDetailItem = nil
        }
    }

    private func skillDetailOverlay(for item: SkillDetailPresentationItem) -> some View {
        let installedSkill = installedSkillsByName[item.name]
        let isDark = colorScheme == .dark

        return GeometryReader { _ in
            ZStack {
                Color.black
                    .opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissSkillCatalogDetail()
                    }

                SkillCatalogDetailSheet(
                    item: item,
                    installedSkill: installedSkill,
                    isInstalling: model.installingCatalogSkillName == item.name,
                    isRemoving: model.removingSkillName == item.name,
                    canRemove: installedSkill.map(SkillsTabModel.canRemoveSkill) ?? false,
                    onInstall: {
                        if let catalogItem = item.catalogItem {
                            Task { await model.installCatalogSkill(catalogItem) }
                        }
                    },
                    onRemove: {
                        if let skill = installedSkill {
                            skillPendingRemoval = skill
                        }
                    },
                    onClose: dismissSkillCatalogDetail
                )
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 28, x: 0, y: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.16 : 0.08), lineWidth: 1)
                )
                .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
        ))
    }
}

private struct ManualSkillInstallSheet: View {
    @State private var repository = ""

    let isInstalling: Bool
    let onCancel: () -> Void
    let onInstall: (String) -> Void

    private var canInstall: Bool {
        !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isInstalling
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(I18n.t("skills.manual.title"))
                    .font(.system(size: 21, weight: .semibold))

                Text(I18n.t("skills.manual.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(I18n.t("skills.manual.repository"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("owner/repo", text: $repository)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .disabled(isInstalling)
                    .onSubmit {
                        if canInstall {
                            onInstall(repository)
                        }
                    }
            }

            HStack(spacing: 10) {
                Spacer()

                Button(action: onCancel) {
                    Text(I18n.t("catalog.action.cancel"))
                        .frame(width: 92, height: 30)
                }
                .buttonStyle(SkillPillButtonStyle(tone: .neutral, isDisabled: isInstalling))
                .disabled(isInstalling)

                Button {
                    onInstall(repository)
                } label: {
                    Text(isInstalling ? I18n.t("catalog.action.installing") : I18n.t("catalog.action.install"))
                        .frame(width: 104, height: 30)
                }
                .buttonStyle(SkillPillButtonStyle(tone: .install, isDisabled: !canInstall))
                .disabled(!canInstall)
            }
        }
        .padding(26)
        .frame(width: 520)
    }
}

private struct SkillSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private enum SkillInstallPalette {
    static let amber = Color(red: 0.72, green: 0.47, blue: 0.12)
    static let copper = Color(red: 0.66, green: 0.40, blue: 0.23)

    static func iconBackground(colorScheme: ColorScheme, isHovered: Bool) -> Color {
        let opacity: Double
        if colorScheme == .dark {
            opacity = isHovered ? 0.24 : 0.16
        } else {
            opacity = isHovered ? 0.17 : 0.11
        }
        return amber.opacity(opacity)
    }

    static func iconBorder(isHovered: Bool) -> Color {
        copper.opacity(isHovered ? 0.44 : 0.24)
    }
}

private struct CatalogSkillListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let item: SkillCatalogItem
    let installedSkill: SkillInfo?
    let isInstalling: Bool
    let onInstall: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let display = I18n.skillDisplay(for: item)

        HStack(spacing: 14) {
            SkillCatalogIcon(iconURL: item.iconURL, size: 32)

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

            if let installedSkill {
                InstalledStatusMark(status: installedSkill.status)
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
                            .foregroundStyle(SkillInstallPalette.amber)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(SkillInstallPalette.iconBackground(colorScheme: colorScheme, isHovered: isHovered))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(SkillInstallPalette.iconBorder(isHovered: isHovered), lineWidth: 1)
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
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        return colorScheme == .dark
            ? Color.white.opacity(isHovered ? 0.075 : 0)
            : Color.black.opacity(isHovered ? 0.065 : 0)
    }
}

private struct InstalledSkillListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let skill: SkillInfo
    let catalogItem: SkillCatalogItem?
    let onOpen: () -> Void

    var body: some View {
        let display = catalogItem.map { I18n.skillDisplay(for: $0) }
        let title = display?.displayName ?? skill.name
        let description = display?.description.nilIfBlank
            ?? skill.description.nilIfBlank
            ?? I18n.t("skills.fallback.installedSkill")

        HStack(spacing: 14) {
            SkillCatalogIcon(iconURL: catalogItem?.iconURL, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            InstalledStatusMark(status: skill.status)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        return colorScheme == .dark
            ? Color.white.opacity(isHovered ? 0.075 : 0)
            : Color.black.opacity(isHovered ? 0.065 : 0)
    }
}

private struct InstalledStatusMark: View {
    let status: SkillStatus

    var body: some View {
        if status == .ready {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .help(I18n.t("catalog.status.ready"))
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .help(I18n.t("catalog.status.missing"))
        }
    }
}

private struct SkillCatalogIcon: View {
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
                Image(systemName: AppSystemSymbol.skills)
                    .font(.system(size: size * 0.58, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .padding(6)
        .background(isUsingDefaultIcon ? skillDefaultIconBackground : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resolvedCustomImage: NSImage? {
        guard let iconURL else { return nil }
        return SkillIconImageCache.shared.image(for: iconURL)
    }

    private var skillDefaultIconBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.32)
            : Color(NSColor.controlBackgroundColor)
    }
}

private final class SkillIconImageCache {
    static let shared = SkillIconImageCache()

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

private struct LoadingStateView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

private struct EmptySkillStateView: View {
    let systemImage: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct SkillCatalogDetailSheet: View {
    let item: SkillDetailPresentationItem
    let installedSkill: SkillInfo?
    let isInstalling: Bool
    let isRemoving: Bool
    let canRemove: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.displayName)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        SkillDetailChip(title: item.sourceTitle)
                        SkillDetailChip(title: installedSkill == nil ? I18n.t("catalog.status.notInstalled") : I18n.t("catalog.status.installed"))
                        if let installedSkill {
                            SkillDetailChip(title: installedSkill.status == .ready ? I18n.t("catalog.status.ready") : I18n.t("catalog.status.missing"))
                        }
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    actionControl

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

        return body.isEmpty && hasTrimmedHeading ? item.description : body
    }

    @ViewBuilder
    private var actionControl: some View {
        if installedSkill == nil {
            Button(action: onInstall) {
                if isInstalling {
                    Text(I18n.t("catalog.action.installing"))
                        .frame(width: 92, height: 30)
                } else {
                    Text(I18n.t("catalog.action.install"))
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(SkillPillButtonStyle(tone: .install, isDisabled: isInstalling))
            .disabled(isInstalling)
        } else if canRemove {
            Button(role: .destructive, action: onRemove) {
                if isRemoving {
                    Text(I18n.t("catalog.action.removing"))
                        .frame(width: 92, height: 30)
                } else {
                    Text(I18n.t("catalog.action.uninstall"))
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(SkillPillButtonStyle(tone: .destructive, isDisabled: isRemoving))
            .disabled(isRemoving)
        } else {
            Text(I18n.t("catalog.status.installed"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct SkillDetailChip: View {
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

private struct SkillPillButtonStyle: ButtonStyle {
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
                    .stroke(borderColor.opacity(configuration.isPressed ? 1 : 0.82), lineWidth: borderWidth)
            )
            .opacity(isDisabled ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tone {
        case .install:
            return SkillInstallPalette.amber
        case .neutral:
            return .primary
        case .destructive:
            return Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .install:
            return SkillInstallPalette.amber.opacity(colorScheme == .dark ? 0.18 : 0.12)
        case .neutral:
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.08)
        case .destructive:
            return Color(red: 1.0, green: 0.18, blue: 0.20)
                .opacity(colorScheme == .dark ? 0.20 : 0.14)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .install:
            return SkillInstallPalette.copper.opacity(colorScheme == .dark ? 0.44 : 0.30)
        case .neutral, .destructive:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch tone {
        case .install:
            return 1
        case .neutral, .destructive:
            return 0
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    SkillsTabView(
        openclawService: OpenClawService(
            commandExecutor: CommandExecutor(
                permissionManager: PermissionManager()
            )
        )
    )
    .frame(width: 1100, height: 800)
}
