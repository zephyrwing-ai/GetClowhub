import SwiftUI

@MainActor
private func localizedString(_ key: String) -> String {
    I18n.t(key, fallback: key)
}

@MainActor
private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: I18n.t(key, fallback: key), arguments: arguments)
}

enum SettingsPageSection: String, CaseIterable, Identifiable {
    case profile
    case preferences
    case persona
    case status
    case gateway
    case apiKey
    case provider
    case budget
    case models
    case channels
    case logs

    var id: Self { self }

    private var titleKey: String {
        switch self {
        case .profile: return "Profile"
        case .preferences: return "Preferences"
        case .persona: return "Persona"
        case .status: return "Status"
        case .gateway: return "Gateway"
        case .apiKey: return "API Key"
        case .provider: return "Provider"
        case .budget: return "Budget"
        case .models: return "Models"
        case .channels: return "Channels"
        case .logs: return "Logs"
        }
    }

    @MainActor
    func localizedTitle() -> String {
        localizedString(titleKey)
    }

    var systemImage: String {
        switch self {
        case .profile: return "person.crop.circle"
        case .preferences: return "slider.horizontal.3"
        case .persona: return "person.text.rectangle"
        case .status: return "chart.bar.fill"
        case .gateway: return "network"
        case .apiKey: return "key"
        case .provider: return "cpu"
        case .budget: return "dollarsign.gauge.chart.lefthalf.righthalf"
        case .models: return "cube.fill"
        case .channels: return "bubble.left.and.bubble.right.fill"
        case .logs: return "doc.text.magnifyingglass"
        }
    }
}

struct ConfigTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedSection: SettingsPageSection
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @AppStorage("appAccent") private var appAccent: String = "green"
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    init(
        viewModel: DashboardViewModel,
        selectedSection: Binding<SettingsPageSection> = .constant(.profile)
    ) {
        self.viewModel = viewModel
        self._selectedSection = selectedSection
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSectionSidebar(selectedSection: $selectedSection)
                .frame(width: 210)

            Divider()

            selectedSettingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.syncEditedFieldsFromSettings()
        }
    }

    @ViewBuilder
    private var selectedSettingsContent: some View {
        switch selectedSection {
        case .profile:
            settingsScroll {
                #if REQUIRE_LOGIN
                ProfileSettingsCard()
                    .environmentObject(authManager)
                    .environmentObject(membershipManager)
                #else
                SettingsCard(title: localizedString("Profile"), systemImage: "person.crop.circle") {
                    Text(localizedString("Profile is available in signed builds."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }
        case .preferences:
            settingsScroll {
                PreferencesSettingsCard(appAppearance: $appAppearance, appAccent: $appAccent)
                    .environmentObject(languageManager)
            }
        case .persona:
            settingsScroll {
                AgentPersonaSettingsList(viewModel: viewModel)
            }
        case .status:
            StatusTabView(viewModel: viewModel)
        case .gateway:
            settingsScroll {
                GatewayConfigSection(viewModel: viewModel)
                SaveButtonsSection(viewModel: viewModel)
                OpenConfigFileSection(viewModel: viewModel)
            }
        case .apiKey:
            settingsScroll {
                #if REQUIRE_LOGIN
                GetClawHubServiceSection(viewModel: viewModel)
                    .environmentObject(authManager)
                    .environmentObject(membershipManager)
                #else
                Text(localizedString("API key management is available in signed builds."))
                    .foregroundColor(.secondary)
                #endif
                SaveButtonsSection(viewModel: viewModel)
            }
        case .provider:
            settingsScroll {
                #if REQUIRE_LOGIN
                HStack(alignment: .top, spacing: 16) {
                    GetClawHubServiceSection(viewModel: viewModel)
                        .environmentObject(authManager)
                        .environmentObject(membershipManager)
                    ModelConfigSection(viewModel: viewModel)
                }
                #else
                ModelConfigSection(viewModel: viewModel)
                #endif
                SaveButtonsSection(viewModel: viewModel)
            }
        case .budget:
            BudgetTabView(viewModel: viewModel)
        case .models:
            ModelsTabView(viewModel: viewModel)
        case .channels:
            ChannelsTabView(viewModel: viewModel)
        case .logs:
            LogsTabView(viewModel: viewModel)
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        SmoothScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selectedSection.localizedTitle())
                    .font(.system(size: 24, weight: .semibold))

                content()
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsSectionSidebar: View {
    @Binding var selectedSection: SettingsPageSection

    private let groups: [(String, [SettingsPageSection])] = [
        ("Account", [.profile, .preferences, .persona]),
        ("System", [.status]),
        ("Configuration", [.gateway, .apiKey, .provider, .budget]),
        ("Advanced", [.models, .channels, .logs])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedString("Settings"))
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localizedString(group.0))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)

                        ForEach(group.1) { section in
                            SettingsSectionRow(
                                section: section,
                                isSelected: selectedSection == section
                            ) {
                                selectedSection = section
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.42))
    }
}

private struct SettingsSectionRow: View {
    let section: SettingsPageSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .frame(width: 16)
                Text(section.localizedTitle())
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.headline)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#if REQUIRE_LOGIN
private struct ProfileSettingsCard: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager

    var body: some View {
        SettingsCard(title: localizedString("Profile"), systemImage: "person.crop.circle") {
            switch authManager.state {
            case .loggedIn(let nickname):
                HStack {
                    Text(nickname)
                        .font(.system(size: 14, weight: .medium))
                    if let membership = membershipManager.membership {
                        Text("[\(membership.level.displayName)]")
                            .font(.caption.bold())
                            .foregroundColor(badgeColor(membership.level))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    Button(localizedString("Manage")) {
                        openMemberAccount()
                    }
                    .buttonStyle(.bordered)
                    Button(localizedString("Log Out")) {
                        authManager.logout()
                    }
                    .buttonStyle(.bordered)
                }
            default:
                Text(localizedString("Not Logged In"))
                    .foregroundColor(.secondary)
                Button(localizedString("Log In")) {
                    authManager.login()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func badgeColor(_ level: MembershipLevel) -> Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }

    private func openMemberAccount() {
        var urlString = "\(AuthConfig.baseURL)/member/account/"
        var params: [String] = []
        if let token = authManager.accessToken {
            params.append("token=\(token)")
        }
        if let uid = authManager.userId {
            params.append("user_id=\(uid)")
        }
        if !params.isEmpty {
            urlString += "?" + params.joined(separator: "&")
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif

private struct PreferencesSettingsCard: View {
    @EnvironmentObject var languageManager: LanguageManager
    @Environment(\.colorScheme) private var colorScheme
    @Binding var appAppearance: String
    @Binding var appAccent: String

    private var selectedAppearance: AppAppearanceMode {
        AppAppearanceMode.storedValue(appAppearance)
    }

    private var selectedAccent: AppAccentPalette {
        AppAccentPalette.storedValue(appAccent)
    }

    var body: some View {
        SettingsCard(title: localizedString("Preferences"), systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 18) {
                preferenceRow(title: localizedString("Language"), subtitle: localizedString("Use your preferred app language.")) {
                    Picker(localizedString("Language"), selection: $languageManager.selectedLanguage) {
                        ForEach(languageManager.supportedLanguages) { lang in
                            Text(lang.name).tag(lang.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    preferenceRow(title: localizedString("Appearance"), subtitle: localizedString("Choose a mode and preview how the workspace will feel.")) {
                        Picker(localizedString("Appearance"), selection: $appAppearance) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Label(localizedString(mode.title), systemImage: mode.systemImage)
                                    .tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 330)
                    }

                    AppearancePreview(
                        mode: selectedAppearance,
                        accent: selectedAccent,
                        systemScheme: colorScheme
                    )

                    preferenceRow(title: localizedString("Accent"), subtitle: localizedString("Applies to controls and selected states.")) {
                        HStack(spacing: 8) {
                            ForEach(AppAccentPalette.allCases) { accent in
                                Button {
                                    appAccent = accent.rawValue
                                } label: {
                                    AccentSwatch(accent: accent, isSelected: selectedAccent == accent)
                                }
                                .buttonStyle(.plain)
                                .help(localizedString(accent.title))
                            }
                        }
                    }
                }
            }
        }
    }

    private func preferenceRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 16)
            content()
        }
    }
}

private struct AccentSwatch: View {
    let accent: AppAccentPalette
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.color)
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 30, height: 30)
        .background(
            Circle()
                .stroke(isSelected ? accent.color.opacity(0.90) : Color.primary.opacity(0.10), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Circle())
    }
}

private struct AppearancePreview: View {
    let mode: AppAppearanceMode
    let accent: AppAccentPalette
    let systemScheme: ColorScheme

    private var isDark: Bool {
        mode.resolvesDark(using: systemScheme)
    }

    private var surfaceColor: Color {
        isDark ? Color(red: 0.13, green: 0.14, blue: 0.14) : Color(red: 0.96, green: 0.95, blue: 0.92)
    }

    private var sidebarColor: Color {
        isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.62)
    }

    private var panelColor: Color {
        isDark ? Color.white.opacity(0.09) : Color.white.opacity(0.86)
    }

    private var codeColor: Color {
        isDark ? Color.black.opacity(0.22) : Color.black.opacity(0.055)
    }

    private var textColor: Color {
        isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 8, height: 8)
                        Text("GetClawHub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textColor)
                }

                previewSidebarRow(icon: AppSystemSymbol.skills, title: localizedString("Skills"), active: true)
                previewSidebarRow(icon: "powerplug.portrait", title: localizedString("Plugins"), active: false)
                previewSidebarRow(icon: "gearshape", title: localizedString("Settings"), active: false)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 154)
            .background(sidebarColor)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedString(mode.title))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textColor)
                        Text(localizedFormat("Accent %@", localizedString(accent.title)))
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.58))
                    }
                    Spacer()
                    Text("Aa")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent.color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(accent.color.opacity(isDark ? 0.18 : 0.12), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.58))
                        .frame(width: 124, height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.26))
                        .frame(width: 190, height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(textColor.opacity(0.18))
                        .frame(width: 152, height: 6)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(panelColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(index == 0 ? accent.color.opacity(0.82) : codeColor)
                            .frame(height: 18)
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 150)
        .background(surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(isDark ? 0.12 : 0.08), lineWidth: 1)
        )
    }

    private func previewSidebarRow(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .foregroundColor(active ? textColor : textColor.opacity(0.62))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? accent.color.opacity(isDark ? 0.28 : 0.16) : Color.clear)
        )
    }
}

private struct AgentPersonaSettingsList: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var expandedAgentId: String?
    @State private var areMoreFilesExpanded = false

    private let optionalPersonaFiles: [PersonaFileDescriptor] = [
        PersonaFileDescriptor(fileName: "USER.md", icon: "person.fill"),
        PersonaFileDescriptor(fileName: "AGENTS.md", icon: "person.3.fill"),
        PersonaFileDescriptor(fileName: "BOOTSTRAP.md", icon: "power"),
        PersonaFileDescriptor(fileName: "HEARTBEAT.md", icon: "heart.text.clipboard"),
        PersonaFileDescriptor(fileName: "TOOLS.md", icon: "wrench.and.screwdriver")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.availableAgents) { agent in
                agentRow(agent)
            }
        }
        .onAppear {
            viewModel.loadAvailableAgents()
        }
    }

    private func agentRow(_ agent: AgentOption) -> some View {
        let isExpanded = expandedAgentId == agent.id
        let unsavedCount = unsavedFileCount(for: agent)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleAgent(agent)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(agent.name)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            Text(agent.id)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        HStack(spacing: 8) {
                            if !agent.model.isEmpty {
                                Label(agent.model, systemImage: "cpu")
                                    .lineLimit(1)
                            }

                            Label(compactWorkspacePath(for: agent), systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        if !agent.description.isEmpty {
                            Text(agent.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        Text(personaStatusText(for: agent))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if unsavedCount > 0 {
                            Text(localizedFormat("%lld unsaved", unsavedCount))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)

                agentPersonaEditors
                    .padding(14)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(isExpanded ? 0.88 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isExpanded ? Color.accentColor.opacity(0.42) : Color.gray.opacity(0.18), lineWidth: 1)
        )
    }

    private var agentPersonaEditors: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarkdownFileEditor(
                title: "IDENTITY.md",
                icon: "person.crop.circle",
                content: viewModel.settingsBinding(for: .identity),
                isDirty: viewModel.selectedAgentDetail?.identityDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .identity)
                },
                initiallyExpanded: false
            )

            MarkdownFileEditor(
                title: "SOUL.md",
                icon: "heart.fill",
                content: viewModel.settingsBinding(for: .soul),
                isDirty: viewModel.selectedAgentDetail?.soulDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .soul)
                },
                initiallyExpanded: false
            )

            MarkdownFileEditor(
                title: "MEMORY.md",
                icon: "brain.head.profile",
                content: viewModel.settingsBinding(for: .memory),
                isDirty: viewModel.selectedAgentDetail?.memoryDirty ?? false,
                onSave: {
                    viewModel.saveAgentPersonaFile(file: .memory)
                },
                initiallyExpanded: false
            )

            let visibleOptionalFiles = optionalPersonaFiles.filter { file in
                let fileName = file.fileName
                return viewModel.hasPersonaFile(fileName)
            }

            if !visibleOptionalFiles.isEmpty {
                DisclosureGroup(isExpanded: $areMoreFilesExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleOptionalFiles) { file in
                            let fileName = file.fileName
                            MarkdownFileEditor(
                                title: fileName,
                                icon: file.icon,
                                content: viewModel.settingsBindingByName(fileName),
                                isDirty: viewModel.isFileDirtyByName(fileName),
                                onSave: {
                                    viewModel.savePersonaFileByName(fileName)
                                },
                                initiallyExpanded: false
                            )
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.secondary)
                        Text(localizedString("More files"))
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(visibleOptionalFiles.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func toggleAgent(_ agent: AgentOption) {
        if expandedAgentId == agent.id {
            expandedAgentId = nil
            return
        }

        expandedAgentId = agent.id
        areMoreFilesExpanded = false
        viewModel.selectedAgentId = agent.id
        viewModel.loadSelectedAgentDetail()
    }

    private func personaStatusText(for agent: AgentOption) -> String {
        let workspace = DashboardViewModel.resolveAgentWorkspace(agent.id)
        let files = ["IDENTITY.md", "SOUL.md", "MEMORY.md"] + optionalPersonaFiles.map(\.fileName)
        let count = files.filter { fileName in
            FileManager.default.fileExists(atPath: (workspace as NSString).appendingPathComponent(fileName))
        }.count
        return localizedFormat("%lld files", count)
    }

    private func unsavedFileCount(for agent: AgentOption) -> Int {
        guard let detail = viewModel.selectedAgentDetail, detail.id == agent.id else {
            return 0
        }

        return [
            detail.identityDirty,
            detail.soulDirty,
            detail.memoryDirty,
            detail.userDirty,
            detail.agentsDirty,
            detail.bootstrapDirty,
            detail.heartbeatDirty,
            detail.toolsDirty
        ].filter { $0 }.count
    }

    private func compactWorkspacePath(for agent: AgentOption) -> String {
        let workspace = DashboardViewModel.resolveAgentWorkspace(agent.id)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return workspace.replacingOccurrences(of: home, with: "~")
    }
}

private struct PersonaFileDescriptor: Identifiable {
    let fileName: String
    let icon: String

    var id: String {
        fileName
    }
}

// MARK: - Gateway Settings Group

struct GatewaySettingsGroup: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localizedString("Gateway"))
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 16) {
                GatewayConfigSection(viewModel: viewModel, showsTitle: false)

                #if REQUIRE_LOGIN
                HStack(alignment: .top, spacing: 16) {
                    GetClawHubServiceSection(viewModel: viewModel)
                    ModelConfigSection(viewModel: viewModel)
                }
                #else
                ModelConfigSection(viewModel: viewModel)
                #endif
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
            )
        }
    }
}

// MARK: - Gateway Configuration (Red Border)

struct GatewayConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    var showsTitle: Bool = true
    @State private var showAuthToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsTitle {
                Text(localizedString("Gateway"))
                    .font(.headline)
            }

            // Port
            HStack {
                Text(localizedString("Port"))
                    .frame(width: 120, alignment: .leading)

                TextField("18789", text: $viewModel.editedPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Text(localizedString("Gateway listening port"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Auth Token
            HStack {
                Text(localizedString("Auth Token"))
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showAuthToken {
                        TextField(localizedString("Enter auth token"), text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField(localizedString("Enter auth token"), text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)

                Button(action: { showAuthToken.toggle() }) {
                    Image(systemName: showAuthToken ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showAuthToken ? localizedString("Hide") : localizedString("Show"))

                Text(localizedString("Authentication token for gateway access"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }
}

#if REQUIRE_LOGIN
// MARK: - GetClawHub Official Service (Blue Border + Radio)

struct GetClawHubServiceSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    @State private var showApiKey = false
    @State private var isExpanded = true
    @State private var areModelsExpanded = false

    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "getclawhub"
    }

    private var presetBaseUrl: String {
        viewModel.presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
    }

    private var officialPresetModels: [PresetModel] {
        viewModel.presetManager.findProvider(byKey: "getclawhub")?.models ?? []
    }

    private var activeOfficialModelAllowList: [String] {
        if let activeKey = membershipManager.apiKeys.last(where: { $0.isActive }), !activeKey.models.isEmpty {
            return activeKey.models
        }
        if let membership = membershipManager.membership, !membership.models.isEmpty {
            return membership.models
        }
        return []
    }

    private var officialAvailableModels: [PresetModel] {
        let allowList = activeOfficialModelAllowList
        guard !allowList.isEmpty else {
            return officialPresetModels
        }

        let allowedLowercased = Set(allowList.map { $0.lowercased() })
        return officialPresetModels.filter { allowedLowercased.contains($0.id.lowercased()) }
    }

    private var officialModelSummary: String {
        let names = officialAvailableModels.prefix(3).map { $0.name.isEmpty ? $0.id : $0.name }
        guard !names.isEmpty else {
            return localizedString("No models available")
        }
        let suffix = officialAvailableModels.count > names.count ? "..." : ""
        return names.joined(separator: ", ") + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Radio + Title + Expand/Collapse
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))
                    .onTapGesture { viewModel.editedActiveServiceSource = "getclawhub" }

                Text(localizedString("GetClawHub Official Service"))
                    .font(.headline)

                Text(localizedString("Recommended"))
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? localizedString("Collapse") : localizedString("Expand"))
            }

            if isExpanded {
                Spacer().frame(height: 16)

                if case .loggedIn = authManager.state {
                    if let membership = membershipManager.membership {
                        loggedInContent(membership)
                    } else {
                        syncingOrErrorView
                    }
                } else {
                    notLoggedInView
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.6 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.editedActiveServiceSource = "getclawhub" }
        .onAppear {
            // Initialize editable key from synced data (use latest key)
            if let activeKey = membershipManager.apiKeys.last(where: { $0.isActive }) {
                viewModel.editedGetClawHubApiKey = activeKey.fullKey
            }
        }
        .onChange(of: membershipManager.apiKeys) { newKeys in
            if let activeKey = newKeys.last(where: { $0.isActive }) {
                viewModel.editedGetClawHubApiKey = activeKey.fullKey
            }
        }
    }

    // MARK: - Logged In Content

    private func loggedInContent(_ membership: MembershipInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Membership
            HStack {
                Text(localizedString("Membership"))
                    .frame(width: 120, alignment: .leading)

                Text(membership.level.displayName)
                    .fontWeight(.semibold)
                    .foregroundColor(badgeColor(membership.level))

                if let expiresAt = membership.expiresAt {
                    Text(localizedFormat("(expires %@)", expiresAt.formatted(.dateTime.year().month().day())))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(localizedString("Manage")) {
                    var urlString = "\(AuthConfig.baseURL)/member/account/"
                    var params: [String] = []
                    if let token = authManager.accessToken {
                        params.append("token=\(token)")
                    }
                    if let uid = authManager.userId {
                        params.append("user_id=\(uid)")
                    }
                    if !params.isEmpty {
                        urlString += "?" + params.joined(separator: "&")
                    }
                    if let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Budget
            HStack {
                Text(localizedString("Budget"))
                    .frame(width: 120, alignment: .leading)

                Text(localizedFormat("%@ / month", "¥\(String(format: "%.0f", membership.maxBudget))"))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(membership.rpmLimit) RPM")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            availableModelsView

            // Base URL (readonly) — above API Key
            HStack {
                Text(localizedString("API Base URL"))
                    .frame(width: 120, alignment: .leading)

                TextField("", text: .constant(presetBaseUrl))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }

            // API Key (editable)
            if let _ = membershipManager.apiKeys.last(where: { $0.isActive }) {
                HStack {
                    Text(localizedString("API Key"))
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField(localizedString("Enter API Key"), text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(localizedString("Enter API Key"), text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        Task { await membershipManager.syncProfile() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(localizedString("Sync"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(membershipManager.syncState == .syncing)
                }
            } else {
                // No key guidance
                noKeyGuidanceView(membership)
            }

        }
    }

    private var availableModelsView: some View {
        HStack(alignment: .top) {
            Text(localizedString("Available Models"))
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if officialAvailableModels.isEmpty {
                    Text(localizedString("No matching models found in the official provider preset."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            areModelsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localizedFormat("%lld models available", officialAvailableModels.count))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(officialModelSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Image(systemName: areModelsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if areModelsExpanded {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(officialAvailableModels) { model in
                                    officialModelPill(model)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func officialModelPill(_ model: PresetModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(model.name.isEmpty ? model.id : model.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if model.input.contains("image") {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }

                if model.reasoning {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                }
            }

            Text("\(formatTokenCount(model.contextWindow)) ctx")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func formatTokenCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        }
        if value >= 1_000 {
            return "\(value / 1_000)K"
        }
        return "\(value)"
    }

    // MARK: - No Key Guidance

    private func noKeyGuidanceView(_ membership: MembershipInfo) -> some View {
        HStack {
            Text(localizedString("API Key"))
                .frame(width: 120, alignment: .leading)

            Image(systemName: "key.slash")
                .foregroundColor(.orange)

            Text(localizedString("No API Key yet"))
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            Button(localizedString("Generate Key")) {
                var urlString = "\(AuthConfig.baseURL)/member/api-keys/"
                if let uid = authManager.userId {
                    urlString += "?user_id=\(uid)"
                }
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(localizedString("Sync")) {
                Task { await membershipManager.syncProfile() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(membershipManager.syncState == .syncing)
        }
    }

    // MARK: - Syncing / Error

    private var syncingOrErrorView: some View {
        Group {
            if membershipManager.syncState == .syncing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizedString("Syncing membership info..."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if case .error(let msg) = membershipManager.syncState {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(localizedFormat("Sync failed: %@", msg))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(localizedString("Retry")) {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text(localizedString("Loading membership info..."))
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(localizedString("Sync")) {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Not Logged In

    private var notLoggedInView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .foregroundColor(.secondary)
                Text(localizedString("Log in to use GetClawHub AI service"))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Button(localizedString("Log In")) {
                authManager.login()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func badgeColor(_ level: MembershipLevel) -> Color {
        switch level {
        case .free: return .gray
        case .pro: return .blue
        case .max: return .purple
        }
    }
}
#endif

// MARK: - Custom API Provider (Blue Border + Radio)

struct ModelConfigSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showApiKey = false
    @State private var isExpanded = true

    #if REQUIRE_LOGIN
    private var isSelected: Bool {
        viewModel.editedActiveServiceSource == "custom"
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title row
            HStack(spacing: 8) {
                #if REQUIRE_LOGIN
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.system(size: 16))
                    .onTapGesture { viewModel.editedActiveServiceSource = "custom" }
                #endif

                Text(localizedString("Custom API Provider"))
                    .font(.headline)

                #if REQUIRE_LOGIN
                Text(localizedString("Use your own API Key"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif

                Spacer()

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? localizedString("Collapse") : localizedString("Expand"))
            }

            if isExpanded {
                // Provider Picker
                HStack {
                    Text(localizedString("Provider"))
                        .frame(width: 120, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { viewModel.editedSelectedProviderKey },
                        set: { newKey in
                            viewModel.requestSwitchProvider(to: newKey)
                        }
                    )) {
                        ForEach(viewModel.availableProviders) { provider in
                            Text(provider.displayName).tag(provider.key)
                        }
                    }
                    .frame(width: 200)
                }

                // Base URL
                HStack {
                    Text(localizedString("API Base URL"))
                        .frame(width: 120, alignment: .leading)

                    TextField("https://api.example.com/v1", text: $viewModel.editedModelBaseUrl)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                // API Key
                HStack {
                    Text(localizedString("API Key"))
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField(localizedString("Enter API key"), text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField(localizedString("Enter API key"), text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(showApiKey ? localizedString("Hide") : localizedString("Show"))
                }

                customProviderModelsView

            } // end isExpanded
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        #if REQUIRE_LOGIN
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(isSelected ? 0.6 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.editedActiveServiceSource = "custom" }
        #endif
        .alert(localizedString("Switch Provider"), isPresented: $viewModel.showProviderSwitchConfirm) {
            Button(localizedString("Cancel"), role: .cancel) {
                viewModel.cancelSwitchProvider()
            }
            Button(localizedString("Switch"), role: .destructive) {
                viewModel.confirmSwitchProvider()
            }
        } message: {
            Text(localizedString("Switching provider will replace the current Base URL. API Key will be cleared. Continue?"))
        }
    }

    private var customProviderModelsView: some View {
        HStack(alignment: .top) {
            Text(localizedString("Models"))
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localizedFormat("%lld models configured", viewModel.editedConfiguredModels.count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button {
                        Task { await viewModel.fetchModelsForSelectedProvider() }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isFetchingProviderModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(localizedString("Fetch Models"))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isFetchingProviderModels || viewModel.editedModelBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !viewModel.editedConfiguredModels.isEmpty {
                    Text(viewModel.editedConfiguredModels.prefix(4).map { $0.name.isEmpty ? $0.id : $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(localizedString("Fetch models from this provider or add them before saving."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !viewModel.providerModelFetchMessage.isEmpty {
                    Text(viewModel.providerModelFetchMessage)
                        .font(.caption)
                        .foregroundColor(viewModel.providerModelFetchMessage.hasPrefix("Fetched") ? .secondary : .red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Save Buttons

struct SaveButtonsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    #if REQUIRE_LOGIN
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    private var isApiKeyMissing: Bool {
        #if REQUIRE_LOGIN
        if viewModel.editedActiveServiceSource == "getclawhub" {
            // GetClawHub selected: check both the edited key field AND whether user has any active key
            let editedKeyEmpty = viewModel.editedGetClawHubApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let noActiveKey = !membershipManager.apiKeys.contains(where: { $0.isActive })
            return editedKeyEmpty || noActiveKey
        } else {
            return viewModel.editedModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        #else
        return viewModel.editedModelApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                viewModel.resetConfiguration()
            }) {
                Text(localizedString("Reset"))
                    .frame(width: 100)
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: {
                Task {
                    await viewModel.saveConfiguration()
                }
            }) {
                HStack {
                    Image(systemName: "checkmark")
                    Text(localizedString("Save"))
                }
                .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPerformingAction || isApiKeyMissing)

            Button(action: {
                Task {
                    await viewModel.saveAndRestartService()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text(localizedString("Save & Restart"))
                }
                .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isPerformingAction || isApiKeyMissing)
        }
    }
}

// MARK: - Advanced (Gray Border)

struct OpenConfigFileSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizedString("Advanced"))
                .font(.headline)

            HStack {
                Text(localizedString("Edit the full configuration file directly for advanced settings."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    viewModel.openProviderPresetFile()
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text(localizedString("Open Providers Preset"))
                    }
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.openConfigFile()
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text(localizedString("Open Config File"))
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Unsaved Changes Warning

struct UnsavedChangesWarning: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(localizedString("You have unsaved changes"))
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct ConfigTabPreviewWrapper: View {
    var body: some View {
        ConfigTabView(
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
    }
}

#Preview {
    ConfigTabPreviewWrapper()
        .frame(width: 700, height: 600)
}
