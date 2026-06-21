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

    static func fromCatalog(_ item: SkillCatalogItem) -> SkillDetailPresentationItem {
        SkillDetailPresentationItem(
            id: "catalog-\(item.id)",
            name: item.name,
            displayName: item.displayName,
            description: item.description,
            documentationMarkdown: item.documentationMarkdown,
            sourceTitle: item.isRecommended ? "Recommend" : "Catalog",
            catalogItem: item,
            iconURL: item.iconURL
        )
    }

    static func fromInstalled(_ skill: SkillInfo, catalogItem: SkillCatalogItem?) -> SkillDetailPresentationItem {
        let sourceTitle: String
        if catalogItem?.isRecommended == true {
            sourceTitle = "Recommend"
        } else if catalogItem != nil {
            sourceTitle = "Catalog"
        } else {
            sourceTitle = "Custom"
        }
        let description = catalogItem?.description.nilIfBlank
            ?? skill.description.nilIfBlank
            ?? "Installed skill"

        return SkillDetailPresentationItem(
            id: "installed-\(skill.name)",
            name: skill.name,
            displayName: catalogItem?.displayName ?? skill.name,
            description: description,
            documentationMarkdown: catalogItem?.documentationMarkdown.nilIfBlank ?? description,
            sourceTitle: sourceTitle,
            catalogItem: catalogItem,
            iconURL: catalogItem?.iconURL
        )
    }
}

struct SkillsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenSkillDetail: (SkillDetailPresentationItem) -> Void
    @State private var searchText = ""
    @State private var displayMode: SkillDisplayMode = .recommend
    @State private var skillPointerLocation: CGPoint?
    @State private var showManualInstallSheet = false

    private enum SkillDisplayMode: String, CaseIterable {
        case recommend = "Recommend"
        case all = "All"
        case installed = "Installed"
    }

    private var installedSkillsByName: [String: SkillInfo] {
        SkillNameIndex.firstByName(viewModel.skills) { $0.name }
    }

    private var catalogItemsByName: [String: SkillCatalogItem] {
        SkillNameIndex.firstByName(viewModel.skillCatalog) { $0.name }
    }

    private var filteredCatalogItems: [SkillCatalogItem] {
        viewModel.skillCatalog.filter { item in
            matchesSearch(
                name: item.displayName,
                description: item.description,
                metadata: [item.name, item.isRecommended ? "recommended" : "", item.tags.joined(separator: " ")]
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
        viewModel.skills.filter { skill in
            let catalogItem = catalogItemsByName[skill.name]
            return matchesSearch(
                name: catalogItem?.displayName ?? skill.name,
                description: catalogItem?.description ?? skill.description,
                metadata: [
                    skill.name,
                    skill.source,
                    catalogItem?.isRecommended == true ? "recommended" : "",
                    catalogItem?.tags.joined(separator: " ") ?? ""
                ]
            )
        }
    }

    init(
        viewModel: DashboardViewModel,
        onOpenSkillDetail: @escaping (SkillDetailPresentationItem) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onOpenSkillDetail = onOpenSkillDetail
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
        }
        .coordinateSpace(name: SkillDockMagnification.coordinateSpace)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                skillPointerLocation = location
            case .ended:
                skillPointerLocation = nil
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.loadSkillMarket()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Skills")
                    .font(.system(size: 24, weight: .semibold))
                Text("Extend GetClowHub with task-specific skills")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !viewModel.skillCatalog.isEmpty || !viewModel.skills.isEmpty {
                Text("\(viewModel.skills.count) installed")
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

                TextField("Search skills", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())

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
            .help("Install skill from GitHub repository")

            Button {
                Task { await viewModel.loadSkillMarket(forceSync: true) }
            } label: {
                if viewModel.isLoadingSkillCatalog {
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
            .disabled(viewModel.isLoadingSkillCatalog)
            .help("Refresh skills")
        }
    }

    private var modePicker: some View {
        Picker("", selection: $displayMode) {
            ForEach(SkillDisplayMode.allCases, id: \.self) { mode in
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
            recommendedSkillsContent
        case .all:
            allSkillsContent
        case .installed:
            installedSkillsContent
        }
    }

    @ViewBuilder
    private var recommendedSkillsContent: some View {
        if viewModel.isLoadingSkillCatalog && viewModel.skillCatalog.isEmpty {
            LoadingStateView(text: "Loading skill catalog...")
        } else if let error = viewModel.skillCatalogError, viewModel.skillCatalog.isEmpty {
            EmptySkillStateView(
                systemImage: "exclamationmark.triangle",
                title: "Could not load skill catalog",
                detail: error
            )
        } else if filteredRecommendedCatalogItems.isEmpty {
            EmptySkillStateView(
                systemImage: "bolt",
                title: viewModel.skillCatalog.isEmpty ? "No recommended skills" : "No matching recommended skills",
                detail: nil
            )
        } else {
            catalogSkillSection(
                title: "Recommend",
                items: filteredRecommendedCatalogItems
            )
        }
    }

    @ViewBuilder
    private var allSkillsContent: some View {
        if viewModel.isLoadingSkillCatalog && viewModel.skillCatalog.isEmpty {
            LoadingStateView(text: "Loading skill catalog...")
        } else if let error = viewModel.skillCatalogError, viewModel.skillCatalog.isEmpty {
            EmptySkillStateView(
                systemImage: "exclamationmark.triangle",
                title: "Could not load skill catalog",
                detail: error
            )
        } else if filteredCatalogItems.isEmpty && filteredCustomInstalledSkills.isEmpty {
            EmptySkillStateView(
                systemImage: "bolt.slash",
                title: viewModel.skillCatalog.isEmpty ? "No skills found" : "No matching skills",
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
                    guard !viewModel.isInstallingManualSkill else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showManualInstallSheet = false
                    }
                }

            ManualSkillInstallSheet(
                isInstalling: viewModel.isInstallingManualSkill,
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showManualInstallSheet = false
                    }
                },
                onInstall: { repository in
                    Task {
                        let didInstall = await viewModel.installManualSkill(repository: repository)
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
            SkillSectionHeader(title: "All", count: catalogItems.count + customSkills.count)

            VStack(spacing: 0) {
                ForEach(Array(catalogItems.enumerated()), id: \.element.id) { index, item in
                    CatalogSkillListRow(
                        item: item,
                        installedSkill: installedSkillsByName[item.name],
                        isInstalling: viewModel.installingCatalogSkillName == item.name,
                        pointerLocation: skillPointerLocation,
                        onInstall: {
                            Task { await viewModel.installCatalogSkill(item) }
                        },
                        onOpen: {
                            onOpenSkillDetail(SkillDetailPresentationItem.fromCatalog(item))
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
                        pointerLocation: skillPointerLocation,
                        onOpen: {
                            onOpenSkillDetail(
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

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    CatalogSkillListRow(
                        item: item,
                        installedSkill: installedSkillsByName[item.name],
                        isInstalling: viewModel.installingCatalogSkillName == item.name,
                        pointerLocation: skillPointerLocation,
                        onInstall: {
                            Task { await viewModel.installCatalogSkill(item) }
                        },
                        onOpen: {
                            onOpenSkillDetail(SkillDetailPresentationItem.fromCatalog(item))
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
        if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
            LoadingStateView(text: "Loading installed skills...")
        } else if filteredInstalledSkills.isEmpty {
            EmptySkillStateView(
                systemImage: "checkmark.circle",
                title: viewModel.skills.isEmpty ? "No installed skills" : "No matching installed skills",
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SkillSectionHeader(title: "Installed", count: filteredInstalledSkills.count)

                VStack(spacing: 0) {
                    ForEach(Array(filteredInstalledSkills.enumerated()), id: \.offset) { index, skill in
                        InstalledSkillListRow(
                            skill: skill,
                            catalogItem: catalogItemsByName[skill.name],
                            pointerLocation: skillPointerLocation,
                            onOpen: {
                                onOpenSkillDetail(
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

    private func matchesSearch(name: String, description: String, metadata: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let haystack = ([name, description] + metadata)
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(query)
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
                Text("Install Skill")
                    .font(.system(size: 21, weight: .semibold))

                Text("Install a GitHub skill repository globally.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository")
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
                    Text("Cancel")
                        .frame(width: 92, height: 30)
                }
                .buttonStyle(SkillPillButtonStyle(tone: .neutral, isDisabled: isInstalling))
                .disabled(isInstalling)

                Button {
                    onInstall(repository)
                } label: {
                    Text(isInstalling ? "Installing..." : "Install")
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

private enum SkillDockMagnification {
    static let coordinateSpace = "skills-dock-magnification"
    static let radius: CGFloat = 118
    static let maxScale: CGFloat = 0.08

    static func scale(pointerLocation: CGPoint?, rowFrame: CGRect, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, let pointerLocation, !rowFrame.isEmpty else { return 1 }

        let center = CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        let distance = hypot(pointerLocation.x - center.x, pointerLocation.y - center.y)
        let influence = max(0, 1 - distance / radius)
        return 1 + influence * maxScale
    }
}

private struct SkillRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct SkillMagnifiedRow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pointerLocation: CGPoint?
    @ViewBuilder let content: () -> Content
    @State private var rowFrame: CGRect = .zero

    var body: some View {
        let rowScale = SkillDockMagnification.scale(
            pointerLocation: pointerLocation,
            rowFrame: rowFrame,
            reduceMotion: reduceMotion
        )

        content()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SkillRowFramePreferenceKey.self,
                        value: proxy.frame(in: .named(SkillDockMagnification.coordinateSpace))
                    )
                }
            )
            .onPreferenceChange(SkillRowFramePreferenceKey.self) { frame in
                rowFrame = frame
            }
            .scaleEffect(rowScale, anchor: .center)
            .zIndex(Double(rowScale))
            .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.86, blendDuration: 0.04), value: rowScale)
    }
}

private struct CatalogSkillListRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let item: SkillCatalogItem
    let installedSkill: SkillInfo?
    let isInstalling: Bool
    let pointerLocation: CGPoint?
    let onInstall: () -> Void
    let onOpen: () -> Void

    var body: some View {
        SkillMagnifiedRow(pointerLocation: pointerLocation) {
            HStack(spacing: 14) {
                SkillCatalogIcon(iconURL: item.iconURL, size: 32)

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

                if let installedSkill {
                    InstalledStatusMark(status: installedSkill.status)
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
                    .help("Install")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHovered)
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
    let pointerLocation: CGPoint?
    let onOpen: () -> Void

    var body: some View {
        SkillMagnifiedRow(pointerLocation: pointerLocation) {
            HStack(spacing: 14) {
                SkillCatalogIcon(iconURL: catalogItem?.iconURL, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(catalogItem?.displayName ?? skill.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(catalogItem?.description.nilIfBlank ?? skill.description.nilIfBlank ?? "Installed skill")
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
        }
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isHovered)
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
                .help("Ready")
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .help("Missing requirements")
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
                Image("SkillAvatarUnifiedDark")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .padding(6)
        .background(isUsingDefaultIcon ? skillDefaultIconBackground : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resolvedCustomImage: NSImage? {
        guard let iconURL else { return nil }
        return NSImage(contentsOf: iconURL)
    }

    private var skillDefaultIconBackground: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.32)
            : Color(NSColor.controlBackgroundColor)
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
                        SkillDetailChip(title: installedSkill == nil ? "Not installed" : "Installed")
                        if let installedSkill {
                            SkillDetailChip(title: installedSkill.status == .ready ? "Ready" : "Missing")
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
                    Text("Installing...")
                        .frame(width: 92, height: 30)
                } else {
                    Text("Install")
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(SkillPillButtonStyle(tone: .install, isDisabled: isInstalling))
            .disabled(isInstalling)
        } else if canRemove {
            Button(role: .destructive, action: onRemove) {
                if isRemoving {
                    Text("Removing...")
                        .frame(width: 92, height: 30)
                } else {
                    Text("Uninstall")
                        .frame(width: 92, height: 30)
                }
            }
            .buttonStyle(SkillPillButtonStyle(tone: .destructive, isDisabled: isRemoving))
            .disabled(isRemoving)
        } else {
            Text("Installed")
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
        )
    )
    .frame(width: 1100, height: 800)
}
