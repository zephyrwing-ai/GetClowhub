import SwiftUI
import AppKit
import MarkdownUI

struct SkillsTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenCatalogItem: (SkillCatalogItem) -> Void
    @State private var searchText = ""
    @State private var displayMode: SkillDisplayMode = .all
    @State private var showManualInstallSheet = false

    private enum SkillDisplayMode: String, CaseIterable {
        case all = "All"
        case installed = "Installed"
    }

    private struct InstalledSection: Identifiable {
        let id: SkillLibrarySection
        let title: String
        let items: [SkillInfo]
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
                metadata: [item.name, item.category.title]
            )
        }
    }

    private var filteredInstalledSkills: [SkillInfo] {
        viewModel.skills.filter { skill in
            let catalogItem = catalogItemsByName[skill.name]
            return matchesSearch(
                name: catalogItem?.displayName ?? skill.name,
                description: catalogItem?.description ?? skill.description,
                metadata: [skill.name, skill.source, catalogItem?.category.title ?? ""]
            )
        }
    }

    private var customInstalledSkills: [SkillInfo] {
        filteredInstalledSkills.filter { skill in
            SkillLibrarySection.section(
                forSkillName: skill.name,
                catalogItemsByName: catalogItemsByName
            ) == .custom
        }
    }

    private var installedSections: [InstalledSection] {
        SkillLibrarySection.allCases.compactMap { section in
            let items = filteredInstalledSkills.filter {
                SkillLibrarySection.section(
                    forSkillName: $0.name,
                    catalogItemsByName: catalogItemsByName
                ) == section
            }
            guard !items.isEmpty else { return nil }
            return InstalledSection(id: section, title: section.title, items: items)
        }
    }

    init(
        viewModel: DashboardViewModel,
        onOpenCatalogItem: @escaping (SkillCatalogItem) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onOpenCatalogItem = onOpenCatalogItem
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
            await viewModel.loadSkillMarket()
        }
        .sheet(isPresented: $showManualInstallSheet) {
            ManualSkillInstallSheet(
                viewModel: viewModel,
                isPresented: $showManualInstallSheet
            )
        }
        .sheet(item: $viewModel.selectedSkillDetail) { detail in
            SkillDetailSheet(detail: detail, isPresented: Binding(
                get: { viewModel.selectedSkillDetail != nil },
                set: { if !$0 { viewModel.selectedSkillDetail = nil } }
            ))
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
                showManualInstallSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SkillInstallPalette.amber)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(SkillInstallPalette.iconBackground(colorScheme: colorScheme, isHovered: false))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SkillInstallPalette.iconBorder(isHovered: false), lineWidth: 1)
                    )
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
        .frame(width: 190)
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .all:
            allSkillsContent
        case .installed:
            installedSkillsContent
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
        } else if filteredCatalogItems.isEmpty && customInstalledSkills.isEmpty {
            EmptySkillStateView(
                systemImage: "bolt.slash",
                title: viewModel.skillCatalog.isEmpty && viewModel.skills.isEmpty ? "No skills found" : "No matching skills",
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                if !filteredCatalogItems.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SkillSectionHeader(title: SkillLibrarySection.builtIn.title, count: filteredCatalogItems.count)

                        VStack(spacing: 0) {
                            ForEach(Array(filteredCatalogItems.enumerated()), id: \.offset) { index, item in
                                CatalogSkillListRow(
                                    item: item,
                                    installedSkill: installedSkillsByName[item.name],
                                    isInstalling: viewModel.installingCatalogSkillName == item.name,
                                    onInstall: {
                                        Task { await viewModel.installCatalogSkill(item) }
                                    },
                                    onOpen: {
                                        onOpenCatalogItem(item)
                                    }
                                )

                                if index < filteredCatalogItems.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }

                if !customInstalledSkills.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SkillSectionHeader(title: SkillLibrarySection.custom.title, count: customInstalledSkills.count)

                        VStack(spacing: 0) {
                            ForEach(Array(customInstalledSkills.enumerated()), id: \.offset) { index, skill in
                                InstalledSkillListRow(
                                    skill: skill,
                                    catalogItem: nil,
                                    isLoadingDetail: viewModel.isLoadingSkillDetail,
                                    onInfo: {
                                        Task { await viewModel.loadSkillDetail(skill.name) }
                                    }
                                )

                                if index < customInstalledSkills.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var installedSkillsContent: some View {
        if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
            LoadingStateView(text: "Loading installed skills...")
        } else if installedSections.isEmpty {
            EmptySkillStateView(
                systemImage: "checkmark.circle",
                title: viewModel.skills.isEmpty ? "No installed skills" : "No matching installed skills",
                detail: nil
            )
        } else {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(installedSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        SkillSectionHeader(title: section.title, count: section.items.count)

                        VStack(spacing: 0) {
                            ForEach(Array(section.items.enumerated()), id: \.offset) { index, skill in
                                InstalledSkillListRow(
                                    skill: skill,
                                    catalogItem: catalogItemsByName[skill.name],
                                    isLoadingDetail: viewModel.isLoadingSkillDetail,
                                    onInfo: {
                                        Task { await viewModel.loadSkillDetail(skill.name) }
                                    }
                                )

                                if index < section.items.count - 1 {
                                    Divider()
                                        .padding(.leading, 56)
                                }
                            }
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
    let isLoadingDetail: Bool
    let onInfo: () -> Void

    var body: some View {
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

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoadingDetail)
            .help("Skill details")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private struct ManualSkillInstallSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool
    @State private var repositoryInput = ""
    @FocusState private var isRepositoryFocused: Bool

    private var canInstall: Bool {
        SkillCatalogService.manualInstallCommand(repositoryInput: repositoryInput) != nil &&
        !viewModel.isInstallingManualSkill
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Install Skill")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Enter a GitHub repository. The app will install it globally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Repository")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("owner/repo", text: $repositoryInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($isRepositoryFocused)
                    .disabled(viewModel.isInstallingManualSkill)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isInstallingManualSkill)

                Button {
                    Task {
                        let success = await viewModel.installManualSkill(repositoryInput: repositoryInput)
                        if success {
                            isPresented = false
                        }
                    }
                } label: {
                    if viewModel.isInstallingManualSkill {
                        Text("Installing...")
                            .frame(width: 78)
                    } else {
                        Text("Install")
                            .frame(width: 78)
                    }
                }
                .buttonStyle(SkillPillButtonStyle(tone: .install, isDisabled: !canInstall))
                .keyboardShortcut(.defaultAction)
                .disabled(!canInstall)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear {
            isRepositoryFocused = true
        }
    }
}

struct SkillCatalogDetailSheet: View {
    let item: SkillCatalogItem
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
                        SkillDetailChip(title: item.category.title)
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
            return Color(red: 0.42, green: 0.13, blue: 0.16)
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

struct SkillDetailSheet: View {
    let detail: SkillDetailInfo
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(detail.isReady ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                Text(detail.name)
                    .font(.headline)

                Text(detail.status)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(detail.isReady ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(detail.isReady ? .green : .orange)
                    .cornerRadius(4)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !detail.description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(detail.description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        if !detail.source.isEmpty {
                            let source = SkillSourcePresentation(source: detail.source)
                            DetailRow(label: "Source", value: source.label)
                            DetailRow(label: "Raw", value: source.detail)
                        }
                        if !detail.path.isEmpty {
                            DetailRow(label: "Path", value: detail.path)
                        }
                    }

                    if !detail.requirements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requirements")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            ForEach(detail.requirements, id: \.self) { req in
                                HStack(spacing: 6) {
                                    Image(systemName: req.contains("\u{2713}") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(req.contains("\u{2713}") ? .green : .orange)
                                        .font(.caption)

                                    Text(req)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
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
