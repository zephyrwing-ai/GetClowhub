import SwiftUI

enum SettingsPageSection: String, CaseIterable, Identifiable {
    case profile
    case preferences
    case persona
    case status
    case gateway
    case apiKey
    case provider
    case budget
    case skills
    case models
    case channels
    case plugins
    case cron
    case logs

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: return "Profile"
        case .preferences: return "Preferences"
        case .persona: return "Persona"
        case .status: return "Status"
        case .gateway: return "Gateway"
        case .apiKey: return "API Key"
        case .provider: return "Provider"
        case .budget: return "Budget"
        case .skills: return "Skills"
        case .models: return "Models"
        case .channels: return "Channels"
        case .plugins: return "Plugins"
        case .cron: return "Cron"
        case .logs: return "Logs"
        }
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
        case .skills: return "bolt.fill"
        case .models: return "cube.fill"
        case .channels: return "bubble.left.and.bubble.right.fill"
        case .plugins: return "puzzlepiece.fill"
        case .cron: return "clock.badge"
        case .logs: return "doc.text.magnifyingglass"
        }
    }
}

struct ConfigTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var selectedSection: SettingsPageSection
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    let onOpenSkillDetail: (SkillDetailPresentationItem) -> Void
    let onOpenPluginDetail: (PluginDetailPresentationItem) -> Void
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif

    init(
        viewModel: DashboardViewModel,
        selectedSection: Binding<SettingsPageSection> = .constant(.profile),
        onOpenSkillDetail: @escaping (SkillDetailPresentationItem) -> Void = { _ in },
        onOpenPluginDetail: @escaping (PluginDetailPresentationItem) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self._selectedSection = selectedSection
        self.onOpenSkillDetail = onOpenSkillDetail
        self.onOpenPluginDetail = onOpenPluginDetail
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
                SettingsCard(title: "Profile", systemImage: "person.crop.circle") {
                    Text("Profile is available in signed builds.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #endif
            }
        case .preferences:
            settingsScroll {
                PreferencesSettingsCard(appAppearance: $appAppearance)
                    .environmentObject(languageManager)
            }
        case .persona:
            settingsScroll {
                PersonaSettingsCard(viewModel: viewModel)
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
                Text("API key management is available in signed builds.")
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
        case .skills:
            SkillsTabView(viewModel: viewModel, onOpenSkillDetail: onOpenSkillDetail)
        case .models:
            ModelsTabView(viewModel: viewModel)
        case .channels:
            ChannelsTabView(viewModel: viewModel)
        case .plugins:
            PluginsTabView(
                viewModel: viewModel,
                onOpenPluginDetail: onOpenPluginDetail
            )
        case .cron:
            CronTabView(viewModel: viewModel)
        case .logs:
            LogsTabView(viewModel: viewModel)
        }
    }

    private func settingsScroll<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        SmoothScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(selectedSection.title)
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
        ("Manage", [.skills, .models, .channels, .plugins, .cron, .logs])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 18, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)

                        ForEach(group.1) { section in
                            Button {
                                selectedSection = section
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: section.systemImage)
                                        .frame(width: 16)
                                    Text(section.title)
                                    Spacer()
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedSection == section ? Color.primary.opacity(0.10) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
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
        SettingsCard(title: "Profile", systemImage: "person.crop.circle") {
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
                    Button("Manage") {
                        openMemberAccount()
                    }
                    .buttonStyle(.bordered)
                    Button("Log Out") {
                        authManager.logout()
                    }
                    .buttonStyle(.bordered)
                }
            default:
                Text("Not Logged In")
                    .foregroundColor(.secondary)
                Button("Log In") {
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
    @Binding var appAppearance: String

    var body: some View {
        SettingsCard(title: "Preferences", systemImage: "slider.horizontal.3") {
            Picker("Language", selection: $languageManager.selectedLanguage) {
                ForEach(languageManager.supportedLanguages) { lang in
                    Text(lang.name).tag(lang.id)
                }
            }
            Picker("Appearance", selection: $appAppearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        }
    }
}

private struct PersonaSettingsCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        SettingsCard(title: "Persona", systemImage: "person.text.rectangle") {
            Text("Edit identity, memory, and persona files from one place.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Open Persona") {
                viewModel.selectedTab = .persona
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Gateway Settings Group

struct GatewaySettingsGroup: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gateway")
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
                Text("Gateway")
                    .font(.headline)
            }

            // Port
            HStack {
                Text("Port")
                    .frame(width: 120, alignment: .leading)

                TextField("18789", text: $viewModel.editedPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Text("Gateway listening port")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Auth Token
            HStack {
                Text("Auth Token")
                    .frame(width: 120, alignment: .leading)

                ZStack {
                    if showAuthToken {
                        TextField("Enter auth token", text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Enter auth token", text: $viewModel.editedAuthToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .frame(maxWidth: 300)

                Button(action: { showAuthToken.toggle() }) {
                    Image(systemName: showAuthToken ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(showAuthToken ? "Hide" : "Show")

                Text("Authentication token for gateway access")
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
            return "No models available"
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

                Text("GetClawHub Official Service")
                    .font(.headline)

                Text("Recommended")
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
                .help(isExpanded ? "Collapse" : "Expand")
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
                Text("Membership")
                    .frame(width: 120, alignment: .leading)

                Text(membership.level.displayName)
                    .fontWeight(.semibold)
                    .foregroundColor(badgeColor(membership.level))

                if let expiresAt = membership.expiresAt {
                    Text("(expires \(expiresAt.formatted(.dateTime.year().month().day())))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Manage") {
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
                Text("Budget")
                    .frame(width: 120, alignment: .leading)

                Text("¥\(String(format: "%.0f", membership.maxBudget)) / month")
                    .foregroundColor(.primary)

                Spacer()

                Text("\(membership.rpmLimit) RPM")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            availableModelsView

            // Base URL (readonly) — above API Key
            HStack {
                Text("API Base URL")
                    .frame(width: 120, alignment: .leading)

                TextField("", text: .constant(presetBaseUrl))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }

            // API Key (editable)
            if let _ = membershipManager.apiKeys.last(where: { $0.isActive }) {
                HStack {
                    Text("API Key")
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField("Enter API Key", text: $viewModel.editedGetClawHubApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API Key", text: $viewModel.editedGetClawHubApiKey)
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
                            Text("Sync")
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
            Text("Available Models")
                .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                if officialAvailableModels.isEmpty {
                    Text("No matching models found in the official provider preset.")
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
                                Text("\(officialAvailableModels.count) models available")
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
            Text("API Key")
                .frame(width: 120, alignment: .leading)

            Image(systemName: "key.slash")
                .foregroundColor(.orange)

            Text("No API Key yet")
                .font(.callout)
                .foregroundColor(.secondary)

            Spacer()

            Button("Generate Key") {
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

            Button("Sync") {
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
                    Text("Syncing membership info...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else if case .error(let msg) = membershipManager.syncState {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Sync failed: \(msg)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await membershipManager.syncProfile() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text("Loading membership info...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Sync") {
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
                Text("Log in to use GetClawHub AI service")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Button("Log In") {
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

                Text("Custom API Provider")
                    .font(.headline)

                #if REQUIRE_LOGIN
                Text("Use your own API Key")
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
                .help(isExpanded ? "Collapse" : "Expand")
            }

            if isExpanded {
                // Provider Picker
                HStack {
                    Text("Provider")
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
                    Text("API Base URL")
                        .frame(width: 120, alignment: .leading)

                    TextField("https://api.example.com/v1", text: $viewModel.editedModelBaseUrl)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                // API Key
                HStack {
                    Text("API Key")
                        .frame(width: 120, alignment: .leading)

                    ZStack {
                        if showApiKey {
                            TextField("Enter API key", text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter API key", text: $viewModel.editedModelApiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: { showApiKey.toggle() }) {
                        Image(systemName: showApiKey ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(showApiKey ? "Hide" : "Show")
                }

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
        .alert("Switch Provider", isPresented: $viewModel.showProviderSwitchConfirm) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelSwitchProvider()
            }
            Button("Switch", role: .destructive) {
                viewModel.confirmSwitchProvider()
            }
        } message: {
            Text("Switching provider will replace the current Base URL. API Key will be cleared. Continue?")
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
                Text("Reset")
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
                    Text("Save")
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
                    Text("Save & Restart")
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
            Text("Advanced")
                .font(.headline)

            HStack {
                Text("Edit the full configuration file directly for advanced settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    viewModel.openProviderPresetFile()
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Open Providers Preset")
                    }
                }
                .buttonStyle(.bordered)

                Button(action: {
                    viewModel.openConfigFile()
                }) {
                    HStack {
                        Image(systemName: "doc.text")
                        Text("Open Config File")
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

            Text("You have unsaved changes")
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
