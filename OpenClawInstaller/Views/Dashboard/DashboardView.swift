import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import MarkdownUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGlobalSessionSearchPresented = false
    @State private var globalSessionSearchText: String = ""
    @FocusState private var isGlobalSessionSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTab: $viewModel.selectedTab,
                viewModel: viewModel,
                onOpenGlobalSessionSearch: openGlobalSessionSearch
            )
        } detail: {
            DetailContentView(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(colorSchemeForAppearance)
        .background(TitlebarSeparatorSuppressor())
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .overlay(alignment: .top) {
            if viewModel.showSuccess {
                SuccessToast(message: viewModel.successMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isGlobalSessionSearchPresented {
                globalSessionSearchOverlay
            }
        }
        .animation(.easeInOut, value: viewModel.showSuccess)
        .animation(.easeInOut(duration: 0.16), value: isGlobalSessionSearchPresented)
        .onAppear {
            viewModel.openclawService.startMonitoring()
            Task {
                await viewModel.openclawService.fetchVersion()
            }
        }
        .onDisappear {
            viewModel.openclawService.stopMonitoring()
        }
        .sheet(isPresented: $viewModel.showDiagnostics) {
            DiagnosticsSheet(report: viewModel.diagnosticReport, isPresented: $viewModel.showDiagnostics)
        }
    }

    private var isDark: Bool {
        if appAppearance == "dark" { return true }
        if appAppearance == "light" { return false }
        return colorScheme == .dark
    }

    private var colorSchemeForAppearance: ColorScheme? {
        switch appAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func openGlobalSessionSearch() {
        globalSessionSearchText = ""
        isGlobalSessionSearchPresented = true
        DispatchQueue.main.async {
            isGlobalSessionSearchFocused = true
        }
    }

    private var globalSearchResults: [ChatSessionMetadata] {
        Array(viewModel.chatSessionStore
            .searchSessions(query: globalSessionSearchText)
            .prefix(12))
    }

    private var globalSessionSearchOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(700, max(320, proxy.size.width - 64))

            ZStack {
                Color.black.opacity(isDark ? 0.28 : 0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isGlobalSessionSearchPresented = false
                        isGlobalSessionSearchFocused = false
                    }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField(String(localized: "Search chats", bundle: languageManager.localizedBundle), text: $globalSessionSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 20, weight: .regular))
                            .focused($isGlobalSessionSearchFocused)
                        if !globalSessionSearchText.isEmpty {
                            Button {
                                globalSessionSearchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                    Text(globalSessionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? String(localized: "Recent chats", bundle: languageManager.localizedBundle)
                         : String(localized: "Search results", bundle: languageManager.localizedBundle))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)

                    if globalSearchResults.isEmpty {
                        Text(String(localized: "No matches", bundle: languageManager.localizedBundle))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 18)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(globalSearchResults.enumerated()), id: \.element.id) { index, meta in
                                    globalSessionSearchRow(meta: meta, shortcutIndex: index + 1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.bottom, 12)
                        }
                        .frame(maxHeight: 420)
                    }
                }
                .frame(width: panelWidth, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.10 : 0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.36 : 0.18), radius: 38, x: 0, y: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    private func globalSessionSearchRow(meta: ChatSessionMetadata, shortcutIndex: Int) -> some View {
        Button {
            viewModel.switchSessionGlobally(to: meta.id)
            viewModel.selectedTab = .chat
            isGlobalSessionSearchPresented = false
            isGlobalSessionSearchFocused = false
        } label: {
            HStack(spacing: 12) {
                Text(meta.title.isEmpty ? String(localized: "New chat", bundle: languageManager.localizedBundle) : meta.title)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                Text(agentName(for: meta.agentId))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.42))
            )
        }
        .buttonStyle(.plain)
    }

    private func agentName(for agentId: String) -> String {
        viewModel.availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
    }
}

private struct TitlebarSeparatorSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.configure(window: nsView.window)
        }
    }

    private static func configure(window: NSWindow?) {
        window?.titlebarSeparatorStyle = .none
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: DashboardViewModel.DashboardTab
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenGlobalSessionSearch: () -> Void
    @EnvironmentObject var sparkleUpdater: SparkleUpdater
    @EnvironmentObject var languageManager: LanguageManager
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    // Agent context menu state
    @State private var showCreateAgentSheet = false
    @StateObject private var createAgentVM: SubAgentsViewModel
    @State private var deleteAgentConfirmId: String?

    // Chat session management state
    @State private var sessionRenameId: UUID?
    @State private var sessionRenameDraft: String = ""
    @State private var confirmingDeleteSessionId: UUID?

    // Marketplace state
    @State private var marketplaceSearchText = ""
    @State private var expandedDivisions: Set<String> = []
    @State private var expandedAgentDivisions: Set<String> = []
    @State private var expandedAgentIds: Set<String> = []
    @State private var hoveredAgentId: String?

    init(
        selectedTab: Binding<DashboardViewModel.DashboardTab>,
        viewModel: DashboardViewModel,
        onOpenGlobalSessionSearch: @escaping () -> Void
    ) {
        self._selectedTab = selectedTab
        self.viewModel = viewModel
        self.onOpenGlobalSessionSearch = onOpenGlobalSessionSearch
        self._createAgentVM = StateObject(wrappedValue: SubAgentsViewModel(openclawService: viewModel.openclawService))
    }

    private var isDark: Bool {
        if appAppearance == "dark" { return true }
        if appAppearance == "light" { return false }
        return colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarTopHeader
            sidebarMainList
            Divider()
            sidebarBottomBar
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        // Chat session rename — bound to sessionRenameId; clearing it dismisses
        .alert("Rename Session",
               isPresented: Binding(
                   get: { sessionRenameId != nil },
                   set: { if !$0 { sessionRenameId = nil } }
               ),
               actions: {
                   TextField("Session name", text: $sessionRenameDraft)
                   Button("Save") {
                       if let id = sessionRenameId {
                           viewModel.renameSession(id, to: sessionRenameDraft)
                       }
                       sessionRenameId = nil
                   }
                   Button("Cancel", role: .cancel) {
                       sessionRenameId = nil
                   }
               })
    }

    // MARK: - Sidebar Top Header

    /// Top of the sidebar — text-only app label. NavigationSplitView's own
    /// toggle in the window toolbar handles sidebar collapse.
    private var sidebarTopHeader: some View {
        HStack {
            Text("GetClawHub")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Sidebar Main List (the new unified list)

    /// Primary app sidebar. Rows use custom buttons so selected state can
    /// stay quiet gray instead of macOS' blue list selection.
    private var sidebarMainList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ServiceStatusBadge(viewModel: viewModel)
                    .padding(.bottom, 8)

                Button {
                    viewModel.createNewSession()
                    selectedTab = .chat
                } label: {
                    sidebarRowContent(title: String(localized: "New chat", bundle: languageManager.localizedBundle), systemImage: "plus.circle")
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selectedTab == .chat
                                    && viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId] == nil
                                    ? Color(NSColor.controlBackgroundColor)
                                    : Color.clear
                                )
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onOpenGlobalSessionSearch()
                } label: {
                    sidebarRowContent(title: String(localized: "Search chats", bundle: languageManager.localizedBundle), systemImage: "magnifyingglass")
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Search chats", bundle: languageManager.localizedBundle))

                navRow(.skills, title: String(localized: "Skills", bundle: languageManager.localizedBundle), systemImage: "bolt.fill")
                navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "puzzlepiece.fill")
                navRow(.tasksLogs, title: String(localized: "Automation", bundle: languageManager.localizedBundle), systemImage: "checklist")
                navRow(.market, title: String(localized: "Market", bundle: languageManager.localizedBundle), systemImage: "storefront")

                agentSectionContent

                Spacer(minLength: 12)

                navRow(.status, title: String(localized: "Status", bundle: languageManager.localizedBundle), systemImage: "chart.bar.fill")
                navRow(.budget, title: String(localized: "Budget", bundle: languageManager.localizedBundle), systemImage: "dollarsign.gauge.chart.lefthalf.righthalf")
                #if REQUIRE_LOGIN
                navRow(.billing, title: String(localized: "Billing", bundle: languageManager.localizedBundle), systemImage: "creditcard.fill")
                #endif
                navRow(.config, title: String(localized: "Settings", bundle: languageManager.localizedBundle), systemImage: "gearshape")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func navRow(_ tab: DashboardViewModel.DashboardTab, title: String, systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            sidebarRowContent(title: title, systemImage: systemImage)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedTab == tab ? Color(NSColor.controlBackgroundColor) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func sidebarRowContent(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
                .lineLimit(1)
            Spacer()
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: - Sessions Section Content (extracted so it stays readable)

    @ViewBuilder
    private var sessionsSectionContent: some View {
        let agentSessions = viewModel.sessionsByAgent[viewModel.selectedAgentId] ?? []
        let activeId = viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId]

        if agentSessions.isEmpty {
            Text(String(localized: "No sessions yet", bundle: languageManager.localizedBundle))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
        } else {
            ForEach(agentSessions) { meta in
                ChatSessionRow(
                    meta: meta,
                    isActive: activeId == meta.id,
                    isExecuting: viewModel.hasInflightTask(inSession: meta.id),
                    isDeleteConfirming: confirmingDeleteSessionId == meta.id,
                    onDeleteIntent: {
                        confirmingDeleteSessionId = meta.id
                    },
                    onDeleteConfirm: {
                        viewModel.deleteSession(meta.id)
                        confirmingDeleteSessionId = nil
                    }
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(activeId == meta.id && selectedTab == .chat ? Color(NSColor.controlBackgroundColor) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    confirmingDeleteSessionId = nil
                    viewModel.switchSession(to: meta.id)
                    selectedTab = .chat
                }
                .contextMenu {
                    Button {
                        sessionRenameId = meta.id
                        sessionRenameDraft = meta.title
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        viewModel.togglePinSession(meta.id)
                    } label: {
                        Label(meta.isPinned ? "Unpin" : "Pin",
                              systemImage: meta.isPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        viewModel.exportSession(meta.id)
                    } label: {
                        Label("Export…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button {
                        viewModel.archiveSession(meta.id)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        confirmingDeleteSessionId = meta.id
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Agent Section Content

    @ViewBuilder
    private var agentSectionContent: some View {
        let visibleAgents = viewModel.availableAgents.filter {
            !DashboardViewModel.internalAgentIds.contains($0.id)
        }

        HStack(spacing: 6) {
            Text(String(localized: "Agent", bundle: languageManager.localizedBundle))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                showCreateAgentSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(String(localized: "New Agent", bundle: languageManager.localizedBundle))
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)

        if visibleAgents.isEmpty {
            Text(String(localized: "No agents yet", bundle: languageManager.localizedBundle))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
        } else {
            ForEach(visibleAgents) { agent in
                agentSidebarRow(agent)
                if expandedAgentIds.contains(agent.id)
                    && viewModel.selectedAgentId == agent.id
                    && selectedTab == .chat {
                    VStack(alignment: .leading, spacing: 0) {
                        sessionsSectionContent
                    }
                        .padding(.leading, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .clipped()
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: expandedAgentIds)
        }
    }

    // MARK: - Sidebar Bottom Bar (version + theme toggle)

    private var sidebarBottomBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line — brand + version side by side
            HStack(spacing: 8) {
                Text("GetClawHub")
                    .font(.system(size: 11, weight: .semibold))
                Text("v\(sparkleUpdater.currentVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Bottom line — update + theme. Help, account, language, and
            // logout now live in Settings.
            HStack(spacing: 14) {
                // Update — pill goes green when an update is available
                if sparkleUpdater.updateAvailable {
                    Button {
                        sparkleUpdater.checkForUpdates()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10))
                            Text("v\(sparkleUpdater.latestVersion)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Update to v\(sparkleUpdater.latestVersion)")
                } else {
                    Button {
                        Task { await sparkleUpdater.checkLatestVersion() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text(sparkleUpdater.checkSucceeded ? "Latest" : "Update")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(sparkleUpdater.checkSucceeded ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Check for Updates")
                }

                Spacer()

                // Theme toggle on the trailing edge (Q2=c)
                Button {
                    appAppearance = isDark ? "light" : "dark"
                } label: {
                    Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Agents List

    /// Agents grouped by division for the sidebar
    private var agentsByDivisionGrouped: [(division: String, agents: [AgentOption])] {
        let grouped = Dictionary(grouping: viewModel.availableAgents.filter {
            $0.id != "commander" && $0.id != "main" && !$0.division.isEmpty
        }) { $0.division }

        // Sort: Custom first, then alphabetical
        let divisionOrder = ["Custom"] + Self.divisionEmoji.keys.sorted()
        return divisionOrder.compactMap { div in
            guard let agents = grouped[div], !agents.isEmpty else { return nil }
            return (division: div, agents: agents)
        }
    }

    private func agentRowWithContextMenu(_ agent: AgentOption) -> some View {
        let isExecuting = viewModel.isAgentExecuting(agent.id)
        let isHovering = hoveredAgentId == agent.id
        return AgentListRow(
            agent: agent,
            isActive: viewModel.selectedAgentId == agent.id,
            isExecuting: isExecuting,
            isHovering: isHovering,
            onCreateSession: { createSession(for: agent) }
        )
            .tag(agent.id)
            .contextMenu {
                Button {
                    showCreateAgentSheet = true
                } label: {
                    Label("New Agent", systemImage: "plus.bubble")
                }

                if agent.id != "main" && agent.id != "commander" {
                    Divider()
                    Button(role: .destructive) {
                        deleteAgentConfirmId = agent.id
                    } label: {
                        Label("Remove Agent", systemImage: "trash")
                    }
                }
            }
    }

    private func agentSidebarRow(_ agent: AgentOption) -> some View {
        let isActive = viewModel.selectedAgentId == agent.id && selectedTab == .chat
        let isHovering = hoveredAgentId == agent.id

        return agentRowWithContextMenu(agent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive || isHovering
                          ? Color(NSColor.controlBackgroundColor)
                          : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                toggleAgentSelection(agent)
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    if hovering {
                        hoveredAgentId = agent.id
                    } else if hoveredAgentId == agent.id {
                        hoveredAgentId = nil
                    }
                }
            }
    }

    private func toggleAgentSelection(_ agent: AgentOption) {
        confirmingDeleteSessionId = nil
        let repeatsCurrentAgent = viewModel.selectedAgentId == agent.id && selectedTab == .chat

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if repeatsCurrentAgent {
                if expandedAgentIds.contains(agent.id) {
                    expandedAgentIds.remove(agent.id)
                } else {
                    expandedAgentIds.insert(agent.id)
                }
            }

            viewModel.selectedAgentId = agent.id
            selectedTab = .chat
        }
    }

    private func createSession(for agent: AgentOption) {
        confirmingDeleteSessionId = nil
        viewModel.createNewSession(forAgent: agent.id)
        selectedTab = .chat
    }

    private var agentsList: some View {
        // Wrap the selection binding so we also force-switch to the
        // chat tab when the user picks an agent from 我的团队. Without
        // this, if the user was on .status (or any non-per-agent tab),
        // clicking a team member visibly does nothing — only
        // `selectedAgentId` updates and the right side doesn't reflect
        // the agent context. The expectation is "I clicked a team
        // member → take me to that team member's conversation".
        List(selection: Binding<String>(
            get: { viewModel.selectedAgentId },
            set: { newId in
                viewModel.selectedAgentId = newId
                viewModel.selectedTab = .chat
            }
        )) {
            // Commander — pinned at top, standalone
            if let commander = viewModel.availableAgents.first(where: { $0.id == "commander" }) {
                agentRowWithContextMenu(commander)
            }

            // main — pinned after commander
            if let main = viewModel.availableAgents.first(where: { $0.id == "main" }) {
                agentRowWithContextMenu(main)
            }

            // Grouped by division
            ForEach(agentsByDivisionGrouped, id: \.division) { group in
                let emoji = Self.divisionEmoji[group.division] ?? "📁"
                DisclosureGroup(
                    isExpanded: Binding<Bool>(
                        get: { expandedAgentDivisions.contains(group.division) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedAgentDivisions.insert(group.division)
                            } else {
                                expandedAgentDivisions.remove(group.division)
                            }
                        }
                    )
                ) {
                    ForEach(group.agents) { agent in
                        agentRowWithContextMenu(agent)
                    }
                } label: {
                    Text(verbatim: "\(emoji) \(group.division) (\(group.agents.count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .id("agent-division-\(group.division)")
            }
            .animation(nil, value: viewModel.availableAgents)
        }
        .listStyle(.sidebar)
        .onAppear {
            viewModel.loadAvailableAgents()
        }
        .alert("Remove Agent", isPresented: Binding<Bool>(
            get: { deleteAgentConfirmId != nil },
            set: { if !$0 { deleteAgentConfirmId = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let agentId = deleteAgentConfirmId {
                    let wasSelected = viewModel.selectedAgentId == agentId
                    Task {
                        await createAgentVM.deleteAgent(agentId: agentId)
                        await MainActor.run {
                            viewModel.loadAvailableAgents()
                            if wasSelected {
                                viewModel.selectedAgentId = "main"
                            }
                        }
                    }
                }
                deleteAgentConfirmId = nil
            }
            Button("Cancel", role: .cancel) {
                deleteAgentConfirmId = nil
            }
        } message: {
            if let agentId = deleteAgentConfirmId,
               let agent = viewModel.availableAgents.first(where: { $0.id == agentId }) {
                Text("Are you sure you want to remove \"\(agent.name)\"? This will delete the agent and its workspace.")
            }
        }
        .sheet(isPresented: $showCreateAgentSheet) {
            CreateAgentSheet(
                viewModel: createAgentVM,
                isPresented: $showCreateAgentSheet,
                onCreatedWithId: { agentId in
                    viewModel.loadAvailableAgents()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.selectedAgentId = agentId
                    }
                }
            )
        }
    }

    // MARK: - Marketplace List

    private static let divisionEmoji: [String: String] = [
        "Academic": "🎓",
        "Design": "🎨",
        "Engineering": "⚙️",
        "Game Development": "🎮",
        "Marketing": "📣",
        "Paid Media": "💰",
        "Product": "📦",
        "Project Management": "📋",
        "Sales": "🤝",
        "Spatial Computing": "🥽",
        "Specialized": "⭐",
        "Support": "🛟",
        "Testing": "🧪",
    ]

    private var filteredMarketplaceAgents: [MarketplaceAgent] {
        MarketplaceCatalog.shared.search(query: marketplaceSearchText)
    }

    /// Agents grouped by division, used when not searching
    private var agentsByDivision: [(division: String, agents: [MarketplaceAgent])] {
        let catalog = MarketplaceCatalog.shared
        return catalog.divisions.compactMap { div in
            let agents = catalog.search(query: "", division: div)
            guard !agents.isEmpty else { return nil }
            return (division: div, agents: agents)
        }
    }

    private var marketplaceList: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search agents...", text: $marketplaceSearchText)
                    .textFieldStyle(.plain)
                if !marketplaceSearchText.isEmpty {
                    Button {
                        marketplaceSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Agent list - tree view or flat search results.
            //
            // Selecting an agent has to do TWO things:
            //   1. Set `selectedMarketplaceAgent` — the .market tab's
            //      branch keys off this to swap from MarketplaceOverview
            //      to MarketplaceDetailView for the chosen agent.
            //   2. Set `selectedTab = .market` — without this, the user
            //      might be on the .chat tab (or any other), and the
            //      main content area keeps showing chat while only the
            //      sidebar reflects the marketplace selection. The
            //      previous binding only did (1), so clicking an agent
            //      in the sidebar visibly highlighted it but the right
            //      side stayed on the previous tab.
            List(selection: Binding<MarketplaceAgent?>(
                get: { viewModel.selectedMarketplaceAgent },
                set: { newAgent in
                    viewModel.selectedMarketplaceAgent = newAgent
                    if newAgent != nil {
                        viewModel.selectedTab = .market
                    }
                }
            )) {
                if marketplaceSearchText.isEmpty {
                    // Tree view grouped by division
                    ForEach(agentsByDivision, id: \.division) { group in
                        let emoji = Self.divisionEmoji[group.division] ?? "📁"
                        DisclosureGroup(
                            isExpanded: Binding<Bool>(
                                get: { expandedDivisions.contains(group.division) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedDivisions.insert(group.division)
                                    } else {
                                        expandedDivisions.remove(group.division)
                                    }
                                }
                            )
                        ) {
                            ForEach(group.agents) { agent in
                                MarketplaceAgentRow(agent: agent)
                                    .tag(agent)
                            }
                        } label: {
                            Text(verbatim: "\(emoji) \(group.division) (\(group.agents.count))")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                } else {
                    // Flat search results
                    ForEach(filteredMarketplaceAgents) { agent in
                        MarketplaceAgentRow(agent: agent)
                            .tag(agent)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

private struct AgentListRow: View {
    let agent: AgentOption
    let isActive: Bool
    let isExecuting: Bool
    let isHovering: Bool
    let onCreateSession: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentAvatarImage(size: 24)

            Text(agent.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .lineLimit(1)

            if isHovering {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if isHovering {
                Button(action: onCreateSession) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                        }
                }
                .buttonStyle(.plain)
                .help(String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(isExecuting
              ? String(localized: "Task running", bundle: LanguageManager.shared.localizedBundle)
              : agent.name)
    }
}

private struct AgentAvatarImage: View {
    let size: CGFloat

    var body: some View {
        Image("AgentAvatar")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Pulsing Dot (green breathing animation)

// MARK: - Marketplace Agent Row

private struct MarketplaceAgentRow: View {
    let agent: MarketplaceAgent

    var body: some View {
        HStack(spacing: 10) {
            Text(agent.emoji)
                .font(.system(size: 22))

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if !agent.description.isEmpty {
                    Text(agent.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Text(agent.division)
                    .font(.system(size: 10))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Service Status Badge

struct ServiceStatusBadge: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.openclawService.status.rawValue)
                    .font(.headline)

                if !viewModel.openclawService.version.isEmpty {
                    Text("v\(viewModel.openclawService.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: SwiftUI.Color {
        switch viewModel.openclawService.status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .error: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Detail Content

private struct WorkspaceSidebarController {
    var isExpanded: Binding<Bool>
    var hasEditor: Bool
    var toggle: () -> Void
}

private struct WorkspaceSidebarControllerKey: EnvironmentKey {
    static let defaultValue = WorkspaceSidebarController(
        isExpanded: .constant(false),
        hasEditor: false,
        toggle: {}
    )
}

private extension EnvironmentValues {
    var workspaceSidebarController: WorkspaceSidebarController {
        get { self[WorkspaceSidebarControllerKey.self] }
        set { self[WorkspaceSidebarControllerKey.self] = newValue }
    }
}

struct DetailContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var collabPanelWidth: CGFloat = 320
    @State private var dragStartWidth: CGFloat = 320
    @State private var workspaceSidebarExpanded = false
    @State private var workspaceEditingFilePath: String?
    @State private var workspaceEditingFileDirty = false
    @State private var workspaceEditorFullscreen = false

    private let collabPanelMinWidth: CGFloat = 220
    private let collabPanelMaxWidth: CGFloat = 500
    private let collabCollapsedWidth: CGFloat = 24
    private static let workspaceLayoutMetrics = OutputsSidebarLayoutMetrics()

    private var isWorkspaceSidebarExpanded: Bool {
        workspaceSidebarExpanded || workspaceEditingFilePath != nil
    }

    var body: some View {
        GeometryReader { geometry in
            let workspaceWidth = Self.workspaceLayoutMetrics.sidebarWidth(
                isExpanded: isWorkspaceSidebarExpanded,
                hasEditor: workspaceEditingFilePath != nil,
                availableWidth: geometry.size.width
            )

            HStack(spacing: 0) {
                // Collab panel (left column)
                if viewModel.showCollabPanel {
                    if viewModel.collabPanelCollapsed {
                        // Collapsed strip
                        collabCollapsedStrip
                    } else {
                        // Panel + drag handle
                        collabPanelContent
                            .frame(width: collabPanelWidth)
                        collabDragHandle
                    }
                }

                // Main detail content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if workspaceWidth > 0 {
                    workspaceSidebarColumn(width: workspaceWidth)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceSidebarExpanded)
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: workspaceEditingFilePath)
        .onChange(of: viewModel.selectedTab) { newTab in
            // Only reload agents when entering chat tab, but preserve current agent selection
            if newTab == .chat {
                let currentAgent = viewModel.selectedAgentId
                let msgCount = viewModel.chatMessages.count
                print("[TAB_CHANGE] Switching to Chat: currentAgent=\(currentAgent), msgCount=\(msgCount)")
                viewModel.loadAvailableAgents()
                // Restore the previously selected agent if it still exists
                if viewModel.availableAgents.contains(where: { $0.id == currentAgent }) {
                    viewModel.selectedAgentId = currentAgent
                    print("[TAB_CHANGE] Restored agent: \(currentAgent), newMsgCount=\(viewModel.chatMessages.count)")
                }
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack {
            // ChatView stays alive — hidden when not active to preserve WKWebView instances.
            // sidebarMode is being phased out; selectedTab == .chat is the canonical signal now.
            let activeTab = viewModel.selectedTab == .outputs ? DashboardViewModel.DashboardTab.chat : viewModel.selectedTab
            let showChat = activeTab == .chat
            ChatView(viewModel: viewModel, hideAgentPicker: false)
                .environment(\.workspaceSidebarController, WorkspaceSidebarController(
                    isExpanded: Binding(
                        get: { isWorkspaceSidebarExpanded },
                        set: { expanded in
                            if expanded {
                                revealWorkspaceSidebar()
                            } else {
                                hideWorkspaceSidebar(resetEditor: true)
                            }
                        }
                    ),
                    hasEditor: workspaceEditingFilePath != nil,
                    toggle: { toggleWorkspaceSidebar() }
                ))
                .opacity(showChat ? 1 : 0)
                .allowsHitTesting(showChat)

            if !showChat {
                Group {
                    switch activeTab {
                    case .chat:
                        EmptyView()
                    case .status:
                        StatusTabView(viewModel: viewModel)
                    case .budget:
                        BudgetTabView(viewModel: viewModel)
                    case .billing:
                        #if REQUIRE_LOGIN
                        if let mm = viewModel.membershipManager {
                            BillingTabView(viewModel: viewModel, membershipManager: mm)
                        } else {
                            Text("Please log in to view billing.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        #else
                        Text("Billing is not available in this build.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        #endif
                    case .persona:
                        PersonaTabView()
                    case .subAgents:
                        SubAgentsTabView(openclawService: viewModel.openclawService)
                    case .market:
                        // Marketplace lives in the main content area now (was a
                        // sidebar mode). Detail view replaces overview when an
                        // agent is selected; back arrow clears selection.
                        if let agent = viewModel.selectedMarketplaceAgent {
                            MarketplaceDetailView(
                                agent: agent,
                                openclawService: viewModel.openclawService,
                                onInstalled: { agentId in
                                    viewModel.loadAvailableAgents()
                                    viewModel.selectedTab = .chat
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        viewModel.selectedAgentId = agentId
                                    }
                                },
                                onBack: {
                                    viewModel.selectedMarketplaceAgent = nil
                                }
                            )
                            .id(agent.id)
                        } else {
                            MarketplaceOverviewView(onSelect: { agent in
                                viewModel.selectedMarketplaceAgent = agent
                            })
                        }
                    case .tasksLogs:
                        TasksLogsTabView(viewModel: viewModel)
                    case .config:
                        ConfigTabView(viewModel: viewModel)
                    case .skills:
                        SkillsTabView(viewModel: viewModel)
                    case .models:
                        ModelsTabView(viewModel: viewModel)
                    case .outputs:
                        EmptyView()
                    case .channels:
                        ChannelsTabView(viewModel: viewModel)
                    case .plugins:
                        PluginsTabView(viewModel: viewModel)
                    case .cron:
                        CronTabView(viewModel: viewModel)
                    case .logs:
                        LogsTabView(viewModel: viewModel)
                    }
                }
            }
        }
    }

    private func toggleWorkspaceSidebar() {
        if isWorkspaceSidebarExpanded {
            hideWorkspaceSidebar(resetEditor: true)
        } else {
            revealWorkspaceSidebar()
        }
    }

    private func revealWorkspaceSidebar() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            workspaceSidebarExpanded = true
        }
    }

    private func hideWorkspaceSidebar(resetEditor: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            workspaceSidebarExpanded = false
            if resetEditor {
                workspaceEditingFilePath = nil
                workspaceEditingFileDirty = false
            }
        }
    }

    private func workspaceSidebarColumn(width: CGFloat) -> some View {
        workspaceExpandedSidebar
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .topTrailing)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(alignment: .leading) {
                Divider()
            }
            .clipped()
    }

    private var workspaceExpandedSidebar: some View {
        HStack(spacing: 0) {
            WorkspaceFilePanel(
                agentId: viewModel.selectedAgentId,
                editingFilePath: $workspaceEditingFilePath,
                editingFileDirty: workspaceEditingFileDirty,
                onClose: {
                    hideWorkspaceSidebar(resetEditor: true)
                }
            )

            if let path = workspaceEditingFilePath {
                FileEditorPanel(
                    filePath: path,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            workspaceEditingFilePath = nil
                            workspaceEditingFileDirty = false
                        }
                    },
                    onDirtyChanged: { dirty in
                        workspaceEditingFileDirty = dirty
                    },
                    isFullscreen: $workspaceEditorFullscreen
                )
                .id(path)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    // MARK: - Collab Panel

    private var collabDragHandle: some View {
        CollabDragHandleView()
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let newWidth = dragStartWidth + value.translation.width
                        collabPanelWidth = min(max(newWidth, collabPanelMinWidth), collabPanelMaxWidth)
                    }
                    .onEnded { _ in
                        dragStartWidth = collabPanelWidth
                    }
            )
    }

    private var collabPanelContent: some View {
        VStack(spacing: 0) {
            if let collabVM = viewModel.collabViewModel {
                CollabWindowView(
                    viewModel: collabVM,
                    onCollapse: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.collabPanelCollapsed = true
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showCollabPanel = false
                        }
                    }
                )
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "No collaboration tasks", bundle: LanguageManager.shared.localizedBundle))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var collabCollapsedStrip: some View {
        VStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.collabPanelCollapsed = false
                }
            }) {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12))
                    // Show progress count if available
                    if let collabVM = viewModel.collabViewModel, collabVM.totalCount > 0 {
                        Text("\(collabVM.completedCount)/\(collabVM.totalCount)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundColor(.secondary)
                .frame(width: collabCollapsedWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

// MARK: - Collab Drag Handle (NSView-based cursor)

/// Uses NSView's resetCursorRects for stable resize cursor without onHover feedback loops.
private struct CollabDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeCursorView {
        let view = ResizeCursorView()
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
    func updateNSView(_ nsView: ResizeCursorView, context: Context) {}

    class ResizeCursorView: NSView {
        override var intrinsicContentSize: NSSize {
            NSSize(width: 5, height: NSView.noIntrinsicMetric)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
        override func draw(_ dirtyRect: NSRect) {
            // Background
            NSColor.gray.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()
            // Center divider line
            let lineX = (bounds.width - 1) / 2
            let lineRect = NSRect(x: lineX, y: 0, width: 1, height: bounds.height)
            NSColor.separatorColor.setFill()
            lineRect.fill()
        }
    }
}

// MARK: - Slash Command Model

struct SlashCommand: Identifiable {
    let id: String  // e.g. "/help"
    let name: String
    let description: String
    let hasParam: Bool
}

private let slashCommands: [SlashCommand] = [
    // Core
    SlashCommand(id: "/help",       name: "/help",       description: "Show help",               hasParam: false),
    SlashCommand(id: "/status",     name: "/status",     description: "View session status",      hasParam: false),
    SlashCommand(id: "/agent",      name: "/agent",      description: "Switch agent",             hasParam: true),
    SlashCommand(id: "/agents",     name: "/agents",     description: "List agents",              hasParam: false),
    SlashCommand(id: "/session",    name: "/session",    description: "Switch session",           hasParam: true),
    SlashCommand(id: "/sessions",   name: "/sessions",   description: "List sessions",            hasParam: false),
    SlashCommand(id: "/model",      name: "/model",      description: "Switch model",             hasParam: true),
    SlashCommand(id: "/models",     name: "/models",     description: "List models",              hasParam: false),
    // Session control
    SlashCommand(id: "/think",      name: "/think",      description: "Set thinking level",       hasParam: true),
    SlashCommand(id: "/verbose",    name: "/verbose",    description: "Verbose output mode",      hasParam: true),
    SlashCommand(id: "/reasoning",  name: "/reasoning",  description: "Reasoning mode toggle",    hasParam: true),
    SlashCommand(id: "/usage",      name: "/usage",      description: "Usage display mode",       hasParam: true),
    SlashCommand(id: "/elevated",   name: "/elevated",   description: "Elevated permission mode", hasParam: true),
    SlashCommand(id: "/activation", name: "/activation", description: "Activation mode",          hasParam: true),
    SlashCommand(id: "/deliver",    name: "/deliver",    description: "Message delivery toggle",  hasParam: true),
    // Session lifecycle
    SlashCommand(id: "/new",        name: "/new",        description: "Reset session",            hasParam: false),
    SlashCommand(id: "/reset",      name: "/reset",      description: "Reset session",            hasParam: false),
    SlashCommand(id: "/abort",      name: "/abort",      description: "Abort current run",        hasParam: false),
    SlashCommand(id: "/settings",   name: "/settings",   description: "Open settings",            hasParam: false),
    SlashCommand(id: "/exit",       name: "/exit",       description: "Exit app",                 hasParam: false),
    // Skills
    SlashCommand(id: "/skills",     name: "/skills",     description: "Use a skill",              hasParam: true),
    // Collab
    SlashCommand(id: "/collab",     name: "/collab",     description: "Multi-agent collab task",   hasParam: true),
]

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var viewModel: DashboardViewModel
    var hideAgentPicker: Bool = false
    @Environment(\.workspaceSidebarController) private var workspaceSidebarController
    @State private var inputText = ""
    // The `ChatInputMode` picker (聊天/执行任务/代码模式) used to live here
    // but was hidden in v1.1.46 — see the toolbar row below and the
    // `ChatInputModePicker` definition for the disabled state's reasoning.
    @State private var eventMonitor: Any?
    @State private var queryHistory: [String] = UserDefaults.standard.stringArray(forKey: "chatQueryHistory") ?? []
    @State private var historyIndex: Int = -1
    // Slash command autocomplete
    @State private var slashSelectedIndex: Int = 0
    @State private var isInputFocused: Bool = false
    @State private var focusMonitor: Any?
    // Skills panel
    @State private var skillsSelectedIndex: Int = 0
    @State private var skillJustSelected: Bool = false
    // @ Agent mention panel
    @State private var agentSelectedIndex: Int = 0
    @State private var agentJustSelected: Bool = false
    // Composer agent/model selector
    @State private var showComposerSelector = false
    @State private var composerSelectorShowsModels = false
    // File attachments
    @State private var attachedFiles: [URL] = []
    // Scroll debounce for streaming content
    @State private var scrollDebounceWork: DispatchWorkItem?
    // Smart scroll: only auto-scroll if user is at bottom
    @State private var shouldAutoScroll: Bool = true
    @State private var autoScrollDisableTimer: Timer?
    // Store ScrollViewProxy so sendMessage() can scroll to bottom
    @State private var chatScrollProxy: ScrollViewProxy?
    // Create agent sheet
    @State private var showCreateAgentSheet = false
    @StateObject private var createAgentVM: SubAgentsViewModel
    // Built-in terminal
    @State private var terminalOpen = false
    @State private var terminalHeight: CGFloat = 120
    private static let layoutMetrics = OutputsSidebarLayoutMetrics()

    init(viewModel: DashboardViewModel, hideAgentPicker: Bool = false) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.hideAgentPicker = hideAgentPicker
        self._createAgentVM = StateObject(wrappedValue: SubAgentsViewModel(openclawService: viewModel.openclawService))
    }

    /// The currently selected agent (for header bar display).
    private var currentAgent: AgentOption? {
        viewModel.availableAgents.first { $0.id == viewModel.selectedAgentId }
    }

    /// Workspace path for the terminal. Uses the shared resolver so it stays
    /// faithful to openclaw's resolveAgentWorkspaceDir (handles non-default
    /// "main" → workspace-main, explicit per-agent workspace, etc.).
    private var terminalWorkspacePath: String {
        DashboardViewModel.resolveAgentWorkspace(viewModel.selectedAgentId)
    }

    private var currentSessionMetadata: ChatSessionMetadata? {
        guard let sessionId = viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId] else {
            return nil
        }
        return (viewModel.sessionsByAgent[viewModel.selectedAgentId] ?? []).first { $0.id == sessionId }
    }

    private var currentSessionTitle: String? {
        guard !viewModel.chatMessages.isEmpty else { return nil }
        let title = currentSessionMetadata?.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    // MARK: - Chat Message List (extracted for compiler performance)

    @ViewBuilder
    private func chatScrollContent(proxy: ScrollViewProxy) -> some View {
        let scrollView = ScrollView {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatTop")

                    ForEach(viewModel.chatMessages, id: \.id) { message in
                        // Hide bubbles that are "transient placeholders" —
                        // empty assistant messages still in `.loading`. Empty
                        // `.background` messages still pass through so users see
                        // the background-running affordance.
                        let isLoadingPlaceholder = message.role == .assistant
                            && message.content.isEmpty
                            && message.attachments.isEmpty
                            && message.taskStatus == .loading
                        if !isLoadingPlaceholder {
                            if message.scrollTargetId != nil {
                                BackgroundTaskNotification(message: message, scrollProxy: proxy)
                                    .id(message.id)
                            } else {
                                ChatBubble(
                                    message: message,
                                    onRewind: { viewModel.rewindToMessage($0) },
                                    onCancel: { viewModel.cancelChat($0.id) }
                                )
                                    .id(message.id)
                            }
                        }
                    }

                    ForEach(viewModel.chatMessages.filter { $0.taskStatus == .loading && $0.content.isEmpty }, id: \.id) { loadingMsg in
                        ThinkingIndicator(
                            message: loadingMsg,
                            viewModel: viewModel
                        )
                        .id("loading-\(loadingMsg.id)")
                    }

                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatBottom")
                }
                .frame(maxWidth: Self.layoutMetrics.chatColumnMaxWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .alert(
            "回滚失败",
            isPresented: Binding(
                get: { viewModel.rewindError != nil },
                set: { if !$0 { viewModel.rewindError = nil } }
            )
        ) {
            Button("好", role: .cancel) { viewModel.rewindError = nil }
        } message: {
            Text(viewModel.rewindError ?? "")
        }

        if #available(macOS 14.0, *) {
            scrollView
                .defaultScrollAnchor(.bottom)
                .onChange(of: viewModel.chatMessages.count) { _ in
                    // Only auto-scroll if user hasn't disabled it by scrolling up
                    if shouldAutoScroll {
                        // Use animated scroll so LazyVStack can progressively create views
                        // during the scroll animation, avoiding white flash from instant jump
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("chatBottom", anchor: .bottom)
                            }
                        }
                    }
                }
        } else {
            scrollView
                .onChange(of: viewModel.chatMessages.count) { _ in
                    if shouldAutoScroll {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("chatBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    if !viewModel.chatMessages.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("chatBottom", anchor: .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            proxy.scrollTo("chatBottom", anchor: .bottom)
                        }
                    }
                }
        }
    }

    /// Filtered slash commands based on current input
    private var filteredSlashCommands: [SlashCommand] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        // Only match when the input is purely a command prefix (no spaces = no param yet)
        guard !trimmed.dropFirst().contains(" ") else { return [] }
        if trimmed == "/" { return slashCommands }
        return slashCommands.filter { $0.name.hasPrefix(trimmed.lowercased()) }
    }

    private var showSlashPanel: Bool {
        !filteredSlashCommands.isEmpty && !showSkillsPanel && !showAgentPanel
    }

    /// Filtered skills based on input after "/skills "
    private var filteredSkills: [SkillInfo] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        // Exact "/skills" or "/skills " prefix
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return [] }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        let allSkills = viewModel.skills
        if keyword.isEmpty { return allSkills }
        return allSkills.filter { $0.name.lowercased().contains(keyword) }
    }

    private var showSkillsPanel: Bool {
        if skillJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return false }
        guard !viewModel.skills.isEmpty else { return false }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        if keyword.contains(" ") { return false }
        return true
    }

    /// Filtered agents based on input after "@"
    private var filteredAgents: [AgentOption] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return [] }
        let keyword = String(trimmed.dropFirst()).lowercased()
        // Only match when typing the agent name (no space yet)
        guard !keyword.contains(" ") else { return [] }
        let allAgents = viewModel.availableAgents
        if keyword.isEmpty { return allAgents }
        return allAgents.filter { $0.name.lowercased().contains(keyword) || $0.id.lowercased().contains(keyword) }
    }

    private var showAgentPanel: Bool {
        if agentJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("@") else { return false }
        guard !viewModel.availableAgents.isEmpty else { return false }
        let keyword = String(trimmed.dropFirst())
        // Only show panel while typing agent name (before space)
        if keyword.contains(" ") { return false }
        return true
    }

    private var emptyChatSurface: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            VStack(spacing: 22) {
                Text(String(localized: "What should we build today?", bundle: LanguageManager.shared.localizedBundle))
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                composerArea(maxWidth: Self.layoutMetrics.chatColumnMaxWidth, horizontalPadding: 0, bottomPadding: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatTopChrome: some View {
        HStack(spacing: 12) {
            if let title = currentSessionTitle {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            chatPanelToggleButton
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, viewModel.chatMessages.isEmpty ? 4 : 2)
    }

    private var timelineChatSurface: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    chatScrollContent(proxy: proxy)
                        .onAppear {
                            chatScrollProxy = proxy
                            if !viewModel.chatMessages.isEmpty && shouldAutoScroll {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    proxy.scrollTo("chatBottom", anchor: .bottom)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    proxy.scrollTo("chatBottom", anchor: .bottom)
                                }
                            }
                        }
                }
            }
            .id("chatScrollView")

            composerArea(maxWidth: Self.layoutMetrics.chatColumnMaxWidth, horizontalPadding: 16, bottomPadding: 16)

            if terminalOpen {
                terminalPanel
            }
        }
    }

    private func composerArea(maxWidth: CGFloat, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        composerInputCard
            .overlay(alignment: .bottomTrailing) {
                composerFloatingPanels
            }
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
        .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
        .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
        .animation(.easeInOut(duration: 0.18), value: composerSelectorShowsModels)
    }

    private var composerFloatingPanels: some View {
        composerSuggestionPanels
            .zIndex(4)
            .allowsHitTesting(showSlashPanel || showSkillsPanel || showAgentPanel)
    }

    @ViewBuilder
    private var composerSuggestionPanels: some View {
        if showSlashPanel {
            slashCommandPanel
        }

        if showSkillsPanel {
            skillsPanel
        }

        if showAgentPanel {
            agentMentionPanel
        }
    }

    private var slashCommandPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { slashProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSlashCommands.enumerated()), id: \.element.id) { index, cmd in
                            HStack(spacing: 8) {
                                Text(cmd.name)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(index == slashSelectedIndex ? .white : .primary)
                                Spacer()
                                Text(cmd.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(index == slashSelectedIndex ? .white.opacity(0.8) : .secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == slashSelectedIndex ? Color.accentColor : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectSlashCommand(filteredSlashCommands[index])
                            }
                            .id(cmd.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: slashSelectedIndex) { newIndex in
                    if newIndex >= 0 && newIndex < filteredSlashCommands.count {
                        withAnimation {
                            slashProxy.scrollTo(filteredSlashCommands[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .autocompletePanelStyle(bottomOffset: 110)
    }

    private var skillsPanel: some View {
        VStack(spacing: 0) {
            if filteredSkills.isEmpty {
                HStack {
                    Text(String(localized: "No matching skills", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ScrollViewReader { skillProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredSkills.enumerated()), id: \.element.id) { index, skill in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(skill.status == .ready ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text(skill.name)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(index == skillsSelectedIndex ? .white : .primary)
                                    Spacer()
                                    if !skill.description.isEmpty {
                                        Text(skill.description)
                                            .font(.system(size: 11))
                                            .foregroundColor(index == skillsSelectedIndex ? .white.opacity(0.8) : .secondary)
                                            .lineLimit(1)
                                    }
                                    if !skill.source.isEmpty {
                                        Text(skill.source)
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(index == skillsSelectedIndex ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                            .foregroundColor(index == skillsSelectedIndex ? .white.opacity(0.9) : .secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == skillsSelectedIndex ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectSkill(filteredSkills[index])
                                }
                                .id("skill-\(skill.name)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: skillsSelectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < filteredSkills.count {
                            withAnimation {
                                skillProxy.scrollTo("skill-\(filteredSkills[newIndex].name)", anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .autocompletePanelStyle(bottomOffset: 110)
    }

    private var agentMentionPanel: some View {
        VStack(spacing: 0) {
            if filteredAgents.isEmpty {
                HStack {
                    Text(String(localized: "No matching agents", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ScrollViewReader { agentProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredAgents.enumerated()), id: \.element.id) { index, agent in
                                HStack(spacing: 8) {
                                    AgentAvatarImage(size: 18)
                                        .frame(width: 24)
                                    Text(agent.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(index == agentSelectedIndex ? .white : .primary)
                                    if agent.id != agent.name {
                                        Text(agent.id)
                                            .font(.system(size: 11))
                                            .foregroundColor(index == agentSelectedIndex ? .white.opacity(0.7) : .secondary)
                                    }
                                    Spacer()
                                    if agent.id == viewModel.selectedAgentId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(index == agentSelectedIndex ? .white : .accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == agentSelectedIndex ? Color.accentColor : Color.clear)
                                .cornerRadius(6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectAgent(filteredAgents[index])
                                }
                                .id("agent-\(agent.id)")
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: agentSelectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < filteredAgents.count {
                            withAnimation {
                                agentProxy.scrollTo("agent-\(filteredAgents[newIndex].id)", anchor: .center)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .autocompletePanelStyle(bottomOffset: 110)
    }

    private var composerInputCard: some View {
        VStack(spacing: 0) {
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachedFiles, id: \.absoluteString) { url in
                            AttachmentPreview(url: url) {
                                attachedFiles.removeAll { $0 == url }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty && !isInputFocused {
                    Text(String(localized: "Do Anything", bundle: LanguageManager.shared.localizedBundle))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color(NSColor.placeholderTextColor).opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                Text(inputText.isEmpty ? " " : inputText)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .opacity(0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $inputText)
                    .font(.body)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .scrollContentBackground(.hidden)
                    .disabled(isInputLocked)
            }
            .frame(minHeight: 44, maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)

            HStack(spacing: 6) {
                Button(action: { openFilePicker() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Attach File", bundle: LanguageManager.shared.localizedBundle))
                .disabled(isInputLocked)

                Spacer(minLength: 8)

                ComposerAgentModelSelector(
                    viewModel: viewModel,
                    isOpen: $showComposerSelector,
                    showingModels: $composerSelectorShowsModels
                )

                Button(action: { sendMessage() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(canSend ? .white : Color(NSColor.tertiaryLabelColor))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(canSend
                                      ? Color.accentColor
                                      : Color(NSColor.quaternaryLabelColor))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if !attachedFiles.contains(url) {
                            attachedFiles.append(url)
                        }
                    }
                }
            }
            return true
        }
    }

    private var terminalPanel: some View {
        VStack(spacing: 0) {
            TerminalDragHandle(height: $terminalHeight)
            TerminalPanelView(
                workspacePath: terminalWorkspacePath,
                onClose: { withAnimation { terminalOpen = false } }
            )
            .frame(height: terminalHeight)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var chatPanelToggleButton: some View {
        Button {
            workspaceSidebarController.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(workspaceSidebarController.isExpanded.wrappedValue ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Outputs")
    }

    private func closeComposerSelector() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showComposerSelector = false
            composerSelectorShowsModels = false
        }
    }

    private var composerSelectorDismissLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                closeComposerSelector()
            }
    }

    @ViewBuilder
    private func composerSelectorOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor, showComposerSelector {
                let selectorFrame = proxy[anchor]
                let trailingOffset = max(12, proxy.size.width - selectorFrame.maxX)
                let bottomOffset = max(12, proxy.size.height - selectorFrame.minY + 8)

                ZStack(alignment: .bottomTrailing) {
                    composerSelectorDismissLayer
                        .zIndex(0)

                    ComposerAgentModelPanel(
                        viewModel: viewModel,
                        isOpen: $showComposerSelector,
                        showingModels: $composerSelectorShowsModels
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.trailing, trailingOffset)
                    .padding(.bottom, bottomOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                    .zIndex(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
                .animation(.easeInOut(duration: 0.18), value: composerSelectorShowsModels)
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            chatTopChrome
            if viewModel.chatMessages.isEmpty {
                emptyChatSurface
            } else {
                timelineChatSurface
            }
        }
    }

    var body: some View {
        chatContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(ComposerSelectorButtonBoundsKey.self) { anchor in
                composerSelectorOverlay(anchor: anchor)
            }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.loadAvailableAgents()
            if viewModel.skills.isEmpty {
                Task { await viewModel.loadSkills() }
            }

            // Monitor scroll wheel events to detect user scrolling
            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                // User scrolled, disable auto-scroll temporarily
                shouldAutoScroll = false

                // Re-enable auto-scroll after user stops scrolling for 3 seconds
                autoScrollDisableTimer?.invalidate()
                autoScrollDisableTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    shouldAutoScroll = true
                }

                return event
            }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let responder = event.window?.firstResponder, responder is NSTextView else {
                    return event
                }
                // Don't intercept keys when the code editor's NSTextView is focused
                if let tv = responder as? NSTextView, tv.identifier?.rawValue == "codeEditorTextView" {
                    return event
                }

                // Don't intercept keys when a CommitTextField (rename/new file) is focused
                if let tv = responder as? NSTextView,
                   tv.identifier?.rawValue == "commitTextField" {
                    return event
                }

                // IME composition guard — when the user is mid-pinyin
                // (or any other input-method composition), the text view
                // has "marked text" (the candidates shown above the
                // caret). In that state ALL keys including Return / Tab
                // / Escape belong to the IME — Return commits the raw
                // composed text as English, Tab cycles candidates, etc.
                // Without this guard, hitting Return mid-composition
                // gets intercepted by our sendMessage shortcut, and the
                // half-typed pinyin (e.g. "li'r") is sent literally
                // before the IME has a chance to convert it.
                if let tv = responder as? NSTextView, tv.hasMarkedText() {
                    return event
                }

                // Escape (keyCode 53) — close slash/skills/agent panel
                if event.keyCode == 53 && (showSlashPanel || showSkillsPanel || showAgentPanel) {
                    DispatchQueue.main.async {
                        inputText = ""
                        slashSelectedIndex = 0
                        skillsSelectedIndex = 0
                        agentSelectedIndex = 0
                    }
                    return nil
                }

                // Cmd+V (keyCode 9) — paste image from clipboard
                if event.keyCode == 9 && event.modifierFlags.contains(.command) {
                    let pb = NSPasteboard.general
                    let hasImage = pb.canReadItem(withDataConformingToTypes: [
                        NSPasteboard.PasteboardType.png.rawValue,
                        NSPasteboard.PasteboardType.tiff.rawValue
                    ])
                    // Only intercept if clipboard has image data but no text
                    let hasText = pb.string(forType: .string) != nil
                    if hasImage && !hasText {
                        DispatchQueue.main.async { pasteImageFromClipboard() }
                        return nil
                    }
                }

                // Tab (keyCode 48) — confirm slash/skills/agent selection
                if event.keyCode == 48 {
                    if showAgentPanel {
                        let agents = filteredAgents
                        if agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                }

                // Return without Shift
                if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                    // If agent panel is open, confirm selection instead of sending
                    if showAgentPanel {
                        let agents = filteredAgents
                        if !agents.isEmpty && agentSelectedIndex >= 0 && agentSelectedIndex < agents.count {
                            DispatchQueue.main.async { selectAgent(agents[agentSelectedIndex]) }
                        }
                        return nil
                    }
                    // If skills panel is open, confirm selection instead of sending
                    if showSkillsPanel {
                        let skills = filteredSkills
                        if !skills.isEmpty && skillsSelectedIndex >= 0 && skillsSelectedIndex < skills.count {
                            DispatchQueue.main.async { selectSkill(skills[skillsSelectedIndex]) }
                        }
                        return nil
                    }
                    // If slash panel is open, confirm selection instead of sending
                    if showSlashPanel {
                        let cmds = filteredSlashCommands
                        if slashSelectedIndex >= 0 && slashSelectedIndex < cmds.count {
                            DispatchQueue.main.async { selectSlashCommand(cmds[slashSelectedIndex]) }
                        }
                        return nil
                    }
                    DispatchQueue.main.async { sendMessage() }
                    return nil
                }

                // ↑ (keyCode 126)
                if event.keyCode == 126 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            if agentSelectedIndex > 0 {
                                agentSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            if skillsSelectedIndex > 0 {
                                skillsSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            if slashSelectedIndex > 0 {
                                slashSelectedIndex -= 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if (inputText.isEmpty || historyIndex >= 0) && !queryHistory.isEmpty {
                        if historyIndex == -1 {
                            historyIndex = queryHistory.count - 1
                        } else if historyIndex > 0 {
                            historyIndex -= 1
                        }
                        inputText = queryHistory[historyIndex]
                        return nil
                    }
                }

                // ↓ (keyCode 125)
                if event.keyCode == 125 {
                    // Agent panel navigation takes priority
                    if showAgentPanel {
                        DispatchQueue.main.async {
                            let agents = filteredAgents
                            if agentSelectedIndex < agents.count - 1 {
                                agentSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Skills panel navigation takes priority
                    if showSkillsPanel {
                        DispatchQueue.main.async {
                            let skills = filteredSkills
                            if skillsSelectedIndex < skills.count - 1 {
                                skillsSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // Slash panel navigation takes priority
                    if showSlashPanel {
                        DispatchQueue.main.async {
                            let cmds = filteredSlashCommands
                            if slashSelectedIndex < cmds.count - 1 {
                                slashSelectedIndex += 1
                            }
                        }
                        return nil
                    }
                    // History browsing
                    if historyIndex >= 0 {
                        if historyIndex < queryHistory.count - 1 {
                            historyIndex += 1
                            inputText = queryHistory[historyIndex]
                        } else {
                            historyIndex = -1
                            inputText = ""
                        }
                        return nil
                    }
                }

                return event
            }

            // Focus monitor: track whether the TextEditor has focus
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                DispatchQueue.main.async {
                    if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                        if !isInputFocused { withAnimation(.easeOut(duration: 0.15)) { isInputFocused = true } }
                    } else {
                        if isInputFocused { withAnimation(.easeIn(duration: 0.15)) { isInputFocused = false } }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            if let monitor = focusMonitor {
                NSEvent.removeMonitor(monitor)
                focusMonitor = nil
            }
            // Clean up timer
            autoScrollDisableTimer?.invalidate()
            autoScrollDisableTimer = nil
        }
        .onChange(of: inputText) { _ in
            // Reset slash/skills/agent selection index when input changes
            slashSelectedIndex = 0
            skillsSelectedIndex = 0
            agentSelectedIndex = 0
            // Reset skill selection flag if input no longer has skill prefix
            if skillJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
                if !trimmed.hasPrefix("/skills ") {
                    skillJustSelected = false
                }
            }
            // Reset agent selection flag if input no longer has @ prefix
            if agentJustSelected {
                let trimmed = inputText.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("@") {
                    agentJustSelected = false
                }
            }
        }
        .overlay(alignment: .trailing) {
            if viewModel.agentSettingsOpen, let detail = viewModel.selectedAgentDetail {
                AgentSettingsPanel(
                    viewModel: viewModel,
                    agent: detail,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModel.agentSettingsOpen = false
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .onChange(of: viewModel.selectedAgentId) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.agentSettingsOpen = false
                terminalOpen = false
            }
        }
        .sheet(isPresented: $showCreateAgentSheet) {
            CreateAgentSheet(
                viewModel: createAgentVM,
                isPresented: $showCreateAgentSheet,
                onCreatedWithId: { agentId in
                    viewModel.loadAvailableAgents()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.selectedAgentId = agentId
                    }
                }
            )
        }
    }

    private var canSend: Bool {
        let hasText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty
        let hasFiles = !attachedFiles.isEmpty
        // Lock send only when *this session* is in flight — not when
        // another session of the same agent is running in the background.
        // `viewModel.isSendingMessage` is the session-scoped predicate
        // (recomputed by `recomputeIsSendingMessage` whenever session,
        // agent, or task set changes); `isCurrentAgentSending` is
        // agent-scoped and used by the sidebar to badge the agent row.
        return (hasText || hasFiles) && !viewModel.isSendingMessage
    }

    /// Whether the input area (text + attachment) should be locked.
    /// Session-scoped — see comment in `canSend`. Switching to a
    /// different session of the same agent unlocks the input even if
    /// the previous session has a task still streaming in the
    /// inactive-sessions map.
    private var isInputLocked: Bool {
        viewModel.isSendingMessage
    }

    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespaces)
        let files = attachedFiles
        guard !text.isEmpty || !files.isEmpty else { return }
        inputText = ""
        attachedFiles = []

        // Handle @agent_name prefix: strip it and use the actual message
        if text.hasPrefix("@") {
            let afterAt = String(text.dropFirst())
            if let spaceIdx = afterAt.firstIndex(of: " ") {
                let agentName = String(afterAt[afterAt.startIndex..<spaceIdx])
                let messageContent = String(afterAt[afterAt.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
                // Verify the agent exists
                if viewModel.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = messageContent.isEmpty ? "hi, \(agentName)" : messageContent
                }
            } else {
                // Just "@agentName" with no message
                let agentName = afterAt.trimmingCharacters(in: .whitespaces)
                if viewModel.availableAgents.contains(where: { $0.name == agentName || $0.id == agentName }) {
                    text = "hi, \(agentName)"
                }
            }
        }

        // Update history: deduplicate, append, cap at 20, persist
        if !text.isEmpty {
            if let idx = queryHistory.firstIndex(of: text) {
                queryHistory.remove(at: idx)
            }
            queryHistory.append(text)
            if queryHistory.count > 20 {
                queryHistory.removeFirst()
            }
            UserDefaults.standard.set(queryHistory, forKey: "chatQueryHistory")
        }
        historyIndex = -1

        // Handle local commands
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "/exit" {
            NSApp.terminate(nil)
            return
        }

        // Handle /collab command
        if lower.hasPrefix("/collab ") {
            let taskDescription = String(text.dropFirst("/collab ".count)).trimmingCharacters(in: .whitespaces)
            guard !taskDescription.isEmpty else { return }

            // Show user message
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))

            // Show placeholder
            let isChinese = LanguageManager.shared.currentLocale.language.languageCode?.identifier.hasPrefix("zh") == true
            let clarifyingText = isChinese ? "正在了解需求..." : "Understanding requirements..."
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander", agentEmoji: "🎯"))

            let collabVM = viewModel.getOrCreateCollabViewModel()

            // Open collab window
            viewModel.showCollabPanel = true
            viewModel.collabPanelCollapsed = false

            Task {
                await collabVM.startCollab(taskDescription)
                // Note: chat messages are now managed by CollabViewModel phases
                // (clarify questions, decompose plan, final result are appended by VM)
            }
            return
        }

        // Route messages to active collab session based on phase (only when on Commander tab)
        // Skip routing when session is stale (not running + not in an interactive phase)
        if viewModel.selectedAgentId == "commander",
           let collabVM = viewModel.collabViewModel,
           collabVM.session != nil {
            let collabPhase = collabVM.phase
            let isInteractivePhase = (collabPhase == .clarifying || collabPhase == .awaitingApproval)

            if collabVM.isRunning || isInteractivePhase {
                if collabPhase == .clarifying {
                    // User is answering Commander's clarification questions
                    viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    Task {
                        await collabVM.handleClarifyResponse(text)
                    }
                    return
                }

                if collabPhase == .awaitingApproval {
                    viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    let confirmWords = ["确认", "ok", "go", "执行", "开始", "yes", "confirm", "start"]
                    if confirmWords.contains(lower) {
                        viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                            role: .assistant,
                            content: "开始执行任务...",
                            agentId: "commander",
                            agentEmoji: "🎯"
                        ))
                        Task {
                            await collabVM.confirmAndExecute()
                        }
                    } else {
                        // User wants to continue discussing / adjust requirements
                        Task {
                            await collabVM.handleClarifyResponse(text)
                        }
                    }
                    return
                }

                if collabPhase == .executing || collabPhase == .summarizing || collabPhase == .completed {
                    // Route to existing chat handler during/after execution
                    viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))
                    Task {
                        if let reply = await collabVM.handleUserMessage(text) {
                            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                                role: .assistant,
                                content: reply,
                                agentId: "commander",
                                agentEmoji: "🎯"
                            ))
                        }
                    }
                    return
                }
            }
            // Stale session (not running, not interactive) — fall through to start new collab
        }

        // Auto-trigger collab when chatting with Commander (no active collab session)
        // First check intent — simple questions get direct replies without entering collab
        if viewModel.selectedAgentId == "commander" {
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .user, content: text))

            let collabVM = viewModel.getOrCreateCollabViewModel()

            // Show thinking placeholder
            let thinkingId = UUID()
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: "", agentId: "commander", agentEmoji: "🎯", taskStatus: .loading, id: thinkingId))
            viewModel.isSendingMessage = true

            Task {
                let directReply = await collabVM.checkIntent(text)

                // Remove thinking placeholder
                await MainActor.run {
                    if let idx = viewModel.chatMessagesByAgent["commander"]?.firstIndex(where: { $0.id == thinkingId }) {
                        viewModel.chatMessagesByAgent["commander"]?.remove(at: idx)
                    }
                }

                if let reply = directReply {
                    // Commander answered directly — no collab needed
                    await MainActor.run {
                        viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                            role: .assistant,
                            content: reply,
                            agentId: "commander",
                            agentEmoji: "🎯"
                        ))
                        viewModel.isSendingMessage = false
                    }
                } else {
                    // Commander says this needs collab — proceed with full flow
                    await MainActor.run {
                        let isChinese = LanguageManager.shared.currentLocale.language.languageCode?.identifier.hasPrefix("zh") == true
                        let clarifyingText = isChinese ? "正在了解需求..." : "Understanding requirements..."
                        viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander", agentEmoji: "🎯"))

                        viewModel.showCollabPanel = true
                        viewModel.collabPanelCollapsed = false
                        viewModel.isSendingMessage = false
                    }
                    await collabVM.startCollab(text)
                }
            }
            return
        }

        let isResetCommand = (lower == "/new" || lower == "/reset")

        // Ensure scroll to bottom when user sends a message
        shouldAutoScroll = true

        Task {
            await viewModel.sendChatMessage(text, attachments: files)
            if isResetCommand {
                await MainActor.run { viewModel.clearChat() }
            }
        }
    }

    /// Scroll chat to the latest message with animation.
    private func scrollToBottom() {
        guard let proxy = chatScrollProxy else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("chatBottom", anchor: .bottom)
        }
    }

    private func selectSlashCommand(_ cmd: SlashCommand) {
        slashSelectedIndex = 0
        if cmd.hasParam {
            // Fill command with trailing space, let user type the parameter
            inputText = cmd.name + " "
        } else {
            // No param — send immediately
            inputText = cmd.name
            sendMessage()
        }
    }

    private func selectSkill(_ skill: SkillInfo) {
        skillsSelectedIndex = 0
        skillJustSelected = true
        inputText = "/skills \(skill.name) "
    }

    private func selectAgent(_ agent: AgentOption) {
        agentSelectedIndex = 0
        agentJustSelected = true
        viewModel.selectedAgentId = agent.id
        inputText = "@\(agent.name) "
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .image, .pdf, .plainText,
            .audio, .movie,
            // Office
            UTType(filenameExtension: "doc")!,
            UTType(filenameExtension: "docx")!,
            UTType(filenameExtension: "xls")!,
            UTType(filenameExtension: "xlsx")!,
            UTType(filenameExtension: "ppt")!,
            UTType(filenameExtension: "pptx")!,
            // Data & Markup
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "json")!,
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "xml")!,
            UTType(filenameExtension: "yaml")!,
            UTType(filenameExtension: "yml")!,
            UTType(filenameExtension: "toml")!,
            UTType(filenameExtension: "ini")!,
            UTType(filenameExtension: "env")!,
            UTType(filenameExtension: "conf")!,
            UTType(filenameExtension: "properties")!,
            // Source code
            UTType(filenameExtension: "py")!,
            UTType(filenameExtension: "js")!,
            UTType(filenameExtension: "ts")!,
            UTType(filenameExtension: "swift")!,
            UTType(filenameExtension: "java")!,
            UTType(filenameExtension: "go")!,
            UTType(filenameExtension: "rs")!,
            UTType(filenameExtension: "c")!,
            UTType(filenameExtension: "cpp")!,
            UTType(filenameExtension: "h")!,
            UTType(filenameExtension: "rb")!,
            UTType(filenameExtension: "php")!,
            UTType(filenameExtension: "sh")!,
            UTType(filenameExtension: "sql")!,
            UTType(filenameExtension: "r")!,
            // Web
            UTType(filenameExtension: "html")!,
            UTType(filenameExtension: "htm")!,
            UTType(filenameExtension: "css")!,
            UTType(filenameExtension: "scss")!,
            UTType(filenameExtension: "vue")!,
            UTType(filenameExtension: "jsx")!,
            UTType(filenameExtension: "tsx")!,
            // Log & Notebook
            UTType(filenameExtension: "log")!,
            UTType(filenameExtension: "ipynb")!,
            // Mind map
            UTType(filenameExtension: "xmind")!,
        ]
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !attachedFiles.contains(url) {
                    attachedFiles.append(url)
                }
            }
        }
    }

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let imageData = pasteboard.data(forType: .png)
                ?? pasteboard.data(forType: .tiff) else { return }

        let uploadsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw/uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "paste_\(timestamp).png"
        let fileURL = uploadsDir.appendingPathComponent(fileName)

        // Convert to PNG if needed
        if let image = NSImage(data: imageData),
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: fileURL)
        } else {
            try? imageData.write(to: fileURL)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if !attachedFiles.contains(fileURL) {
                attachedFiles.append(fileURL)
            }
        }
    }
}

private extension View {
    func autocompletePanelStyle(bottomOffset: CGFloat) -> some View {
        self
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
            .padding(.horizontal, 16)
            .padding(.bottom, bottomOffset)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct ComposerSelectorButtonBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct ComposerAgentModelSelector: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isOpen: Bool
    @Binding var showingModels: Bool

    private var currentAgent: AgentOption? {
        viewModel.availableAgents.first { $0.id == viewModel.selectedAgentId }
    }

    private var agentLabel: String {
        currentAgent?.name ?? viewModel.selectedAgentId
    }

    private var modelLabel: String {
        let raw = currentAgent?.model ?? ""
        let resolved = raw.isEmpty ? viewModel.modelOverview.defaultModel : raw
        let cleaned = stripProviderPrefix(resolved)
        return cleaned.isEmpty || cleaned == "-" ? "Model" : cleaned
    }

    var body: some View {
        Button {
            if !isOpen {
                Task { await viewModel.loadModelsForSettings() }
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                isOpen.toggle()
                if !isOpen {
                    showingModels = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                AgentAvatarImage(size: 16)

                Text("\(agentLabel) · \(modelLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Agent and model")
        .anchorPreference(key: ComposerSelectorButtonBoundsKey.self, value: .bounds) { anchor in
            isOpen ? anchor : nil
        }
    }
}

private struct ComposerAgentModelPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isOpen: Bool
    @Binding var showingModels: Bool

    private var currentAgent: AgentOption? {
        viewModel.availableAgents.first { $0.id == viewModel.selectedAgentId }
    }

    private var currentRawModel: String {
        currentAgent?.model ?? ""
    }

    private var resolvedDefaultModel: String {
        let defaultModel = viewModel.modelOverview.defaultModel
        let cleaned = stripProviderPrefix(defaultModel)
        return cleaned.isEmpty || cleaned == "-" ? "" : cleaned
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 8) {
                primaryPanel
                if showingModels {
                    modelPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                }
            }

            VStack(alignment: .trailing, spacing: 8) {
                if showingModels {
                    modelPanel
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                }
                primaryPanel
            }
        }
    }

    private var primaryPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(viewModel.availableAgents) { agent in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        viewModel.selectedAgentId = agent.id
                        showingModels = false
                        isOpen = false
                    }
                } label: {
                    selectorRow(
                        title: agent.name,
                        subtitle: agent.id == agent.name ? nil : agent.id,
                        selected: agent.id == viewModel.selectedAgentId,
                        showsDisclosure: false,
                        showsAgentAvatar: true
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                Task { await viewModel.loadModelsForSettings() }
                withAnimation(.easeInOut(duration: 0.16)) {
                    showingModels.toggle()
                }
            } label: {
                selectorRow(
                    title: "Model",
                    subtitle: currentModelDisplay,
                    selected: false,
                    showsDisclosure: true,
                    showsAgentAvatar: false
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
        .frame(width: 240)
        .panelChrome(cornerRadius: 12)
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            Button {
                selectModel("")
            } label: {
                selectorRow(
                    title: resolvedDefaultModel.isEmpty ? "Default" : "Default (\(resolvedDefaultModel))",
                    subtitle: "Inherit",
                    selected: currentRawModel.isEmpty,
                    showsDisclosure: false,
                    showsAgentAvatar: false
                )
            }
            .buttonStyle(.plain)

            if !currentRawModel.isEmpty
                && !viewModel.availableModelsForSettings.contains(where: { $0.id == currentRawModel }) {
                Button {
                    selectModel(currentRawModel)
                } label: {
                    selectorRow(
                        title: stripProviderPrefix(currentRawModel),
                        subtitle: nil,
                        selected: true,
                        showsDisclosure: false,
                        showsAgentAvatar: false
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(viewModel.availableModelsForSettings) { model in
                Button {
                    selectModel(model.id)
                } label: {
                    selectorRow(
                        title: stripProviderPrefix(model.name),
                        subtitle: nil,
                        selected: model.id == currentRawModel,
                        showsDisclosure: false,
                        showsAgentAvatar: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 230)
        .panelChrome(cornerRadius: 12)
    }

    private var currentModelDisplay: String {
        let raw = currentRawModel.isEmpty ? viewModel.modelOverview.defaultModel : currentRawModel
        let cleaned = stripProviderPrefix(raw)
        return cleaned.isEmpty || cleaned == "-" ? "Model" : cleaned
    }

    private func selectorRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        showsDisclosure: Bool,
        showsAgentAvatar: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if showsAgentAvatar {
                AgentAvatarImage(size: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, subtitle == nil ? 8 : 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func selectModel(_ model: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            viewModel.updateAgentModel(model: model)
            showingModels = false
            isOpen = false
        }
    }
}

private extension View {
    func panelChrome(cornerRadius: CGFloat) -> some View {
        self
            .padding(6)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

private func stripProviderPrefix(_ s: String) -> String {
    if let slash = s.lastIndex(of: "/") {
        return String(s[s.index(after: slash)...])
    }
    return s
}

// MARK: - Chat Welcome View

struct ChatWelcomeView: View {
    var body: some View {
        VStack {
            Spacer()
            Text(String(localized: "What should we build today?", bundle: LanguageManager.shared.localizedBundle))
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Background Task Notification

struct BackgroundTaskNotification: View {
    let message: ChatMessage
    let scrollProxy: ScrollViewProxy

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Agent avatar
            if let agentId = message.agentId, agentId != "main",
               let emoji = message.agentEmoji {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                Text(message.content)
                    .font(.callout)

                Button(action: {
                    if let targetId = message.scrollTargetId {
                        withAnimation {
                            scrollProxy.scrollTo(targetId, anchor: .top)
                        }
                    }
                }) {
                    Text("View result ↑")
                        .font(.callout)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.08))
            .cornerRadius(12)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - Thinking Indicator with Background Timer

struct ThinkingIndicator: View {
    let message: ChatMessage
    @ObservedObject var viewModel: DashboardViewModel
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?

    private var showBackgroundButton: Bool {
        // Manual "Move to Background" is disabled along with auto-background:
        // this build keeps tasks foreground until they finish or are cancelled
        // (synchronous review-then-send workflow). A long run is stopped with
        // Cancel, not parked in the background. Reattached background runs
        // (from a prior app session) still render + cancel via the bubble's
        // .background row.
        false
    }

    var body: some View {
        HStack(spacing: 8) {
            // Agent avatar
            if let agentId = message.agentId, agentId != "main",
               let emoji = viewModel.availableAgents.first(where: { $0.id == agentId })?.emoji {
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show elapsed time
                Text(formatTime(elapsedSeconds))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            // Cancel button — always visible
            Button(action: {
                viewModel.cancelChat(message.id)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                    Text("Cancel")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.12))
                .foregroundColor(.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // "Move to Background" button — only visible after 60 seconds
            if showBackgroundButton {
                Button(action: {
                    viewModel.moveTaskToBackground(message.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11))
                        Text("Move to Background")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: showBackgroundButton)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        // Derive elapsed from message.timestamp (set when the placeholder
        // was created in sendChatMessage) instead of counting up from 0.
        // Without this, switching away and back to the session re-runs
        // .onAppear → startTimer → reset to 0 even though the actual
        // gateway-side run is still progressing, so "Thinking 23s"
        // became "Thinking 0s" every time the user clicked back.
        recomputeElapsed()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak viewModel] _ in
            DispatchQueue.main.async { [weak viewModel] in
                recomputeElapsed()
                // Auto-move to background after `autoBackgroundAfterSeconds`
                // (UserDefaults-backed, default 120). Returns nil if the
                // user disabled auto-background entirely.
                if let limit = viewModel?.autoBackgroundAfterSeconds,
                   elapsedSeconds >= limit,
                   let vm = viewModel,
                   vm.foregroundTaskIds.contains(message.id) {
                    vm.moveTaskToBackground(message.id)
                }
            }
        }
    }

    /// Set `elapsedSeconds` from the absolute task start time
    /// (`message.timestamp`) — wall-clock derived, so it survives view
    /// recreation across session switches.
    private func recomputeElapsed() {
        if let start = message.timestamp {
            elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }
}

// MARK: - Model Picker Row (right-sidebar SessionDetailsPanel)

/// Extracted into its own view so we can use the working
/// `@State + .onChange(of:)` pattern (mirrors `SubAgentsTabView`'s model
/// picker, which actually works). The previous inline `Binding(get:set:)`
/// in `SessionDetailsPanel.modelRow` looked correct but the picker's
/// selection often failed to fire `set:` in SwiftUI on macOS — net
/// result: dropdown opens, user picks an option, nothing happens.
///
/// Source-of-truth flow:
///   - external: `viewModel.availableAgents[i].model` (raw, "" means inherit)
///   - `@State selection`: kept in sync with external via `.onAppear` and
///     `.onChange(of: currentRawModel)`
///   - user picks → `.onChange(of: selection)` fires →
///     `viewModel.updateAgentModel(model:)` writes to disk → reload →
///     `currentRawModel` flips → external observer syncs `selection`.
private struct ModelPickerRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let currentRawModel: String
    let resolvedDefaultModel: String

    @State private var selection: String = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "cube.fill")
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            Picker("", selection: $selection) {
                if resolvedDefaultModel.isEmpty {
                    Text("Default (inherit)").tag("")
                } else {
                    Text("Default (\(resolvedDefaultModel))").tag("")
                }
                // Always include the currently-set model so the Picker
                // can render the active selection even if the available
                // list hasn't loaded yet or doesn't contain that id.
                if !currentRawModel.isEmpty
                   && !viewModel.availableModelsForSettings.contains(where: { $0.id == currentRawModel }) {
                    Text(SessionDetailsPanel.stripProviderPrefix(currentRawModel))
                        .tag(currentRawModel)
                }
                ForEach(viewModel.availableModelsForSettings) { m in
                    Text(SessionDetailsPanel.stripProviderPrefix(m.name)).tag(m.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onAppear { selection = currentRawModel }
        .onChange(of: currentRawModel) { newRaw in
            // External truth changed (agent switched, or another panel
            // wrote a different model). Sync our local @State.
            if selection != newRaw {
                selection = newRaw
            }
        }
        .onChange(of: selection) { newValue in
            // User picked something. Only write through when it differs
            // from the external raw — same guard as before, but now the
            // .onChange contract guarantees this fires even with
            // identity-shaped equality, unlike the manual Binding pattern.
            if newValue != currentRawModel {
                viewModel.updateAgentModel(model: newValue)
            }
        }
    }
}

// MARK: - Chat Bubble

/// Borderless message-action icon (copy / rewind) with a subtle per-icon hover
/// highlight — matches the macOS / Claude action-bar look. Row-level show/hide
/// (fade in on message hover) is handled by the parent via opacity.
/// Shared by the main chat bubbles and the Help assistant window.
struct MessageActionIcon: View {
    let systemName: String
    var tint: SwiftUI.Color = .secondary
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @State private var showTooltip = false
    @State private var tooltipTask: DispatchWorkItem?

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(tint)
                .frame(width: 22, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? SwiftUI.Color.primary.opacity(0.08) : SwiftUI.Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Claude-style tooltip instead of the native `.help()` — the system
        // tooltip's ~1.5s delay + OS styling felt unresponsive. A compact dark
        // pill fades in ~0.35s after the cursor settles, sits just above the
        // icon, and never intercepts clicks. VoiceOver still gets the label via
        // accessibilityLabel.
        .onHover { h in
            hovering = h
            tooltipTask?.cancel()
            if h {
                let task = DispatchWorkItem {
                    withAnimation(.easeInOut(duration: 0.1)) { showTooltip = true }
                }
                tooltipTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
            } else {
                showTooltip = false
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .accessibilityLabel(help)
        .overlay(alignment: .top) {
            if showTooltip {
                Text(help)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SwiftUI.Color(white: 0.15))
                            .shadow(color: SwiftUI.Color.black.opacity(0.28), radius: 4, y: 2)
                    )
                    .offset(y: -26)
                    .transition(.opacity)
                    .zIndex(100)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Tiny self-ticking label that prints "已运行 N 分" once a run crosses the
/// 1-minute mark. Used in the streaming-cancel row so users have a sense of
/// progress on long autonomous runs (browser automation, multi-step research)
/// instead of just a spinning indicator. Uses `TimelineView(.periodic)` so we
/// don't need a `Timer`/`@State` per bubble — SwiftUI refreshes the closure
/// every 30s and the rest of the bubble stays still.
///
/// HOTFIX v1.1.59: `from` MUST be a stable anchor. Was `from: .now`, which
/// is evaluated fresh on every body re-eval — SwiftUI then sees a new
/// `PeriodicTimelineSchedule` and re-subscribes its schedule. On a chat
/// with many active bubbles + high-frequency streaming deltas, that
/// constant re-subscription compounds into a main-thread SwiftUI body
/// avalanche (see Intel-Mac hang spindump, 17.7s, com.apple.WebKit.WebContent
/// × 10 + AG::Subgraph::update reentry). Anchoring `from` to the run's
/// `start` time (constant for this view's lifetime) keeps the schedule
/// stable: same `from`, same `by` → SwiftUI reuses one subscription.
private struct ElapsedSinceView: View {
    let start: Date?
    var body: some View {
        if let start = start {
            TimelineView(.periodic(from: start, by: 30)) { ctx in
                let minutes = Int(ctx.date.timeIntervalSince(start) / 60)
                if minutes >= 1 {
                    Text("已运行 \(minutes) 分")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    /// Rewind the session to (and including) this message. When set, a rewind
    /// button appears in the bubble toolbar.
    var onRewind: ((ChatMessage) -> Void)? = nil
    /// Cancel the in-flight run for this message. When set, a cancel button
    /// appears next to the streaming spinner so a run can be stopped mid-stream.
    var onCancel: ((ChatMessage) -> Void)? = nil
    @State private var isHovering = false
    @State private var cachedMediaURLs: [URL] = []
    @State private var lastMediaScanContent: String = ""

    /// Visual ack for the copy button — flips to `true` for ~1.5s after a
    /// successful clipboard write, swaps the icon to a green checkmark, and
    /// surfaces a "已复制" label. Without this, clicking the button gave
    /// zero feedback (a user-reported bug — they couldn't tell whether the
    /// copy actually fired).
    @State private var copied = false
    /// In-flight reset task for `copied`. Re-clicking the button while a
    /// previous ack is still showing should restart the 1.5s window rather
    /// than have both timers fight each other.
    @State private var copyResetTask: DispatchWorkItem?

    /// Pending "hide the action icons" task. The icons don't vanish the instant
    /// the cursor leaves the bubble — that made them impossible to reach
    /// ("悬停时间太短"). Instead we wait out a short grace period; moving the
    /// cursor back in (or onto the icons) cancels the hide so they stay put.
    @State private var hoverHideTask: DispatchWorkItem?

    /// Cached regex for media URL detection (compiled once, reused)
    private static let mediaFileRegex: NSRegularExpression? = {
        let mediaExtensions = [
            "mp4", "mov", "avi", "mkv", "webm", "m4v",
            "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff",
            "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff",
        ]
        let extPattern = mediaExtensions.joined(separator: "|")
        let filePattern = "(/[^\\s\"'`<>()\\[\\]]+\\.(?:\(extPattern)))(?=[\\s\"'`.,;:!?)\\]\\n]|$)"
        return try? NSRegularExpression(pattern: filePattern, options: [.caseInsensitive, .anchorsMatchLines])
    }()

    /// Format a message timestamp: "HH:mm" if the message is from today, or
    /// "MM-dd HH:mm" if it's older. Cached formatters keep this cheap on
    /// scroll — Date↦string allocation per row is fine but we don't want
    /// to spin up a fresh DateFormatter each time.
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dateAndTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    static func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return timeOnlyFormatter.string(from: date)
        }
        return dateAndTimeFormatter.string(from: date)
    }

    /// Scan for media file URLs — only called from .onChange, result stored in cachedMediaURLs
    private static func scanMediaURLs(in text: String) -> [URL] {
        guard let regex = mediaFileRegex else { return [] }
        var urls: [URL] = []
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            if let range = Range(captureRange, in: text) {
                let path = String(text[range])
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Timestamp — small, secondary, sits above the message body.
                // Hidden for legacy messages (nil timestamp) so we never
                // synthesize a bogus "now" for pre-existing chats.
                if let ts = message.timestamp {
                    Text(Self.formatTimestamp(ts))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Attachment thumbnails (user-attached files)
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                if !message.content.isEmpty {
                    // Bubble body — always use SwiftUI-native MarkdownUI,
                    // including for streaming. Previously we routed
                    // streaming to SelectableMarkdownView (WKWebView) on
                    // the assumption that re-parsing markdown on every
                    // token would saturate the main thread, BUT the
                    // WKWebView path has its own problems:
                    //   - Each token arrival triggers throttled HTML
                    //     rebuild → async load → JS height callback
                    //     pipeline. The bubble's reserved height is
                    //     based on an estimate, so for long content
                    //     (tables especially) you see a big empty dark
                    //     area while the HTML is in-flight, then it
                    //     suddenly "drops in" once didFinish + JS
                    //     measurement resolve.
                    //   - SwiftUI's body re-evaluates on every @Published
                    //     content change. With WKWebView re-loading
                    //     constantly during streaming, the visual flow
                    //     is "blank → loaded → blank → loaded".
                    // MarkdownUI parses synchronously inside body and
                    // renders SwiftUI views directly. The full content
                    // appears immediately on every update, no async
                    // round trip.
                    //
                    // Performance: stream deltas already arrive at ~100ms
                    // throttle (DashboardViewModel.sendChatMessage's
                    // throttle). At that cadence MarkdownUI re-parsing
                    // is fine on the main thread.
                    // Bubble + action row share ONE hover zone (the inner
                    // VStack's `.onHover`). A single source of truth for
                    // `isHovering` means moving the cursor from the bubble
                    // down onto the icons never crosses a "dead gap" that
                    // would flip hover off and hide the row mid-reach — the
                    // old two-`onHover` setup (bubble toggled true/false,
                    // row only set true) raced and dropped clicks.
                    //
                    // spacing:3 tucks the icons right under the bubble.
                    // NO negative padding: `.padding(.top, -6)` shifted the
                    // row's *visual* position up but left its hit-test
                    // region at the layout slot, so clicks landed in dead
                    // space ("点击没有反应"). Positive spacing keeps both
                    // aligned and keeps the row clear of the WKWebView's
                    // click-capturing frame above it.
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                        Group {
                            if message.role == .assistant {
                                // Single rendering path for the full message
                                // lifecycle. WKWebView is mounted on first
                                // render with the full HTML envelope already
                                // baked in (CSS + MathJax), then every
                                // streaming delta and the final terminal-
                                // state content land via JS DOM mutation —
                                // `document.body.innerHTML = ...` — so we
                                // never reload the page, never tear down the
                                // SwiftUI subtree, and never see the blank
                                // transition the hybrid Markdown↔WebView
                                // attempt produced. WebKit's selection model
                                // gives us cross-paragraph / list / table
                                // drag-select for free via the body's
                                // `-webkit-user-select: text`.
                                SelectableMarkdownView(content: message.content)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(10)
                                    .background(bubbleBackgroundColor)
                                    .cornerRadius(12)
                            } else {
                                Text(message.content)
                                    .padding(10)
                                    .background(bubbleBackgroundColor)
                                    .foregroundColor(.primary)
                                    .cornerRadius(12)
                                    .textSelection(.enabled)
                            }
                        }
                        .contextMenu {
                            Button(action: { performCopy(message.content) }) {
                                Label("Copy", systemImage: "square.on.square")
                            }
                        }

                        // Action row: copy + (assistant) rewind. Shown only
                        // for TERMINAL-state messages (streaming bubbles get
                        // the cancel row below instead). Hidden until the
                        // wrapper is hovered, then fades in; `copied` keeps
                        // the ✓ up briefly after the cursor leaves.
                        // `allowsHitTesting` is gated on visibility so the
                        // transparent row never silently eats clicks.
                        if !isStreamingState && !message.content.isEmpty {
                            HStack(spacing: 2) {
                                MessageActionIcon(
                                    systemName: copied ? "checkmark" : "square.on.square",
                                    tint: copied ? .green : .secondary,
                                    help: copied ? "已复制" : "复制",
                                    action: { performCopy(message.content) }
                                )
                                // Edit & resend only makes sense for the user's
                                // own messages (you edit your prompt, not the
                                // assistant's output), so the rewind icon is
                                // gated to .user bubbles.
                                if onRewind != nil && message.role == .user {
                                    MessageActionIcon(
                                        systemName: "arrow.uturn.backward",
                                        tint: .secondary,
                                        help: "编辑重发",
                                        action: { onRewind?(message) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                            .opacity(isHovering || copied ? 1.0 : 0.0)
                            .allowsHitTesting(isHovering || copied)
                            .animation(.easeInOut(duration: 0.15), value: isHovering)
                            .animation(.easeInOut(duration: 0.18), value: copied)
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            // Entered the bubble/toolbar zone — cancel any pending
                            // hide and reveal the icons right away.
                            hoverHideTask?.cancel()
                            hoverHideTask = nil
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovering = true
                            }
                        } else {
                            // Left the zone — keep the icons up for a grace period
                            // so the cursor has time to travel to them and click.
                            // Re-entering cancels this (see the `hovering` branch).
                            hoverHideTask?.cancel()
                            let task = DispatchWorkItem {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isHovering = false
                                }
                            }
                            hoverHideTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
                        }
                    }
                }

                // Streaming indicator — sub-bubble row showing the AI is
                // still writing. Sits directly under the bubble with a
                // small gap (no hover toolbar between them in streaming
                // state, so this looks like a continuation of the bubble
                // rather than a disconnected third widget).
                if message.role == .assistant && message.taskStatus == .loading && !message.content.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .controlSize(.small)
                        // Long-run feedback: show elapsed minutes once the run
                        // crosses 1 minute. Reduces "is it stuck?" anxiety,
                        // gives the user signal before deciding to cancel.
                        // TimelineView refreshes every 30s so the number
                        // advances without any per-bubble state/timer.
                        ElapsedSinceView(start: message.timestamp)
                        // Cancel during ACTIVE streaming. The ThinkingIndicator's
                        // cancel only shows while waiting for the first token
                        // (content empty); once text starts flowing the message
                        // renders here, so without this the user couldn't stop a
                        // long run mid-stream. Aborting keeps the partial output.
                        if onCancel != nil {
                            Button(action: { onCancel?(message) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 11))
                                    Text("取消")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.12))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help("取消当前执行（保留已生成的部分）")
                        }
                    }
                    .padding(.top, 2)
                }

                // Detected media files from assistant response
                if !cachedMediaURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cachedMediaURLs, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                // Background task indicator
                if message.taskStatus == .background {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Running in background...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        // Background runs are cancellable too. `cancelChat`
                        // already clears BOTH foreground and background tracking
                        // and aborts by the run's own id, but the .background
                        // state had no cancel affordance — so a task that the
                        // 120s timer auto-flipped to background (or any long run
                        // the user navigated away from and back to) couldn't be
                        // stopped from the UI. Same abort path as the streaming
                        // 取消 button; partial output is kept.
                        if onCancel != nil {
                            Button(action: { onCancel?(message) }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 11))
                                    Text("取消")
                                        .font(.caption)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.12))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .help("取消后台执行（保留已生成的部分）")
                        }
                    }
                    .padding(.top, 2)
                }

                // Cancelled task indicator
                if message.taskStatus == .cancelled {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Cancelled")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 2)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .onAppear {
            // Initial scan for media URLs when bubble first appears
            if message.role == .assistant && lastMediaScanContent != message.content {
                lastMediaScanContent = message.content
                cachedMediaURLs = ChatBubble.scanMediaURLs(in: message.content)
            }
        }
        .onChange(of: message.content) { newContent in
            // Only re-scan for media URLs when content actually changes
            guard message.role == .assistant, newContent != lastMediaScanContent else { return }
            lastMediaScanContent = newContent
            cachedMediaURLs = ChatBubble.scanMediaURLs(in: newContent)
        }
    }

    private var bubbleBackgroundColor: SwiftUI.Color {
        message.role == .user
            ? Color.gray.opacity(0.14)
            : Color(NSColor.controlBackgroundColor)
    }

    /// True while the message is still being generated — covers both the
    /// foreground `.loading` and `.background` (running detached) statuses.
    /// Used to gate the hover toolbar; we don't want a stale "Copy
    /// half-streamed text" affordance.
    private var isStreamingState: Bool {
        message.role == .assistant
            && (message.taskStatus == .loading || message.taskStatus == .background)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copy + show the "已复制" ack for 1.5s. Both the bubble toolbar
    /// button and the contextMenu "Copy" item route through here so the
    /// feedback is consistent across entry points.
    private func performCopy(_ text: String) {
        copyToClipboard(text)
        withAnimation(.easeInOut(duration: 0.18)) {
            copied = true
        }
        // Restart the 1.5s reset window on every click so rapid
        // repeated clicks don't get clipped by a stale reset firing
        // mid-animation.
        copyResetTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                copied = false
            }
        }
        copyResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}

// MARK: - Typewriter Text for Streaming

class TypewriterEngine: ObservableObject {
    @Published var displayed: String = ""
    private var target: String = ""
    private var visibleLength: Int = 0
    private var timer: Timer?

    func setTarget(_ text: String) {
        target = text
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if visibleLength < target.count {
            // Type 15 chars at a time to reduce CPU usage during long streaming output
            visibleLength = min(visibleLength + 15, target.count)
            displayed = String(target.prefix(visibleLength))
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

struct TypewriterText: View {
    let fullText: String
    @StateObject private var engine = TypewriterEngine()

    var body: some View {
        Text(engine.displayed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            engine.setTarget(fullText)
        }
        .onChange(of: fullText) { newText in
            engine.setTarget(newText)
        }
        .onDisappear {
            engine.stop()
        }
    }
}

// MARK: - Attachment Thumbnail (in chat bubble)

struct AttachmentThumbnail: View {
    let url: URL

    private var fileType: AttachmentFileType {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(ext) {
            return .video
        } else if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff"].contains(ext) {
            return .audio
        }
        return .other
    }

    enum AttachmentFileType {
        case image, video, audio, other
    }

    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            switch fileType {
            case .image:
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(8)
                } else {
                    fileIcon
                }
            case .video:
                InlineVideoPlayer(url: url)
            case .audio:
                InlineAudioPlayer(url: url)
            case .other:
                fileIcon
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var fileIcon: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "json", "xml", "yaml", "yml", "toml", "ini", "env", "conf", "properties": return "curlybraces"
        case "md", "txt", "log": return "doc.plaintext"
        case "xmind": return "brain.head.profile"
        case "py", "js", "ts", "swift", "java", "go", "rs", "c", "cpp", "h",
             "rb", "php", "sh", "sql", "r", "jsx", "tsx", "vue": return "chevron.left.forwardslash.chevron.right"
        case "html", "htm", "css", "scss": return "globe"
        case "ipynb": return "book.closed.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Inline Video Player

struct InlineVideoPlayer: View {
    let url: URL
    @State private var showPlayer = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if showPlayer {
                NativeVideoPlayerView(url: url)
                    .frame(width: 280, height: 180)
                    .cornerRadius(8)
            } else {
                // Thumbnail placeholder with play button
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 280, height: 180)
                        Image(systemName: "film")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                    }

                    // Play button overlay
                    Button(action: { showPlayer = true }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)

                    // File name
                    VStack {
                        Spacer()
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                .frame(width: 280, height: 180)
                .cornerRadius(8)
            }
        }
        .onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        Task.detached {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 560, height: 360)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    thumbnail = nsImage
                }
            }
        }
    }
}

// MARK: - Native Video Player (NSViewRepresentable)

struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - Inline Audio Player

struct InlineAudioPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 10) {
            // Play/Pause button
            Button(action: { togglePlayback() }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // File name
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: duration > 0 ? geo.size.width * (currentTime / duration) : 0, height: 4)
                    }
                }
                .frame(height: 4)

                // Time labels
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .onDisappear { cleanup() }
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer

        // Get duration
        Task {
            if let asset = avPlayer.currentItem?.asset {
                let dur = try? await asset.load(.duration)
                if let dur = dur {
                    await MainActor.run {
                        duration = CMTimeGetSeconds(dur)
                    }
                }
            }
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }

        // Reset when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            avPlayer.seek(to: .zero)
            currentTime = 0
        }
    }

    private func togglePlayback() {
        ensurePlayer()
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Attachment Preview (in input bar)

struct AttachmentPreview: View {
    let url: URL
    let onRemove: () -> Void

    private var isImage: Bool {
        // Directories never read as images, even if the path happens to end in .png.
        if isDirectory { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext)
    }

    /// True iff the URL points at an existing directory. Stat'd once per render —
    /// fine for the small N of attached items shown in the chip strip.
    private var isDirectory: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isImage, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: fileIconName)
                        .font(.system(size: 20))
                        .foregroundColor(isDirectory ? .accentColor : .secondary)
                    Text(url.lastPathComponent)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 56)
                }
                .frame(width: 60, height: 60)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var fileIconName: String {
        // Folder takes precedence over extension — `~/Projects/foo.bar` is still
        // a folder; rendering it as a generic doc icon would be misleading.
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "mp3", "wav", "m4a", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv", "webm": return "film.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Success Toast

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))

            Text(message)
                .font(.body)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
    }
}

// MARK: - Diagnostics Sheet

struct DiagnosticsSheet: View {
    let report: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Diagnostics Report")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Report content
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Brand Text

struct BrandTextView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            Text("GetClaw")
                .foregroundColor(colorScheme == .dark ? .white : .black)
            Text("Hub")
                .foregroundColor(.red)
        }
        .font(.title2)
        .fontWeight(.bold)
    }
}

// MARK: - Selectable Markdown View (WKWebView-based)

// MARK: - Native Markdown View (lightweight, no WKWebView)

/// Renders markdown using SwiftUI's native AttributedString.
/// Zero WKWebView overhead — no process spawn, no HTML parsing, no height measurement.
struct NativeMarkdownView: View {
    let content: String

    var body: some View {
        Text(attributedContent)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content)
    }
}

// MARK: - Selectable Markdown View (WKWebView-based, used by HelpAssistantWindow)

import WebKit

/// Cache for rendered Markdown HTML to avoid repeated parsing during SwiftUI layout cycles.
private let markdownHTMLCache = NSCache<NSString, NSString>()
/// Cache for measured heights to avoid 22pt → actual height jump when LazyVStack recreates views.
private let markdownHeightCache = NSCache<NSString, NSNumber>()

/// Renders markdown as selectable rich text via WKWebView. Supports
/// free multi-line drag-selection across paragraphs, lists and tables
/// (HTML body carries `-webkit-user-select: text` and WebKit's native
/// selection model handles cross-block ranges).
///
/// Streaming updates: `_MarkdownWebView` mutates `document.body.innerHTML`
/// via JS on every content delta — no `loadHTMLString` reload, no flash.
/// The 500 ms throttle the previous version had was a workaround for
/// the reload-flash; with DOM mutations the per-update cost is small
/// (~5–30 ms for markdown→HTML build + a single JS bridge call), so we
/// just pipe `content` straight through and let SwiftUI's natural body
/// re-eval rate (bounded by the upstream `sendChatMessage` throttle of
/// ~100 ms) drive updates.
struct SelectableMarkdownView: View {
    let content: String
    var onReady: (() -> Void)? = nil
    @State private var height: CGFloat

    init(content: String, onReady: (() -> Void)? = nil) {
        self.content = content
        self.onReady = onReady
        // Use cached height to prevent 22pt → actual height jump on LazyVStack recreation
        let heightKey = "\(content.hashValue)" as NSString
        if let cached = markdownHeightCache.object(forKey: heightKey) {
            _height = State(initialValue: CGFloat(cached.doubleValue))
        } else {
            // Estimate initial height from content length so the frame is
            // roughly the right size before WKWebView reports its measured
            // height. Without this estimate, the frame is locked at 22pt
            // (one line) until the WebView's JS callback fires — and on
            // macOS 26 we've observed that callback can stall for several
            // seconds (or never arrive), leaving content visibly clipped
            // to a sliver and the bubble appearing empty.
            //
            // Heuristic: ~60 chars per visual line, ~18pt line height,
            // 20pt total padding. Newlines count for an extra line each.
            // Capped at 600pt so we don't reserve a huge frame for a
            // message that turns out to be short.
            let lineCount = max(1, content.split(separator: "\n").count)
            let estimatedLines = max(Double(lineCount),
                                     ceil(Double(content.count) / 60.0))
            // Line-height only (≈13px × 1.6 ≈ 21pt). The bubble's 10pt padding
            // is applied OUTSIDE this view (in ChatBubble), so DON'T add it
            // here — the old `+ 20` double-counted the padding, and when the
            // async JS height measurement is delayed (LazyVStack rows mount at
            // width 0), that too-tall estimate stuck and left ~16pt of phantom
            // space below the text, pushing the action icons far away. A small
            // +4 guards single-line wraps from a 1px clip before measurement.
            let estimatedHeight = min(600.0, estimatedLines * 21.0 + 4.0)
            _height = State(initialValue: CGFloat(max(21.0, estimatedHeight)))
        }
    }

    var body: some View {
        _MarkdownWebView(content: content, dynamicHeight: $height)
            .frame(height: max(height, 22))
            .onChange(of: height) { newHeight in
                if newHeight > 22 {
                    onReady?()
                }
            }
    }
}

/// WKWebView subclass that forwards scroll events to the parent view,
/// allowing the outer SwiftUI ScrollView to handle page scrolling.
private class ScrollThroughWebView: WKWebView {
    /// Called when the view's width changes (throttled), for height re-measurement.
    var onResize: (() -> Void)?
    private var resizeWorkItem: DispatchWorkItem?

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        super.setFrameSize(newSize)
        // Only trigger on width changes (height is managed by dynamicHeight binding)
        if abs(newSize.width - oldWidth) > 1 {
            resizeWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.onResize?()
            }
            resizeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }
}

private struct _MarkdownWebView: NSViewRepresentable {
    let content: String
    @Binding var dynamicHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(dynamicHeight: $dynamicHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = ScrollThroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Wire resize callback to re-measure height when window width changes
        webView.onResize = { [weak webView, weak coordinator = context.coordinator] in
            guard let webView = webView, let coordinator = coordinator else { return }
            coordinator.remeasureHeight(webView: webView)
        }

        let isDark = (colorScheme == .dark)

        // Always paint the full HTML envelope (CSS + MathJax + body) on
        // first mount — synchronously, no transparent shell, no async
        // round trip. This gives the WKWebView a complete styled
        // document immediately. Every subsequent content delta updates
        // the body via JS DOM mutation (see `updateNSView` →
        // `Coordinator.injectBodyHTML`), so we never reload the page,
        // never flash, and never see the "blank then re-render" the
        // previous loadHTMLString-on-every-update path produced.
        //
        // For empty starting content (streaming placeholder before the
        // first delta), `MarkdownHTML.buildHTML("")` is essentially the
        // envelope alone — cheap to build, fine to display as an empty
        // bubble for the brief moment before the first delta arrives.
        let contentHash = content.hashValue
        let cacheKey = "\(isDark ? "d" : "l"):\(contentHash)" as NSString
        let html: String
        if let cachedHTML = markdownHTMLCache.object(forKey: cacheKey) {
            html = cachedHTML as String
        } else {
            html = MarkdownHTML.buildHTML(content, isDark: isDark)
            markdownHTMLCache.setObject(html as NSString, forKey: cacheKey)
        }
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastSource = content
        context.coordinator.lastIsDark = isDark
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = (colorScheme == .dark)
        let coordinator = context.coordinator

        // Bail when nothing meaningful changed (SwiftUI re-evaluates
        // bodies aggressively).
        guard content != coordinator.lastSource || isDark != coordinator.lastIsDark else { return }

        // Theme change requires a full reload — the CSS (text color,
        // borders, code background) is embedded in the HTML <style>
        // block, not driven by CSS variables. Rare event (user toggling
        // system appearance); a momentary reload-flash is acceptable.
        let isThemeChange = (isDark != coordinator.lastIsDark)
        coordinator.lastSource = content
        coordinator.lastIsDark = isDark
        coordinator.buildGeneration += 1
        let myGen = coordinator.buildGeneration
        let currentContent = content

        coordinator.buildQueue.async { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            if myGen != coordinator.buildGeneration { return }

            let contentHash = currentContent.hashValue
            let cacheKey = "\(isDark ? "d" : "l"):\(contentHash)" as NSString

            if isThemeChange {
                // Build (or fetch) full HTML, reload entire page.
                let html: String
                if let cached = markdownHTMLCache.object(forKey: cacheKey) {
                    html = cached as String
                } else {
                    html = MarkdownHTML.buildHTML(currentContent, isDark: isDark)
                    markdownHTMLCache.setObject(html as NSString, forKey: cacheKey)
                }
                DispatchQueue.main.async {
                    if myGen != coordinator.buildGeneration { return }
                    coordinator.isPageLoaded = false
                    coordinator.pendingBodyHTML = nil
                    webView.loadHTMLString(html, baseURL: nil)
                }
                return
            }

            // Content-only delta. Build just the <body> innards and
            // poke them into the live document via JS. No navigation,
            // no parse-from-scratch, no flash. CSS / MathJax / scripts
            // stay loaded.
            let bodyHTML = MarkdownHTML.convertMarkdown(currentContent)

            // Keep the full-HTML cache warm too, so a future cold mount
            // (LazyVStack recycling, theme toggle and back, etc.) hits
            // the sync path in `makeNSView`.
            if markdownHTMLCache.object(forKey: cacheKey) == nil {
                let fullHTML = MarkdownHTML.buildHTML(currentContent, isDark: isDark)
                markdownHTMLCache.setObject(fullHTML as NSString, forKey: cacheKey)
            }

            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator = coordinator else { return }
                if myGen != coordinator.buildGeneration { return }

                if !coordinator.isPageLoaded {
                    // Initial navigation from makeNSView still in flight.
                    // Stash; `didFinish` will inject when ready.
                    coordinator.pendingBodyHTML = bodyHTML
                    return
                }
                coordinator.injectBodyHTML(bodyHTML, into: webView) {
                    coordinator.remeasureHeight(webView: webView)
                }
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastSource: String = ""
        var lastIsDark: Bool = false
        /// Serial queue ensures only one buildHTML runs at a time
        let buildQueue = DispatchQueue(label: "markdown.build", qos: .utility)
        /// Incremented on each loadHTML call; stale builds check this to skip work
        var buildGeneration: Int = 0
        /// True once the WKWebView has finished its initial navigation —
        /// only then are JS DOM mutations safe to evaluate. Updates that
        /// arrive before this flips are stashed in `pendingBodyHTML` and
        /// flushed by `webView(_:didFinish:)`.
        var isPageLoaded: Bool = false
        /// Latest body-HTML waiting on the first navigation to finish.
        /// Always holds the freshest value; older stashes are overwritten.
        var pendingBodyHTML: String?
        private var dynamicHeight: Binding<CGFloat>

        init(dynamicHeight: Binding<CGFloat>) {
            self.dynamicHeight = dynamicHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let pending = pendingBodyHTML {
                pendingBodyHTML = nil
                injectBodyHTML(pending, into: webView) { [weak self] in
                    self?.measureHeight(webView: webView, attempt: 0)
                }
            } else {
                measureHeight(webView: webView, attempt: 0)
            }
        }

        /// Replace `document.body.innerHTML` with `bodyHTML` and re-run
        /// MathJax typesetting. Body HTML is shipped over the JS bridge
        /// as a JSON-encoded array element so all escaping (quotes,
        /// backslashes, newlines, unicode) is handled by Foundation —
        /// no fragile manual string mangling.
        func injectBodyHTML(_ bodyHTML: String, into webView: WKWebView, completion: (() -> Void)? = nil) {
            guard let data = try? JSONSerialization.data(withJSONObject: [bodyHTML]),
                  let jsonStr = String(data: data, encoding: .utf8) else {
                completion?()
                return
            }
            let js = """
            (function() {
                var arr = \(jsonStr);
                document.body.innerHTML = arr[0];
                if (window.MathJax && window.MathJax.typesetPromise) {
                    window.MathJax.typesetPromise([document.body]).catch(function(){});
                }
            })();
            """
            webView.evaluateJavaScript(js) { _, _ in
                completion?()
            }
        }

        /// Measure content height, retrying if the WKWebView hasn't received
        /// its layout width yet (which would produce an inflated height).
        private func measureHeight(webView: WKWebView, attempt: Int) {
            // Retry until the WebView reports a real layout width. LazyVStack
            // rows can mount at width 0, and WebKit's body.clientWidth lags the
            // native frame by a few runloop ticks. The old code gave up after
            // 2 tries — if width was still 0 then, the (too-tall) estimate
            // stuck forever, leaving phantom space below the text and pushing
            // the action icons far from the message. Retry ~12× over ~2.4s so a
            // freshly-scrolled-in bubble always converges to its true height.
            let maxAttempts = 12
            guard attempt < maxAttempts else { return }
            let delay: TimeInterval = attempt == 0 ? 0.05 : 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                self.evaluateHeight(webView: webView) { newHeight, width in
                    if width > 10 {
                        self.applyHeight(newHeight)
                    } else {
                        // Width still ~0, layout not ready — keep retrying.
                        self.measureHeight(webView: webView, attempt: attempt + 1)
                    }
                }
            }
        }

        /// Re-measure height (called on width change / scroll-in). Delegates to
        /// the retrying measureHeight so a width-0 mount still converges.
        func remeasureHeight(webView: WKWebView) {
            measureHeight(webView: webView, attempt: 0)
        }

        private func evaluateHeight(webView: WKWebView, completion: @escaping (CGFloat, CGFloat) -> Void) {
            let js = "JSON.stringify({h:Math.ceil(document.body.scrollHeight),w:document.body.clientWidth})"
            webView.evaluateJavaScript(js) { result, _ in
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let h = json["h"] as? CGFloat,
                      let w = json["w"] as? CGFloat, h > 0 else { return }
                DispatchQueue.main.async {
                    // +1 guards against sub-pixel scrollHeight under-report
                    // without leaving a visible gap below the text (was +4).
                    completion(h + 1, w)
                }
            }
        }

        private func applyHeight(_ newHeight: CGFloat) {
            // Only update if height actually changed to avoid SwiftUI re-render loop
            if abs(dynamicHeight.wrappedValue - newHeight) > 1 {
                dynamicHeight.wrappedValue = newHeight
            }
            // Cache height for LazyVStack recreation
            let heightKey = "\(lastSource.hashValue)" as NSString
            markdownHeightCache.setObject(NSNumber(value: Double(newHeight)), forKey: heightKey)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Markdown → HTML

enum MarkdownHTML {
    // MARK: - Cached Regex Patterns (Performance optimization)

    /// Cached regex for display math patterns ($$...$$)
    private static let displayMathRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\$\\$([\\s\\S]*?)\\$\\$")
    }()

    /// Cached regex for image markdown ![alt](url)
    private static let imageRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)")
    }()

    /// Cached regex for link markdown [text](url)
    private static let linkRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    }()

    /// Cached regex for bold **text** or __text__
    private static let boldAsteriskRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    }()

    private static let boldUnderscoreRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "__(.+?)__")
    }()

    /// Cached regex for italic *text* or _text_
    private static let italicAsteriskRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
    }()

    private static let italicUnderscoreRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?<![\\w])_(.+?)_(?![\\w])")
    }()

    /// Cached regex for strikethrough ~~text~~
    private static let strikethroughRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "~~(.+?)~~")
    }()

    /// Cached regex for inline code `text`
    private static let inlineCodeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "`([^`]+)`")
    }()

    static func buildHTML(_ markdown: String, isDark: Bool) -> String {
        let textColor = isDark ? "#e0e0e0" : "#1d1d1f"
        let codeBg = isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.10)"
        let borderColor = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"
        let tableBg = isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.02)"
        let blockquoteBorder = isDark ? "#555" : "#ccc"
        let blockquoteColor = isDark ? "#aaa" : "#666"
        let linkColor = isDark ? "#6cb6ff" : "#0366d6"

        let body = convertMarkdown(markdown)

        return """
        <html><head><meta charset='utf-8'>
        <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
        <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
        <script>
        window.MathJax = {
            tex: {
                // Inline math uses LaTeX-style \\( ... \\) ONLY — never single
                // '$'. Customer-support content is full of currency ("$5",
                // "$5 ... $10 discount"), and treating '$' as an inline-math
                // delimiter made MathJax parse the text between two dollar
                // signs as a formula — e.g. it hit a literal '#' and rendered
                // the red error "You can't use 'macro parameter character #'
                // in math mode" right in the chat bubble. \\( ... \\) never
                // collides with natural text.
                inlineMath: [['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                processEscapes: true
            },
            svg: {
                fontCache: 'global'
            }
        };
        </script>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { background: transparent; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 13px; color: \(textColor); line-height: 1.6;
            -webkit-user-select: text; cursor: text;
            word-wrap: break-word; overflow-wrap: break-word;
            overflow: hidden;
        }
        /* Hug the content: strip the first/last block's outer margins so the
           measured WebView height matches the text exactly. Without this the
           leading/trailing <p> margins (+ body padding) left phantom whitespace
           inside the bubble, pushing the action icons far below the message. */
        body > :first-child { margin-top: 0 !important; }
        body > :last-child { margin-bottom: 0 !important; }
        h1 { font-size: 20px; font-weight: 700; margin: 12px 0 6px; }
        h2 { font-size: 17px; font-weight: 700; margin: 10px 0 5px; }
        h3 { font-size: 15px; font-weight: 600; margin: 8px 0 4px; }
        h4, h5, h6 { font-size: 14px; font-weight: 600; margin: 6px 0 3px; }
        p { margin: 6px 0; }
        code {
            font-family: Menlo, Monaco, monospace; font-size: 12px;
            background: \(codeBg); padding: 1px 4px; border-radius: 3px;
        }
        pre {
            background: \(codeBg); padding: 10px; border-radius: 6px;
            overflow-x: auto; margin: 8px 0;
        }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; margin: 8px 0; }
        th, td { border: 1px solid \(borderColor); padding: 5px 10px; text-align: left; }
        th { font-weight: 600; }
        tr:nth-child(even) { background: \(tableBg); }
        blockquote {
            border-left: 3px solid \(blockquoteBorder);
            margin: 6px 0; padding: 2px 10px; color: \(blockquoteColor);
        }
        a { color: \(linkColor); text-decoration: none; }
        ul, ol { padding-left: 20px; margin: 4px 0; }
        li { margin: 2px 0; }
        hr { border: none; border-top: 1px solid \(borderColor); margin: 10px 0; }
        img { max-width: 100%; }
        .math-formula { margin: 8px 0; }
        </style></head><body>\(body)</body></html>
        """
    }

    // MARK: - Markdown → HTML conversion

    static func convertMarkdown(_ markdown: String) -> String {
        // Extract & preserve display-math blocks ($$...$$) so markdown
        // inline processing doesn't mangle their contents (e.g. `a_b`
        // becoming italic). We deliberately DO NOT extract single-'$'
        // inline math — '$' is currency in customer-support content, and
        // protecting/round-tripping "$5 ... $10" as a formula is exactly
        // what produced the MathJax "macro parameter character #" error.
        // Real inline math is delimited \\( ... \\) (see the MathJax
        // config in buildHTML) and needs no markdown protection.
        var processedMarkdown = markdown
        var mathPlaceholders: [String: String] = [:]
        var mathCounter = 0

        // Extract display math blocks ($$...$$) first
        if let regex = displayMathRegex {
            let nsString = processedMarkdown as NSString
            let matches = regex.matches(in: processedMarkdown, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if let mathRange = Range(match.range, in: processedMarkdown) {
                    let placeholder = ":MATHDISPLAY\(mathCounter):"
                    let formula = String(processedMarkdown[mathRange])
                    mathPlaceholders[placeholder] = formula
                    processedMarkdown.replaceSubrange(mathRange, with: placeholder)
                    mathCounter += 1
                }
            }
        }

        let lines = processedMarkdown.components(separatedBy: "\n")
        // Pre-trim all lines once to avoid repeated trimming in inner loops
        let trimmedLines = lines.map { fastTrim($0) }
        var html = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = trimmedLines[i]

            // Code block
            if startsWithBytes(trimmed, 0x60, 0x60, 0x60) { // ```
                var codeContent = ""
                var closed = false
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if startsWithBytes(trimmedLines[i], 0x60, 0x60, 0x60) { // ```
                        i += 1
                        closed = true
                        break
                    }
                    if !codeContent.isEmpty { codeContent += "\n" }
                    codeContent += codeLine
                    i += 1
                }
                html += "<pre><code>\(escapeHTML(codeContent))</code></pre>"
                // If unclosed, remaining lines were consumed — content is already in codeContent
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Table: starts with | and contains |
            if startsWithByte(trimmed, 0x7C) && trimmed.contains("|") { // |
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = trimmedLines[i]
                    if startsWithByte(tl, 0x7C) && tl.contains("|") {
                        tableLines.append(tl)
                        i += 1
                    } else {
                        break
                    }
                }
                html += renderTable(tableLines)
                continue
            }

            // Heading: # to ######
            if startsWithByte(trimmed, 0x23) { // #
                // Fast UTF-8 scan: count '#' then expect space
                var hashCount = 0
                let tUtf8 = trimmed.utf8
                var hIdx = tUtf8.startIndex
                while hIdx < tUtf8.endIndex && tUtf8[hIdx] == 0x23 { // '#'
                    hashCount += 1
                    hIdx = tUtf8.index(after: hIdx)
                }
                if hashCount >= 1 && hashCount <= 6 && hIdx < tUtf8.endIndex && tUtf8[hIdx] == 0x20 {
                    let headingText = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashCount + 1)...])
                    html += "<h\(hashCount)>\(processInline(headingText, mathPlaceholders: mathPlaceholders))</h\(hashCount)>"
                    i += 1
                    continue
                }
            }

            // Horizontal rule — require only dashes/stars/underscores + spaces, at least 3 chars
            if trimmed.utf8.count >= 3 && isHorizontalRule(trimmed) {
                html += "<hr>"
                i += 1
                continue
            }

            // Blockquote
            if startsWithByte(trimmed, 0x3E) { // >
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = trimmedLines[i]
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                        i += 1
                    } else if ql == ">" {
                        quoteLines.append("")
                        i += 1
                    } else if ql.hasPrefix(">") {
                        // Handle >text without space after >
                        quoteLines.append(String(ql.dropFirst(1)))
                        i += 1
                    } else {
                        break
                    }
                }
                html += "<blockquote>\(quoteLines.map { processInline($0, mathPlaceholders: mathPlaceholders) }.joined(separator: "<br>"))</blockquote>"
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                html += "<ul>"
                while i < lines.count {
                    let li = trimmedLines[i]
                    if isUnorderedListItem(li) {
                        html += "<li>\(processInline(String(li.dropFirst(2)), mathPlaceholders: mathPlaceholders))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ul>"
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                html += "<ol>"
                while i < lines.count {
                    let li = trimmedLines[i]
                    if let content = orderedListContent(li) {
                        html += "<li>\(processInline(content, mathPlaceholders: mathPlaceholders))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ol>"
                continue
            }

            // Regular paragraph — collect consecutive non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let pl = trimmedLines[i]
                if pl.isEmpty || startsWithBytes(pl, 0x60, 0x60, 0x60) || startsWithByte(pl, 0x23)
                    || startsWithByte(pl, 0x7C) || startsWithByte(pl, 0x3E)
                    || isUnorderedListItem(pl) || isOrderedListItem(pl)
                    || isHorizontalRule(pl) {
                    break
                }
                paraLines.append(processInline(pl, mathPlaceholders: mathPlaceholders))
                i += 1
            }
            if !paraLines.isEmpty {
                html += "<p>\(paraLines.joined(separator: "<br>"))</p>"
            } else {
                // Safety: if no pattern matched and paragraph collector didn't consume the line,
                // skip it to prevent infinite loop (e.g., a lone "#" without heading text)
                i += 1
            }
        }

        // Restore all math placeholders
        for (placeholder, formula) in mathPlaceholders {
            html = html.replacingOccurrences(of: placeholder, with: formula)
        }

        return html
    }

    // MARK: - Helpers

    /// Fast check if string starts with given ASCII byte. Uses withCString for zero generic overhead.
    @inline(__always)
    private static func startsWithByte(_ s: String, _ byte: UInt8) -> Bool {
        return s.withCString { ptr in
            UInt8(bitPattern: ptr[0]) == byte
        }
    }

    /// Fast check if string starts with given ASCII bytes. Uses withCString for zero generic overhead.
    @inline(__always)
    private static func startsWithBytes(_ s: String, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Bool {
        return s.withCString { ptr in
            UInt8(bitPattern: ptr[0]) == b0 && UInt8(bitPattern: ptr[1]) == b1 && UInt8(bitPattern: ptr[2]) == b2
        }
    }

    /// Fast whitespace trim using direct UTF-8 byte access.
    /// Avoids CFCharacterSetIsLongCharacterMember and generic iterator/subscript overhead in -Onone.
    /// Only trims ASCII whitespace which matches Markdown semantics.
    private static func fastTrim(_ s: String) -> String {
        // Use withUTF8 for direct pointer access — zero overhead, no generic dispatch
        return s.withCString { cstr -> String in
            var len = 0
            while cstr[len] != 0 { len += 1 }
            guard len > 0 else { return "" }
            var lo = 0
            var hi = len - 1
            while lo <= hi {
                let b = UInt8(bitPattern: cstr[lo])
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { lo += 1 }
                else { break }
            }
            guard lo <= hi else { return "" }
            while hi > lo {
                let b = UInt8(bitPattern: cstr[hi])
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { hi -= 1 }
                else { break }
            }
            if lo == 0 && hi == len - 1 { return s }
            let buf = UnsafeBufferPointer(
                start: UnsafeRawPointer(cstr.advanced(by: lo))
                    .assumingMemoryBound(to: UInt8.self),
                count: hi - lo + 1
            )
            return String(decoding: buf, as: UTF8.self)
        }
    }

    private static func isHorizontalRule(_ s: String) -> Bool {
        return s.withCString { ptr in
            var dashes = 0, stars = 0, underscores = 0
            var i = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                switch b {
                case 0x2D: dashes += 1
                case 0x2A: stars += 1
                case 0x5F: underscores += 1
                case 0x20: break
                default: return false
                }
                i += 1
            }
            let total = dashes + stars + underscores
            return total >= 3 && (dashes == total || stars == total || underscores == total)
        }
    }

    private static func isUnorderedListItem(_ s: String) -> Bool {
        return s.withCString { ptr in
            let first = UInt8(bitPattern: ptr[0])
            let second = UInt8(bitPattern: ptr[1])
            return second == 0x20 && (first == 0x2D || first == 0x2A || first == 0x2B)
        }
    }

    private static func isOrderedListItem(_ s: String) -> Bool {
        return s.withCString { ptr in
            var i = 0
            var digitCount = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                if b >= 0x30 && b <= 0x39 {
                    digitCount += 1; i += 1
                } else if b == 0x2E && digitCount > 0 {
                    return UInt8(bitPattern: ptr[i + 1]) == 0x20
                } else {
                    return false
                }
            }
            return false
        }
    }

    private static func orderedListContent(_ s: String) -> String? {
        return s.withCString { ptr in
            var i = 0
            var digitCount = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                if b >= 0x30 && b <= 0x39 {
                    digitCount += 1; i += 1
                } else if b == 0x2E && digitCount > 0 {
                    guard UInt8(bitPattern: ptr[i + 1]) == 0x20 else { return nil }
                    // Return content after "N. "
                    return String(cString: ptr.advanced(by: i + 2))
                } else {
                    return nil
                }
            }
            return nil
        }
    }

    private static func renderTable(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        var html = "<table>"
        var headerDone = false
        for line in lines {
            let inner = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // Check if separator row
            let isSeparator = cells.allSatisfy { cell in
                let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                return stripped.isEmpty && !cell.isEmpty
            }
            if isSeparator {
                headerDone = true
                continue
            }
            let tag = !headerDone ? "th" : "td"
            html += "<tr>" + cells.map { "<\(tag)>\(processInline($0))</\(tag)>" }.joined() + "</tr>"
        }
        html += "</table>"
        return html
    }

    // MARK: - Inline markdown processing

    private static func processInline(_ text: String, mathPlaceholders: [String: String] = [:]) -> String {
        var result = escapeHTML(text)
        // Fast path: skip regex if no markdown-related characters present
        let hasMarkdownChars = result.utf8.contains(where: { byte in
            byte == 0x5B    // '['  (links/images)
            || byte == 0x2A // '*'  (bold/italic)
            || byte == 0x5F // '_'  (bold/italic)
            || byte == 0x7E // '~'  (strikethrough)
            || byte == 0x60 // '`'  (inline code)
            || byte == 0x21 // '!'  (images)
        })
        guard hasMarkdownChars else { return result }
        // Images ![alt](url)
        if let regex = imageRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<img src=\"$2\" alt=\"$1\">")
        }
        // Links [text](url)
        if let regex = linkRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<a href=\"$2\">$1</a>")
        }
        // Bold **text**
        if let regex = boldAsteriskRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1</strong>")
        }
        // Bold __text__
        if let regex = boldUnderscoreRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1</strong>")
        }
        // Italic *text*
        if let regex = italicAsteriskRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1</em>")
        }
        // Italic _text_
        if let regex = italicUnderscoreRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1</em>")
        }
        // Strikethrough ~~text~~
        if let regex = strikethroughRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<s>$1</s>")
        }
        // Inline code `text`
        if let regex = inlineCodeRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<code>$1</code>")
        }
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Agent Settings Panel

private struct AgentSettingsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    let agent: SubAgentInfo
    let onClose: () -> Void

    @State private var selectedModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Text(agent.emoji)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    Text(agent.id)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Info section
                        VStack(alignment: .leading, spacing: 6) {
                            // Model picker
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Model:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker("", selection: $selectedModel) {
                                    Text("Default (inherit)").tag("")
                                    ForEach(viewModel.availableModelsForSettings) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .controlSize(.small)
                                .frame(maxWidth: 260)
                                .onChange(of: selectedModel) { newValue in
                                    if newValue != agent.model {
                                        viewModel.updateAgentModel(model: newValue)
                                    }
                                }
                            }

                            // Workspace path (clickable → open in Finder)
                            if !agent.workspace.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(agent.workspace.replacingOccurrences(
                                        of: FileManager.default.homeDirectoryForCurrentUser.path,
                                        with: "~"
                                    ))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: agent.workspace))
                                }
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }

                            // Binding details
                            if !agent.bindingDetails.isEmpty {
                                ForEach(agent.bindingDetails, id: \.self) { binding in
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(binding)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        Divider()

                        // Persona editors (collapsed by default)
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

                            // Additional .md files — only shown when present in workspace
                            if viewModel.hasPersonaFile("USER.md") {
                                MarkdownFileEditor(
                                    title: "USER.md",
                                    icon: "person.fill",
                                    content: viewModel.settingsBindingByName("USER.md"),
                                    isDirty: viewModel.isFileDirtyByName("USER.md"),
                                    onSave: { viewModel.savePersonaFileByName("USER.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("AGENTS.md") {
                                MarkdownFileEditor(
                                    title: "AGENTS.md",
                                    icon: "person.3.fill",
                                    content: viewModel.settingsBindingByName("AGENTS.md"),
                                    isDirty: viewModel.isFileDirtyByName("AGENTS.md"),
                                    onSave: { viewModel.savePersonaFileByName("AGENTS.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("BOOTSTRAP.md") {
                                MarkdownFileEditor(
                                    title: "BOOTSTRAP.md",
                                    icon: "power",
                                    content: viewModel.settingsBindingByName("BOOTSTRAP.md"),
                                    isDirty: viewModel.isFileDirtyByName("BOOTSTRAP.md"),
                                    onSave: { viewModel.savePersonaFileByName("BOOTSTRAP.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("HEARTBEAT.md") {
                                MarkdownFileEditor(
                                    title: "HEARTBEAT.md",
                                    icon: "heart.text.clipboard",
                                    content: viewModel.settingsBindingByName("HEARTBEAT.md"),
                                    isDirty: viewModel.isFileDirtyByName("HEARTBEAT.md"),
                                    onSave: { viewModel.savePersonaFileByName("HEARTBEAT.md") },
                                    initiallyExpanded: false
                                )
                            }

                            if viewModel.hasPersonaFile("TOOLS.md") {
                                MarkdownFileEditor(
                                    title: "TOOLS.md",
                                    icon: "wrench.and.screwdriver",
                                    content: viewModel.settingsBindingByName("TOOLS.md"),
                                    isDirty: viewModel.isFileDirtyByName("TOOLS.md"),
                                    onSave: { viewModel.savePersonaFileByName("TOOLS.md") },
                                    initiallyExpanded: false
                                )
                            }
                        }
                        .padding(16)
                    }
                }
        }
        .frame(width: 380)
        // Contrast against the chat area's windowBackgroundColor so the
        // drawer reads as a clearly separate panel — without this, the
        // drawer and chat were the same surface and felt borderless.
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .leading) {
            // Crisp 1px divider on the leading edge so the boundary is
            // unambiguous even when shadow is muted in light mode.
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, x: -2, y: 0)
        .onAppear {
            selectedModel = agent.model
        }
    }
}

// MARK: - Workspace File Panel

private struct OutputsTabView: View {
    let agentId: String
    @State private var refreshId = UUID()

    private var workspacePath: String {
        let base = NSString("~/.openclaw").expandingTildeInPath
        if agentId == "main" {
            return (base as NSString).appendingPathComponent("workspace")
        }
        return (base as NSString).appendingPathComponent("workspace-\(agentId)")
    }

    private var outputItems: [URL] {
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let excludedNames: Set<String> = [
            "IDENTITY.md", "SOUL.md", "MEMORY.md", "USER.md",
            "AGENTS.md", "BOOTSTRAP.md", "HEARTBEAT.md", "TOOLS.md"
        ]

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let name = url.lastPathComponent
            if excludedNames.contains(name) { return nil }
            if name.hasPrefix(".") { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { return nil }
            return url
        }
        .sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outputs")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button {
                    refreshId = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: workspacePath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.plain)
                .help("Open Outputs Folder")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            if outputItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No outputs yet")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(outputItems, id: \.path) { url in
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconName(for: url))
                                .foregroundColor(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .foregroundColor(.primary)
                                Text(relativePath(for: url))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .id(refreshId)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: workspacePath + "/", with: "")
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic": return "photo"
        case "mp4", "mov", "webm": return "film"
        case "md", "txt", "json", "csv", "xml", "yaml", "yml": return "doc.text"
        default: return "doc"
        }
    }
}

private struct WorkspaceFilePanel: View {
    let agentId: String
    @Binding var editingFilePath: String?
    let editingFileDirty: Bool
    let onClose: () -> Void

    @State private var expandedFolders: Set<String> = []
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // Context menu state
    @State private var renamingPath: String?
    @State private var renamingText: String = ""
    @State private var newItemParent: String?
    @State private var newItemIsFolder: Bool = false
    @State private var newItemName: String = ""
    @State private var clipboardPath: String?
    @State private var clipboardIsCut: Bool = false
    @State private var deleteConfirmPath: String?
    @State private var refreshTrigger: Int = 0
    @FocusState private var isRenameFocused: Bool
    @FocusState private var isNewItemFocused: Bool

    private static let hiddenAgentConfigFileNames: Set<String> = [
        "AGENTS.md", "IDENTITY.md", "SOUL.md", "MEMORY.md",
        "USER.md", "BOOTSTRAP.md", "HEARTBEAT.md", "TOOLS.md"
    ]

    private var workspacePath: String {
        DashboardViewModel.resolveAgentWorkspace(agentId)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)
                .shadow(color: .black.opacity(0.15), radius: 6, x: -3, y: 0)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text("Workspace")
                        .font(.headline)
                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isSearching.toggle()
                            if !isSearching {
                                searchText = ""
                                isSearchFocused = false
                            } else {
                                isSearchFocused = true
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundColor(isSearching ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Search Files")

                    Button(action: {
                        NSWorkspace.shared.open(URL(fileURLWithPath: workspacePath))
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                // Search bar
                if isSearching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField("Search files...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isSearchFocused)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
                        if query.isEmpty {
                            let visibleItems = buildVisibleItems(root: workspacePath, depth: 0)
                            ForEach(visibleItems, id: \.item.path) { entry in
                                fileRowView(item: entry.item, depth: entry.depth)
                            }
                            // New item input row at workspace root level
                            if newItemParent == workspacePath {
                                newItemInputRow(depth: 0)
                            }
                        } else {
                            let results = searchFiles(root: workspacePath, query: query)
                            if results.isEmpty {
                                Text("No results")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(12)
                            } else {
                                ForEach(results, id: \.path) { item in
                                    searchResultRow(item: item)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .id(refreshTrigger)
            }
            .frame(width: 280)
            .background(Color(NSColor.windowBackgroundColor))
            .alert("Delete", isPresented: Binding<Bool>(
                get: { deleteConfirmPath != nil },
                set: { if !$0 { deleteConfirmPath = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let path = deleteConfirmPath {
                        performDelete(path: path)
                    }
                    deleteConfirmPath = nil
                }
                Button("Cancel", role: .cancel) {
                    deleteConfirmPath = nil
                }
            } message: {
                if let path = deleteConfirmPath {
                    Text("Are you sure you want to delete \"\((path as NSString).lastPathComponent)\"?")
                }
            }
        }
    }

    // MARK: - Search result row (flat, with relative path)

    private func searchResultRow(item: FileItem) -> some View {
        let isSelected = editingFilePath == item.path
        let isDirtyFile = isSelected && editingFileDirty
        let relativePath = item.path.replacingOccurrences(of: workspacePath + "/", with: "")

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                if item.isDirectory {
                    // Expand all ancestor folders + this folder, then exit search
                    var current = item.path
                    while current != workspacePath && current != "/" {
                        expandedFolders.insert(current)
                        current = (current as NSString).deletingLastPathComponent
                    }
                    searchText = ""
                    isSearching = false
                    isSearchFocused = false
                } else {
                    editingFilePath = item.path
                }
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                    .font(.system(size: 13))
                    .foregroundColor(item.isDirectory ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    if relativePath != item.name {
                        Text(relativePath)
                            .font(.system(size: 10))
                            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if isDirtyFile {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recursive file search

    private func searchFiles(root: String, query: String) -> [FileItem] {
        var results: [FileItem] = []
        searchFilesRecursive(directory: root, query: query, depth: 0, results: &results)
        return results.sorted {
            // Directories first, then by name
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func searchFilesRecursive(directory: String, query: String, depth: Int, results: inout [FileItem]) {
        guard depth < 3 else { return }
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for name in names {
            if isHiddenWorkspaceItem(name: name) { continue }
            let fullPath = (directory as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if name.lowercased().contains(query) {
                results.append(FileItem(name: name, path: fullPath, isDirectory: isDir.boolValue))
            }
            if isDir.boolValue {
                searchFilesRecursive(directory: fullPath, query: query, depth: depth + 1, results: &results)
            }
        }
    }

    private struct DepthItem {
        let item: FileItem
        let depth: Int
    }

    private func buildVisibleItems(root: String, depth: Int) -> [DepthItem] {
        var result: [DepthItem] = []
        let items = listDirectory(root)
        for item in items {
            result.append(DepthItem(item: item, depth: depth))
            if item.isDirectory && expandedFolders.contains(item.path) {
                result.append(contentsOf: buildVisibleItems(root: item.path, depth: depth + 1))
                // New item input row inside this expanded directory
                if newItemParent == item.path {
                    result.append(DepthItem(
                        item: FileItem(name: "__new_item_placeholder__", path: item.path + "/__new_item__", isDirectory: false),
                        depth: depth + 1
                    ))
                }
            }
        }
        return result
    }

    @ViewBuilder
    private func fileRowView(item: FileItem, depth: Int) -> some View {
        // Placeholder for new item input
        if item.name == "__new_item_placeholder__" {
            newItemInputRow(depth: depth)
        } else {
            fileRowContent(item: item, depth: depth)
        }
    }

    @ViewBuilder
    private func fileRowContent(item: FileItem, depth: Int) -> some View {
        let isExpanded = expandedFolders.contains(item.path)
        let isSelected = editingFilePath == item.path
        let isDirtyFile = isSelected && editingFileDirty
        let isRenaming = renamingPath == item.path

        if isRenaming {
            // Rename mode: standalone row (not inside Button, so Enter works on TextField)
            HStack(spacing: 6) {
                if item.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }

                Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                    .font(.system(size: 13))
                    .foregroundColor(item.isDirectory ? .accentColor : .secondary)

                CommitTextField(
                    text: $renamingText,
                    onCommit: { value in performRename(oldPath: item.path, newName: value) },
                    onCancel: { renamingPath = nil; refreshTrigger += 1 }
                )
                .frame(height: 22)

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.15))
            .cornerRadius(4)
        } else {
            // Normal mode: clickable button row
            Button(action: {
                if item.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isExpanded {
                            expandedFolders.remove(item.path)
                        } else {
                            expandedFolders.insert(item.path)
                        }
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        editingFilePath = item.path
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if item.isDirectory {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    } else {
                        Spacer().frame(width: 12)
                    }

                    Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                        .font(.system(size: 13))
                        .foregroundColor(item.isDirectory ? .accentColor : .secondary)

                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isDirtyFile {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }

                    Spacer()
                }
                .padding(.leading, CGFloat(depth) * 16 + 12)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.85) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
            Button {
                let parent = item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent
                beginNewItem(parent: parent, isFolder: false)
            } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }

            Button {
                let parent = item.isDirectory ? item.path : (item.path as NSString).deletingLastPathComponent
                beginNewItem(parent: parent, isFolder: true)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                renamingText = item.name
                renamingPath = item.path
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isRenameFocused = true
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button {
                clipboardPath = item.path
                clipboardIsCut = true
            } label: {
                Label("Cut", systemImage: "scissors")
            }

            Button {
                clipboardPath = item.path
                clipboardIsCut = false
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if item.isDirectory, let clip = clipboardPath, !clip.isEmpty {
                Button {
                    performPaste(into: item.path)
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
            }

            Divider()

            Button(role: .destructive) {
                deleteConfirmPath = item.path
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        }
    }

    // MARK: - New item inline input row

    private func newItemInputRow(depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 12)
            Image(systemName: newItemIsFolder ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
            CommitTextField(
                text: $newItemName,
                placeholder: newItemIsFolder ? "Folder name" : "File name",
                onCommit: { value in performNewItem(name: value) },
                onCancel: { cancelNewItem() }
            )
            .frame(height: 22)
        }
        .padding(.leading, CGFloat(depth) * 16 + 12)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
    }

    // MARK: - File operations

    private func beginNewItem(parent: String, isFolder: Bool) {
        newItemParent = parent
        newItemIsFolder = isFolder
        newItemName = ""
        expandedFolders.insert(parent)
        refreshTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isNewItemFocused = true
        }
    }

    private func cancelNewItem() {
        newItemParent = nil
        newItemName = ""
        refreshTrigger += 1
    }

    private func performNewItem(name inputName: String) {
        guard let parent = newItemParent else { return }
        let name = inputName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { cancelNewItem(); return }
        let fullPath = (parent as NSString).appendingPathComponent(name)
        let fm = FileManager.default
        if newItemIsFolder {
            try? fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
        } else {
            fm.createFile(atPath: fullPath, contents: nil)
        }
        newItemParent = nil
        newItemName = ""
        refreshTrigger += 1
    }

    private func performRename(oldPath: String, newName inputName: String) {
        let newName = inputName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != (oldPath as NSString).lastPathComponent else {
            renamingPath = nil
            refreshTrigger += 1
            return
        }
        let parent = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parent as NSString).appendingPathComponent(newName)
        let fm = FileManager.default
        do {
            try fm.moveItem(atPath: oldPath, toPath: newPath)
            if editingFilePath == oldPath {
                editingFilePath = newPath
            }
        } catch {}
        renamingPath = nil
        refreshTrigger += 1
    }

    private func performDelete(path: String) {
        try? FileManager.default.removeItem(atPath: path)
        if let editing = editingFilePath, editing.hasPrefix(path) {
            editingFilePath = nil
        }
        if let clip = clipboardPath, clip.hasPrefix(path) {
            clipboardPath = nil
        }
        refreshTrigger += 1
    }

    private func performPaste(into directory: String) {
        guard let source = clipboardPath else { return }
        let name = (source as NSString).lastPathComponent
        var dest = (directory as NSString).appendingPathComponent(name)
        let fm = FileManager.default

        // Avoid overwriting: append " copy" if needed
        if !clipboardIsCut && fm.fileExists(atPath: dest) {
            let baseName = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var counter = 1
            repeat {
                let suffix = counter == 1 ? " copy" : " copy \(counter)"
                let newName = ext.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(ext)"
                dest = (directory as NSString).appendingPathComponent(newName)
                counter += 1
            } while fm.fileExists(atPath: dest)
        }

        do {
            if clipboardIsCut {
                try fm.moveItem(atPath: source, toPath: dest)
                if let editing = editingFilePath, editing.hasPrefix(source) {
                    editingFilePath = editing.replacingOccurrences(of: source, with: dest)
                }
                clipboardPath = nil
            } else {
                try fm.copyItem(atPath: source, toPath: dest)
            }
        } catch {}

        expandedFolders.insert(directory)
        refreshTrigger += 1
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "yaml", "yml": return "list.bullet.rectangle"
        case "txt": return "doc.text"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "swift": return "swift"
        case "js", "ts": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    private func listDirectory(_ path: String) -> [FileItem] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var items: [FileItem] = []
        for name in names.sorted() {
            if isHiddenWorkspaceItem(name: name) { continue }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            items.append(FileItem(name: name, path: fullPath, isDirectory: isDir.boolValue))
        }
        // Folders first, then files
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private func isHiddenWorkspaceItem(name: String) -> Bool {
        name.hasPrefix(".") || Self.hiddenAgentConfigFileNames.contains(name)
    }
}

// MARK: - Commit TextField (reliable Enter + focus-loss on macOS)

private class EnterResignsTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        // Tag the field editor so the global key monitor can skip it
        if let editor = currentEditor() as? NSTextView {
            editor.identifier = NSUserInterfaceItemIdentifier("commitTextField")
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        // Enter (keyCode 36) or Return (keyCode 76) → resign focus
        if event.keyCode == 36 || event.keyCode == 76 {
            window?.makeFirstResponder(nil)
            return
        }
        super.keyDown(with: event)
    }
}

private struct CommitTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: (String) -> Void
    var onCancel: (() -> Void)?

    func makeNSView(context: Context) -> EnterResignsTextField {
        let tf = EnterResignsTextField()
        tf.placeholderString = placeholder
        tf.font = NSFont.systemFont(ofSize: 13)
        tf.isBordered = true
        tf.bezelStyle = .roundedBezel
        tf.focusRingType = .exterior
        tf.delegate = context.coordinator
        tf.stringValue = text
        DispatchQueue.main.async {
            tf.window?.makeFirstResponder(tf)
            tf.currentEditor()?.selectAll(nil)
        }
        return tf
    }

    func updateNSView(_ nsView: EnterResignsTextField, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onCommit: (String) -> Void
        var onCancel: (() -> Void)?

        init(text: Binding<String>, onCommit: @escaping (String) -> Void, onCancel: (() -> Void)?) {
            self._text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel?()
                return true
            }
            return false
        }

        // Fires on Enter (resign) and any other focus loss
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            onCommit(tf.stringValue)
        }
    }
}

private struct FileItem {
    let name: String
    let path: String
    let isDirectory: Bool
}

// MARK: - File Editor Panel

private enum FileViewMode {
    case preview    // QLPreviewView (read-only, syntax highlight / media playback)
    case editor     // TextEditor (editable)
}

private enum FileCategory {
    case text       // .txt, .yaml, .yml, .csv, .log — open in editor directly
    case code       // .py, .swift, .js, .ts, .json, .go, .rb, .rs, .sh, .md, etc. — preview first, edit button
    case media      // audio/video — preview only
    case image      // .png, .jpg, .gif, .svg, etc. — preview only
    case other      // everything else — preview

    var supportsEditing: Bool {
        switch self {
        case .text, .code: return true
        case .media, .image, .other: return false
        }
    }

    var defaultMode: FileViewMode {
        return .preview
    }

    static func detect(ext: String) -> FileCategory {
        switch ext.lowercased() {
        case "txt", "yaml", "yml", "csv", "log", "ini", "cfg", "conf", "toml":
            return .text
        case "md", "py", "swift", "js", "ts", "jsx", "tsx", "json", "go", "rb", "rs",
             "sh", "bash", "zsh", "c", "cpp", "h", "hpp", "java", "kt", "lua",
             "r", "sql", "html", "css", "scss", "xml", "dockerfile", "makefile":
            return .code
        case "mp3", "wav", "m4a", "aac", "flac", "ogg", "aiff",
             "mp4", "mov", "avi", "mkv", "m4v", "webm":
            return .media
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "svg", "webp", "ico", "heic":
            return .image
        default:
            return .other
        }
    }

    static func languageName(ext: String) -> String {
        switch ext.lowercased() {
        case "py": return "Python"
        case "swift": return "Swift"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "jsx": return "JSX"
        case "tsx": return "TSX"
        case "json": return "JSON"
        case "go": return "Go"
        case "rb": return "Ruby"
        case "rs": return "Rust"
        case "sh", "bash", "zsh": return "Shell"
        case "c": return "C"
        case "cpp", "hpp": return "C++"
        case "h": return "C/C++ Header"
        case "java": return "Java"
        case "kt": return "Kotlin"
        case "lua": return "Lua"
        case "r": return "R"
        case "sql": return "SQL"
        case "html": return "HTML"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "xml": return "XML"
        case "md": return "Markdown"
        case "txt": return "Plain Text"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "ini", "cfg", "conf": return "Config"
        case "csv": return "CSV"
        case "log": return "Log"
        case "dockerfile": return "Dockerfile"
        case "makefile": return "Makefile"
        default: return ext.uppercased()
        }
    }
}

private struct FileEditorPanel: View {
    let filePath: String
    let onClose: () -> Void
    var onDirtyChanged: ((Bool) -> Void)?

    @State private var content: String = ""
    @State private var originalContent: String = ""
    @State private var isLoading = true
    @State private var saveMessage: String?
    @State private var viewMode: FileViewMode = .editor
    @Binding var isFullscreen: Bool
    @State private var fontSize: CGFloat = 13
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 1
    @State private var wordWrap = true

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var fileExt: String {
        (filePath as NSString).pathExtension
    }

    private var category: FileCategory {
        FileCategory.detect(ext: fileExt)
    }

    private var isDirty: Bool {
        content != originalContent
    }

    private var fileSizeString: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
              let size = attrs[.size] as? UInt64 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        return String(format: "%.1f MB", Double(size) / (1024 * 1024))
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)
                .shadow(color: .black.opacity(0.15), radius: 6, x: -3, y: 0)

            VStack(spacing: 0) {
                // Header
                headerBar
                Divider()

                // Content
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if viewMode == .editor {
                    CodeEditorView(
                        text: $content,
                        fontSize: fontSize,
                        wordWrap: wordWrap,
                        fileExtension: fileExt,
                        cursorLine: $cursorLine,
                        cursorColumn: $cursorColumn
                    )
                } else if category.supportsEditing && !["md", "html", "htm"].contains(fileExt.lowercased()) {
                    // Text/code preview: read-only with syntax highlighting
                    CodeEditorView(
                        text: .constant(content),
                        fontSize: fontSize,
                        wordWrap: wordWrap,
                        fileExtension: fileExt,
                        cursorLine: $cursorLine,
                        cursorColumn: $cursorColumn,
                        isReadOnly: true
                    )
                } else if fileExt.lowercased() == "md" {
                    MarkdownPreviewView(markdown: content)
                } else if ["html", "htm"].contains(fileExt.lowercased()) {
                    HTMLPreviewView(fileURL: URL(fileURLWithPath: filePath))
                } else {
                    QuickLookPreview(url: URL(fileURLWithPath: filePath))
                }

                // Status bar
                if viewMode == .editor {
                    Divider()
                    statusBar
                }
            }
            .frame(maxWidth: isFullscreen ? .infinity : 480)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear { loadFile() }
        .onChange(of: filePath) { _ in loadFile() }
        .onChange(of: isDirty) { dirty in
            onDirtyChanged?(dirty)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundColor(.accentColor)
            Text(fileName)
                .font(.headline)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(filePath, forType: .string)
                    saveMessage = "Path copied"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if saveMessage == "Path copied" { saveMessage = nil }
                    }
                }
                .help("Double-click to copy path")

            if viewMode == .editor && isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            }

            if let msg = saveMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()

            // Font size controls
            if viewMode == .editor {
                Button(action: { if fontSize > 9 { fontSize -= 1 } }) {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Decrease font size (⌘-)")

                Text("\(Int(fontSize))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Button(action: { if fontSize < 28 { fontSize += 1 } }) {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Increase font size (⌘+)")

                // Word wrap toggle
                Button(action: { wordWrap.toggle() }) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 12))
                        .foregroundColor(wordWrap ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(wordWrap ? "Disable word wrap" : "Enable word wrap")

                Divider().frame(height: 16)
            }

            // Toggle preview/edit for code files
            if category.supportsEditing {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewMode = (viewMode == .preview) ? .editor : .preview
                    }
                }) {
                    Image(systemName: viewMode == .preview ? "pencil.line" : "eye")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help(viewMode == .preview ? "Edit" : "Preview")
            }

            // Save via Cmd+S (hidden)
            if viewMode == .editor {
                Button(action: save) { EmptyView() }
                    .keyboardShortcut("s", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()

                // Font size keyboard shortcuts
                Button(action: { if fontSize < 28 { fontSize += 1 } }) { EmptyView() }
                    .keyboardShortcut("+", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()

                Button(action: { if fontSize > 9 { fontSize -= 1 } }) { EmptyView() }
                    .keyboardShortcut("-", modifiers: .command)
                    .frame(width: 0, height: 0)
                    .hidden()
            }

            // Fullscreen toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullscreen.toggle()
                }
            }) {
                Image(systemName: isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(isFullscreen ? "Exit Fullscreen" : "Fullscreen")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("Ln \(cursorLine), Col \(cursorColumn)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            Text("UTF-8")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text(FileCategory.languageName(ext: fileExt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text(fileSizeString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var headerIcon: String {
        switch category {
        case .media: return "play.circle"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }

    private func loadFile() {
        isLoading = true
        saveMessage = nil
        viewMode = category.defaultMode
        cursorLine = 1
        cursorColumn = 1

        if category.supportsEditing {
            if let data = FileManager.default.contents(atPath: filePath),
               let text = String(data: data, encoding: .utf8) {
                let formatted = fileExt.lowercased() == "json" ? prettyJSON(text) : text
                content = formatted
                originalContent = formatted
            } else {
                content = ""
                originalContent = ""
            }
        }
        isLoading = false
    }

    private func save() {
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            originalContent = content
            saveMessage = "Saved"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if saveMessage == "Saved" { saveMessage = nil }
            }
        } catch {
            saveMessage = "Error"
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return result
    }
}

// MARK: - Code Editor View (NSTextView with Line Numbers + Find Bar)

private struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var wordWrap: Bool
    var fileExtension: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int
    var isReadOnly: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.isEditable = !isReadOnly
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.identifier = NSUserInterfaceItemIdentifier("codeEditorTextView")

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textView.drawsBackground = true
        textView.backgroundColor = isDark
            ? NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
            : NSColor.white
        textView.textColor = isDark ? NSColor.white : NSColor.black
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        if wordWrap {
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
        } else {
            scrollView.hasHorizontalScroller = true
            textView.isHorizontallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }

        textView.string = text
        SyntaxHighlighter.highlight(textView: textView, fileExtension: fileExtension, fontSize: fontSize)

        // Observe selection changes for cursor position
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewDidChangeSelection(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )

        // Observe scroll
        if let clipView = scrollView.contentView as? NSClipView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Never interrupt IME composition (e.g. Chinese/Japanese input)
        guard !textView.hasMarkedText() else { return }

        if !context.coordinator.isUpdatingFromDelegate && textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            SyntaxHighlighter.highlight(textView: textView, fileExtension: fileExtension, fontSize: fontSize)
            textView.selectedRanges = selectedRanges
        }

        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        let needsHorizontalScroller = !wordWrap
        if scrollView.hasHorizontalScroller != needsHorizontalScroller {
            scrollView.hasHorizontalScroller = needsHorizontalScroller
            if wordWrap {
                textView.isHorizontallyResizable = false
                textView.textContainer?.widthTracksTextView = true
            } else {
                textView.isHorizontallyResizable = true
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var textView: NSTextView?
        var isUpdatingFromDelegate = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isUpdatingFromDelegate = true
            parent.text = tv.string
            // Defer flag reset so it covers SwiftUI's batched updateNSView call
            DispatchQueue.main.async {
                self.isUpdatingFromDelegate = false
            }
            SyntaxHighlighter.highlight(textView: tv, fileExtension: parent.fileExtension, fontSize: parent.fontSize)
        }

        @objc func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let selectedRange = tv.selectedRange()
            let text = tv.string
            let nsText = text as NSString

            let lineRange = nsText.lineRange(for: NSRange(location: selectedRange.location, length: 0))
            let lineStart = lineRange.location

            var line = 1
            var idx = 0
            while idx < selectedRange.location && idx < nsText.length {
                if nsText.character(at: idx) == 0x0A { line += 1 }
                idx += 1
            }

            let col = selectedRange.location - lineStart + 1

            DispatchQueue.main.async {
                self.parent.cursorLine = line
                self.parent.cursorColumn = col
            }
        }

        @objc func boundsDidChange(_ notification: Notification) {
        }
    }
}

// MARK: - Line Number Gutter (replaces NSRulerView to avoid tile() corruption)

private class LineNumberGutterView: NSView {
    weak var textView: NSTextView?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        // Separator line on the right edge
        NSColor.separatorColor.setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.minY))
        sep.line(to: NSPoint(x: bounds.maxX - 0.5, y: dirtyRect.maxY))
        sep.lineWidth = 0.5
        sep.stroke()

        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let font = NSFont.monospacedSystemFont(ofSize: (textView.font?.pointSize ?? 13) - 2, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return }

        // Find line number for the first visible character
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location && idx < nsString.length {
            if nsString.character(at: idx) == 0x0A { lineNumber += 1 }
            idx += 1
        }

        // Draw line numbers for visible lines
        var charIndex = charRange.location
        while charIndex < NSMaxRange(charRange) && charIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))

            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerInset.height

            let yPos = lineRect.origin.y - visibleRect.origin.y
            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: bounds.width - strSize.width - 8,
                y: yPos + (lineRect.height - strSize.height) / 2
            )
            lineStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
            if charIndex == lineRange.location { charIndex += 1 } // prevent infinite loop
        }
    }
}

// MARK: - Syntax Highlighter

private struct SyntaxHighlighter {

    struct Rule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options

        init(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.color = color
            self.options = options
        }
    }

    static func highlight(textView: NSTextView, fileExtension: String, fontSize: CGFloat) {
        guard let layoutManager = textView.layoutManager else { return }
        let source = textView.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard fullRange.length > 0 else { return }

        // Clear previous temporary highlighting
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)

        // Apply rules via temporary attributes (display-only, does not modify textStorage)
        let rules = Self.rules(for: fileExtension)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            regex.enumerateMatches(in: source, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range, matchRange.location != NSNotFound else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: rule.color, forCharacterRange: matchRange)
            }
        }
    }

    // MARK: - Language Rules

    private static func rules(for ext: String) -> [Rule] {
        switch ext.lowercased() {
        case "py":          return pythonRules
        case "swift":       return swiftRules
        case "js", "jsx":   return jsRules
        case "ts", "tsx":   return tsRules
        case "json":        return jsonRules
        case "go":          return goRules
        case "rb":          return rubyRules
        case "rs":          return rustRules
        case "sh", "bash", "zsh": return shellRules
        case "c", "cpp", "h", "hpp": return cRules
        case "java", "kt":  return javaRules
        case "html", "xml": return htmlRules
        case "css", "scss": return cssRules
        case "sql":         return sqlRules
        case "yaml", "yml": return yamlRules
        case "toml", "ini", "cfg", "conf": return configRules
        case "md":          return markdownRules
        case "lua":         return luaRules
        case "dockerfile":  return dockerRules
        case "makefile":    return makefileRules
        default:            return genericRules
        }
    }

    // Colors
    private static let kKeyword   = NSColor.systemPink
    private static let kString    = NSColor.systemGreen
    private static let kComment   = NSColor.systemGray
    private static let kNumber    = NSColor.systemOrange
    private static let kType      = NSColor.systemTeal
    private static let kFunction  = NSColor.systemBlue
    private static let kConstant  = NSColor.systemPurple
    private static let kTag       = NSColor.systemRed
    private static let kAttr      = NSColor.systemOrange
    private static let kHeading   = NSColor.systemBlue

    // Shared patterns
    private static let pDoubleStr = "\"(?:[^\"\\\\]|\\\\.)*\""
    private static let pSingleStr = "'(?:[^'\\\\]|\\\\.)*'"
    private static let pNumber    = "\\b(?:0[xXoObB])?[0-9][0-9_]*\\.?[0-9_]*(?:[eE][+-]?[0-9]+)?\\b"
    private static let pLineComment = "//.*"
    private static let pHashComment = "#.*"
    private static let pBlockComment = "/\\*[\\s\\S]*?\\*/"

    // MARK: Python
    private static var pythonRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule("\"\"\"[\\s\\S]*?\"\"\"", kString, options: []),
        Rule("'''[\\s\\S]*?'''", kString, options: []),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:def|class|if|elif|else|for|while|return|import|from|as|try|except|finally|with|raise|yield|lambda|pass|break|continue|and|or|not|in|is|async|await|global|nonlocal|del|assert)\\b", kKeyword),
        Rule("\\b(?:True|False|None|self|cls)\\b", kConstant),
        Rule("\\b(?:int|float|str|bool|list|dict|tuple|set|bytes|object|type|Exception)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Swift
    private static var swiftRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:func|var|let|if|else|guard|switch|case|default|for|while|repeat|return|import|class|struct|enum|protocol|extension|init|deinit|self|super|throw|throws|try|catch|do|break|continue|where|in|as|is|typealias|associatedtype|async|await|actor|some|any|macro)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|Self)\\b", kConstant),
        Rule("\\b(?:String|Int|Double|Float|Bool|Array|Dictionary|Optional|Set|Result|Void|Any|AnyObject|Error|Codable|Hashable|Equatable|Identifiable|View|State|Binding|Published|ObservableObject|EnvironmentObject)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("#\\w+", kKeyword),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: JavaScript
    private static var jsRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`(?:[^`\\\\]|\\\\.)*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:function|var|let|const|if|else|for|while|do|switch|case|default|return|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|void)\\b", kKeyword),
        Rule("\\b(?:true|false|null|undefined|NaN|Infinity)\\b", kConstant),
        Rule("\\b(?:Array|Object|String|Number|Boolean|Function|Promise|Map|Set|RegExp|Error|Date|Math|JSON|console)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: TypeScript
    private static var tsRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`(?:[^`\\\\]|\\\\.)*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:function|var|let|const|if|else|for|while|do|switch|case|default|return|break|continue|throw|try|catch|finally|new|delete|typeof|instanceof|in|of|class|extends|super|import|export|from|as|default|async|await|yield|this|void|type|interface|enum|namespace|declare|abstract|implements|readonly|keyof|infer)\\b", kKeyword),
        Rule("\\b(?:true|false|null|undefined|NaN|Infinity)\\b", kConstant),
        Rule("\\b(?:string|number|boolean|any|unknown|never|void|object|symbol|bigint|Array|Object|Promise|Map|Set|Record|Partial|Required|Omit|Pick)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: JSON
    private static var jsonRules: [Rule] { [
        Rule(pDoubleStr + "(?=\\s*:)", kFunction),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:true|false|null)\\b", kConstant),
    ] }

    // MARK: Go
    private static var goRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule("`[^`]*`", kString),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:func|var|const|if|else|for|range|switch|case|default|return|break|continue|go|defer|select|chan|map|struct|interface|type|package|import|fallthrough|goto)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|iota)\\b", kConstant),
        Rule("\\b(?:int|int8|int16|int32|int64|uint|uint8|uint16|uint32|uint64|float32|float64|complex64|complex128|string|bool|byte|rune|error|any)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Ruby
    private static var rubyRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:def|class|module|if|elsif|else|unless|while|until|for|do|end|return|break|next|yield|begin|rescue|ensure|raise|require|include|extend|attr_accessor|attr_reader|attr_writer|puts|print|lambda|proc)\\b", kKeyword),
        Rule("\\b(?:true|false|nil|self)\\b", kConstant),
        Rule(":[a-zA-Z_]\\w*", kConstant),
        Rule("@{1,2}\\w+", kType),
        Rule("\\b\\w+(?=[?!]?\\()", kFunction),
    ] }

    // MARK: Rust
    private static var rustRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:fn|let|mut|if|else|match|for|while|loop|return|break|continue|struct|enum|impl|trait|type|use|mod|pub|crate|self|super|where|async|await|move|unsafe|extern|const|static|ref|as|in|dyn|macro_rules)\\b", kKeyword),
        Rule("\\b(?:true|false|None|Some|Ok|Err|Self)\\b", kConstant),
        Rule("\\b(?:i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc|HashMap|HashSet)\\b", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
        Rule("#\\[.*?\\]", kFunction),
    ] }

    // MARK: Shell
    private static var shellRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|exit|local|export|source|alias|unalias|set|unset|readonly|shift|eval|exec|trap)\\b", kKeyword),
        Rule("\\$\\{?[a-zA-Z_]\\w*\\}?", kType),
        Rule("\\$[0-9#?@*!$-]", kType),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: C / C++
    private static var cRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("#\\s*(?:include|define|ifdef|ifndef|endif|pragma|if|else|elif|undef|error|warning)\\b.*", kFunction),
        Rule("\\b(?:if|else|for|while|do|switch|case|default|return|break|continue|struct|union|enum|typedef|sizeof|static|extern|inline|const|volatile|register|auto|void|goto|class|public|private|protected|virtual|override|template|typename|namespace|using|new|delete|try|catch|throw|noexcept|constexpr|nullptr|this|operator)\\b", kKeyword),
        Rule("\\b(?:int|char|short|long|float|double|unsigned|signed|bool|size_t|string|vector|map|set|auto|wchar_t|int8_t|int16_t|int32_t|int64_t|uint8_t|uint16_t|uint32_t|uint64_t)\\b", kType),
        Rule("\\b(?:true|false|NULL|nullptr|TRUE|FALSE)\\b", kConstant),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Java / Kotlin
    private static var javaRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:if|else|for|while|do|switch|case|default|return|break|continue|class|interface|extends|implements|new|this|super|import|package|public|private|protected|static|final|abstract|synchronized|volatile|transient|native|try|catch|finally|throw|throws|void|enum|instanceof|assert|when|fun|val|var|data|object|companion|override|open|sealed|suspend|inline|reified|lateinit|by|constructor|init)\\b", kKeyword),
        Rule("\\b(?:true|false|null|it)\\b", kConstant),
        Rule("\\b(?:int|long|short|byte|float|double|char|boolean|String|Integer|Long|Float|Double|Boolean|Object|List|Map|Set|Array|ArrayList|HashMap|void|Void|Any|Unit|Nothing|Int)\\b", kType),
        Rule("@\\w+", kFunction),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: HTML / XML
    private static var htmlRules: [Rule] { [
        Rule("<!--[\\s\\S]*?-->", kComment, options: [.dotMatchesLineSeparators]),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("</?\\w+", kTag),
        Rule("/?>", kTag),
        Rule("\\b[a-zA-Z-]+(?=\\s*=)", kAttr),
    ] }

    // MARK: CSS / SCSS
    private static var cssRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("[.#][a-zA-Z_][\\w-]*", kTag),
        Rule("@[a-zA-Z][\\w-]*", kKeyword),
        Rule("\\b[a-zA-Z-]+(?=\\s*:)", kFunction),
        Rule("#[0-9a-fA-F]{3,8}\\b", kConstant),
        Rule("\\$[a-zA-Z_][\\w-]*", kType),
    ] }

    // MARK: SQL
    private static var sqlRules: [Rule] { [
        Rule("--.*", kComment),
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pSingleStr, kString),
        Rule(pDoubleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|ALTER|ADD|INDEX|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|NOT|IN|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|DISTINCT|EXISTS|BETWEEN|LIKE|CASE|WHEN|THEN|ELSE|END|BEGIN|COMMIT|ROLLBACK|PRIMARY|KEY|FOREIGN|REFERENCES|UNIQUE|DEFAULT|CHECK|CONSTRAINT|VIEW|TRIGGER|FUNCTION|PROCEDURE|GRANT|REVOKE|WITH|RECURSIVE)\\b", kKeyword, options: [.caseInsensitive]),
        Rule("\\b(?:INT|INTEGER|VARCHAR|TEXT|BOOLEAN|BOOL|DATE|TIMESTAMP|FLOAT|DOUBLE|DECIMAL|NUMERIC|CHAR|BLOB|SERIAL|BIGINT|SMALLINT|REAL)\\b", kType, options: [.caseInsensitive]),
        Rule("\\b(?:COUNT|SUM|AVG|MIN|MAX|COALESCE|IFNULL|NULLIF|CAST|CONVERT|CONCAT|LENGTH|SUBSTR|TRIM|UPPER|LOWER|NOW|CURRENT_TIMESTAMP)\\b", kFunction, options: [.caseInsensitive]),
    ] }

    // MARK: YAML
    private static var yamlRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("^\\s*[\\w.-]+(?=\\s*:)", kFunction, options: [.anchorsMatchLines]),
        Rule("\\b(?:true|false|yes|no|null|~)\\b", kConstant, options: [.caseInsensitive]),
    ] }

    // MARK: Config (TOML / INI)
    private static var configRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(";.*", kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("^\\s*\\[.*?\\]", kTag, options: [.anchorsMatchLines]),
        Rule("^\\s*[\\w.-]+(?=\\s*=)", kFunction, options: [.anchorsMatchLines]),
        Rule("\\b(?:true|false)\\b", kConstant, options: [.caseInsensitive]),
    ] }

    // MARK: Markdown
    private static var markdownRules: [Rule] { [
        Rule("^#{1,6}\\s+.*$", kHeading, options: [.anchorsMatchLines]),
        Rule("\\*\\*(?:[^*]|\\*(?!\\*))+\\*\\*", kKeyword),
        Rule("\\*(?:[^*])+\\*", kConstant),
        Rule("`[^`\n]+`", kString),
        Rule("```[\\s\\S]*?```", kString, options: [.dotMatchesLineSeparators]),
        Rule("^\\s*[-*+]\\s", kTag, options: [.anchorsMatchLines]),
        Rule("^\\s*\\d+\\.\\s", kTag, options: [.anchorsMatchLines]),
        Rule("\\[([^\\]]*)\\]\\([^)]*\\)", kFunction),
    ] }

    // MARK: Lua
    private static var luaRules: [Rule] { [
        Rule("--\\[\\[[\\s\\S]*?\\]\\]", kComment, options: [.dotMatchesLineSeparators]),
        Rule("--.*", kComment),
        Rule("\\[\\[[\\s\\S]*?\\]\\]", kString, options: [.dotMatchesLineSeparators]),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
        Rule("\\b(?:and|break|do|else|elseif|end|for|function|if|in|local|not|or|repeat|return|then|until|while|goto)\\b", kKeyword),
        Rule("\\b(?:true|false|nil)\\b", kConstant),
        Rule("\\b\\w+(?=\\()", kFunction),
    ] }

    // MARK: Dockerfile
    private static var dockerRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("^\\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS)\\b", kKeyword, options: [.anchorsMatchLines, .caseInsensitive]),
        Rule("\\$\\{?[a-zA-Z_]\\w*\\}?", kType),
    ] }

    // MARK: Makefile
    private static var makefileRules: [Rule] { [
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule("^[a-zA-Z_][\\w.-]*(?=\\s*:)", kTag, options: [.anchorsMatchLines]),
        Rule("\\$[({][^)}]+[)}]", kType),
        Rule("\\b(?:ifeq|ifneq|ifdef|ifndef|else|endif|include|define|endef|override|export|unexport|vpath|PHONY)\\b", kKeyword),
    ] }

    // MARK: Generic fallback
    private static var genericRules: [Rule] { [
        Rule(pBlockComment, kComment, options: [.dotMatchesLineSeparators]),
        Rule(pLineComment, kComment),
        Rule(pHashComment, kComment),
        Rule(pDoubleStr, kString),
        Rule(pSingleStr, kString),
        Rule(pNumber, kNumber),
    ] }
}

// MARK: - Line Number Ruler View

private class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Background
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        // Separator line
        NSColor.separatorColor.setStroke()
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: rect.minY))
        separatorPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: rect.maxY))
        separatorPath.lineWidth = 0.5
        separatorPath.stroke()

        let font = NSFont.monospacedSystemFont(ofSize: (textView.font?.pointSize ?? 13) - 2, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let nsString = textView.string as NSString
        let visibleRect = scrollView!.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Find the line number for the first visible character
        var lineNumber = 1
        var idx = 0
        while idx < charRange.location && idx < nsString.length {
            if nsString.character(at: idx) == 0x0A {
                lineNumber += 1
            }
            idx += 1
        }

        // Draw line numbers for visible lines
        var charIndex = charRange.location
        while charIndex < NSMaxRange(charRange) {
            let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))

            let glyphIdx = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += textView.textContainerInset.height

            // Convert to ruler coordinates
            let yPos = lineRect.origin.y - visibleRect.origin.y

            let lineStr = "\(lineNumber)" as NSString
            let strSize = lineStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - 8,
                y: yPos + (lineRect.height - strSize.height) / 2
            )
            lineStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            charIndex = NSMaxRange(lineRange)
        }
    }
}

// MARK: - QuickLook Preview (NSViewRepresentable)

// MARK: - Markdown Preview (WKWebView)

private struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadMarkdown(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadMarkdown(webView)
    }

    private func loadMarkdown(_ webView: WKWebView) {
        let escaped = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark ? "#1e1e1e" : "#ffffff"
        let textColor = isDark ? "#d4d4d4" : "#1e1e1e"
        let codeBg = isDark ? "#2d2d2d" : "#f5f5f5"
        let borderColor = isDark ? "#444" : "#ddd"
        let linkColor = isDark ? "#569cd6" : "#0366d6"
        let headingColor = isDark ? "#e0e0e0" : "#111111"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 14px;
                line-height: 1.6;
                color: \(textColor);
                background: \(bgColor);
                padding: 16px 20px;
                margin: 0;
                word-wrap: break-word;
            }
            h1, h2, h3, h4, h5, h6 { color: \(headingColor); margin-top: 1.2em; margin-bottom: 0.4em; }
            h1 { font-size: 1.8em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.3em; }
            h2 { font-size: 1.4em; border-bottom: 1px solid \(borderColor); padding-bottom: 0.2em; }
            h3 { font-size: 1.2em; }
            a { color: \(linkColor); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code {
                background: \(codeBg);
                padding: 2px 6px;
                border-radius: 3px;
                font-family: "SF Mono", Menlo, monospace;
                font-size: 0.9em;
            }
            pre {
                background: \(codeBg);
                padding: 12px;
                border-radius: 6px;
                overflow-x: auto;
            }
            pre code { background: none; padding: 0; }
            blockquote {
                border-left: 4px solid \(borderColor);
                margin: 0.5em 0;
                padding: 0.2em 1em;
                color: \(isDark ? "#999" : "#666");
            }
            table { border-collapse: collapse; width: 100%; margin: 0.8em 0; }
            th, td { border: 1px solid \(borderColor); padding: 6px 12px; text-align: left; }
            th { background: \(codeBg); font-weight: 600; }
            img { max-width: 100%; }
            hr { border: none; border-top: 1px solid \(borderColor); margin: 1.5em 0; }
            ul, ol { padding-left: 1.5em; }
            li { margin: 0.2em 0; }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
            document.getElementById('content').innerHTML = marked.parse(`\(escaped)`);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - HTML Preview (WKWebView)

private struct HTMLPreviewView: NSViewRepresentable {
    let fileURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}

// MARK: - Terminal Panel

private struct TerminalPanelView: View {
    let workspacePath: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Terminal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            SwiftTermView(workspacePath: workspacePath)
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

private struct SwiftTermView: NSViewRepresentable {
    let workspacePath: String

    func makeNSView(context: Context) -> SwiftTerm.LocalProcessTerminalView {
        let tv = SwiftTerm.LocalProcessTerminalView(frame: .zero)
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let cwd: String
        if !workspacePath.isEmpty, FileManager.default.fileExists(atPath: workspacePath) {
            cwd = workspacePath
        } else {
            cwd = FileManager.default.homeDirectoryForCurrentUser.path
        }
        tv.startProcess(executable: shell, args: [], environment: nil, execName: nil, currentDirectory: cwd)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return tv
    }

    func updateNSView(_ nsView: SwiftTerm.LocalProcessTerminalView, context: Context) {}
}

private struct TerminalDragHandle: View {
    @Binding var height: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil { dragStart = height }
                        let newHeight = (dragStart ?? height) - value.translation.height
                        height = min(max(newHeight, 80), 500)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}

// MARK: - Session Details Panel (right column on chat tab)

/// Right-side panel matching the redesign: surfaces metadata about the
/// currently active chat session (agent, model, tool status, session info)
/// plus a destructive "Clear Conversation" action. Two-tab top picker:
/// 会话详情 / 执行记录.
struct SessionDetailsPanel: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var tab: PanelTab = .details

    /// Collapsed by default per redesign — the full 300pt panel takes
    /// a lot of width and most of the time users only need to glance at
    /// the agent / counts. Stored in UserDefaults so the user's
    /// preference persists across launches.
    @AppStorage("dashboard.sessionPanelExpanded") private var expanded: Bool = false

    enum PanelTab: String, CaseIterable {
        case details
        case logs
    }

    var body: some View {
        Group {
            if expanded {
                expandedBody
            } else {
                collapsedBody
            }
        }
        // Pre-load the model list, overview, and skills once when the panel
        // first appears. Applied here (outer group) instead of only on the
        // expanded variant so the collapsed view's tool count badge also
        // populates without waiting for the user to expand. Each viewModel
        // function guards against double-load itself.
        .task {
            if viewModel.availableModelsForSettings.isEmpty {
                await viewModel.loadModelsForSettings()
            }
            if viewModel.modelOverview.defaultModel.isEmpty
                || viewModel.modelOverview.defaultModel == "-" {
                await viewModel.loadModels()
            }
            if viewModel.skills.isEmpty {
                await viewModel.loadSkills()
            }
        }
    }

    // MARK: - Collapsed (default)

    /// Slim vertical strip — mirrors the same content as the expanded
    /// panel but stripped to icons + counts. Toggle handle lives on the
    /// leading edge (vertically centered) — see `edgeChevronHandle`.
    private var collapsedBody: some View {
        VStack(spacing: 14) {
            // Tab labels (clickable — switch tab AND expand). Padded to match
            // the gap left by the old top-chevron so the panel head doesn't
            // butt up against the window's top edge.
            VStack(spacing: 8) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                        expanded = true
                    } label: {
                        Text(t == .details ? "详情" : "记录")
                            .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                            .foregroundColor(tab == t ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)

            Divider().padding(.horizontal, 12)

            // Agent avatar + name (no picker in collapsed view to save space;
            // user can expand to switch).
            VStack(spacing: 4) {
                if let agent = viewModel.availableAgents.first(where: { $0.id == viewModel.selectedAgentId }) {
                    Text(agent.emoji)
                        .font(.system(size: 24))
                    Text(agent.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Stats — same data as expanded view, vertical compact form.
            // Each block: label (tiny secondary) + value (small primary).
            // Uptime uses a compact formatter — full HH:MM:SS doesn't
            // fit in 52pt width and gets truncated to "00:00:" mid-string.
            VStack(spacing: 10) {
                statBlock(label: "工具",
                          value: viewModel.skillsSummary.total > 0
                                 ? "\(viewModel.skillsSummary.ready)/\(viewModel.skillsSummary.total)"
                                 : "—")
                statBlock(label: "消息",
                          value: "\(viewModel.chatMessages.count)")
                statBlock(label: "时长",
                          value: Self.formatUptimeCompact(viewModel.openclawService.uptime))
            }

            Spacer()

            // Clear conversation — bottom, destructive red icon-only.
            Button {
                viewModel.chatMessagesByAgent[viewModel.selectedAgentId] = []
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Clear Conversation")
            .padding(.bottom, 16)
        }
        .frame(width: 52)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .overlay(alignment: .leading) { edgeChevronHandle }
    }

    /// Vertical edge handle used by both collapsed and expanded bodies.
    /// Lives on the panel's leading edge, vertically centered. Replaces
    /// the previous top-aligned chevron — feels more like a draggable
    /// panel tab (Notion/Linear convention) and frees the top of the
    /// panel for content. The button is offset half outward so it
    /// visually straddles the divider, giving a "handle sticking out"
    /// affordance.
    private var edgeChevronHandle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                expanded.toggle()
            }
        } label: {
            Image(systemName: expanded ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 14, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(expanded ? "Collapse session details" : "Expand session details")
        .offset(x: -7)  // half-out / half-in; the button visually sits on the divider
    }

    /// Short uptime label for the collapsed column. Falls back to a few
    /// distinct formats sized to fit ≤ 5 chars:
    ///   - < 1 min: `<1m`
    ///   - < 1 hr:  `Xm` (e.g. 7m, 42m)
    ///   - < 1 day: `Xh` (e.g. 2h, 23h)
    ///   - 1+ day:  `Xd`
    /// Long-form HH:MM:SS lives on the expanded view's "Uptime" row.
    static func formatUptimeCompact(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let s = Int(seconds)
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }

    /// Small label/value block used in the collapsed stats column.
    private func statBlock(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Expanded (existing layout)

    private var expandedBody: some View {
        VStack(spacing: 0) {
            // Top tab strip — the collapse chevron used to sit before the
            // first tab; it now lives on the panel's leading edge (see
            // `edgeChevronHandle`), so tabs span the full strip cleanly.
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 4) {
                            Text(t == .details ? "Session Details" : "Activity")
                                .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                                .foregroundColor(tab == t ? .accentColor : .secondary)
                            Rectangle()
                                .fill(tab == t ? Color.accentColor : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)

            Divider()

            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .details:
                        detailsContent
                    case .logs:
                        activityContent
                    }
                }
                .padding(16)
            }

            Divider()

            // Clear conversation — destructive red button matching the
            // latest design mockup. Wipes the in-memory thread for the
            // active agent (persistence layer continues writing on next
            // turn). Quick action; long-press / right-click on a session
            // in the sidebar still surfaces Export / Rename.
            Button {
                viewModel.chatMessagesByAgent[viewModel.selectedAgentId] = []
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Clear Conversation")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.55), lineWidth: 1)
                )
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
        .overlay(alignment: .leading) { edgeChevronHandle }
    }

    // MARK: - Details tab

    @ViewBuilder
    private var detailsContent: some View {
        // Current agent card
        sectionTitle("Current Agent")
        agentCard

        // Model
        sectionTitle("Model")
        modelRow

        // Tool status (mock — wire to real state once backend data is available).
        // Header + count are rendered together inside toolStatusList so the
        // count sits on the same line as the section name, per the design.
        toolStatusList

        // Session info
        sectionTitle("Session Info")
        sessionInfoList
    }

    @ViewBuilder
    private var activityContent: some View {
        if recentActivity.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("No activity yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            ForEach(recentActivity, id: \.id) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11))
                        .foregroundColor(item.color)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if let emoji = item.emoji {
                                Text(emoji)
                                    .font(.system(size: 12))
                            }
                            Text(item.isUser ? "User" : "Assistant")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Sub-blocks

    private var agentCard: some View {
        // Flat layout — avatar + name + pencil on the left, agent Picker
        // pushed to the right edge. Two distinct entries:
        //   - **Picker** (right side): SWITCH to a different agent.
        //     Writes `viewModel.selectedAgentId`; SwiftUI auto-propagates
        //     the change to the top header read-out and the left-sidebar
        //     agent list.
        //   - **Pencil** (next to name): EDIT the current agent's
        //     identity / soul / model (opens AgentSettingsPanel as a
        //     trailing overlay).
        let agent = viewModel.availableAgents.first { $0.id == viewModel.selectedAgentId }
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(agent?.emoji ?? "🤖")
                    .font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent?.name ?? viewModel.selectedAgentId)
                        .font(.system(size: 14, weight: .semibold))
                    Button {
                        viewModel.loadSelectedAgentDetail()
                        Task { await viewModel.loadModelsForSettings() }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.agentSettingsOpen = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit agent")
                }
                if let desc = agent?.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else {
                    Text("General-purpose assistant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Agent switch picker — right-aligned, distinct visual unit.
            // Uses a Menu so the trigger renders the current agent's
            // name with a chevron, matching the mock-up's bordered
            // popup-button look.
            Menu {
                ForEach(viewModel.availableAgents) { a in
                    Button {
                        if viewModel.selectedAgentId != a.id {
                            viewModel.selectedAgentId = a.id
                        }
                    } label: {
                        if a.id == viewModel.selectedAgentId {
                            Label("\(a.emoji) \(a.name)", systemImage: "checkmark")
                        } else {
                            Text("\(a.emoji) \(a.name)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(agent?.name ?? viewModel.selectedAgentId)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// Resolves the model that should display for the *current* agent.
    /// Falls back to the global default when an agent has no per-agent model
    /// override — that mirrors the runtime behavior of openclaw.
    /// The **raw** per-agent model override. Empty string means "inherit
    /// the global default" — same semantics as `AgentSettingsPanel`'s
    /// model picker. Was previously returning the RESOLVED model (the
    /// global default substituted in when the agent had no override),
    /// which caused two bugs:
    ///   1. Inconsistency: the sidebar showed e.g. "deepseek-v4-pro"
    ///      while the agent settings panel showed "Default (inherit)"
    ///      for the same agent.
    ///   2. Picker `set:` saw `newValue == currentAgentModel` whenever
    ///      the user picked the same model that was being inherited,
    ///      so the binding was silently a no-op — "无法切换".
    private var currentAgentModel: String {
        viewModel.availableAgents
            .first { $0.id == viewModel.selectedAgentId }?
            .model ?? ""
    }

    /// Display label for the resolved default (shown in parentheses after
    /// "Default (inherit)" so the user can see WHAT they're inheriting).
    private var resolvedDefaultModel: String {
        let defaultModel = viewModel.modelOverview.defaultModel
        return defaultModel.isEmpty || defaultModel == "-"
            ? ""
            : Self.stripProviderPrefix(defaultModel)
    }

    private var modelRow: some View {
        ModelPickerRow(viewModel: viewModel,
                       currentRawModel: currentAgentModel,
                       resolvedDefaultModel: resolvedDefaultModel)
    }

    /// Skills panel — sourced from real `openclaw skills list` data via
    /// viewModel.skills. Top 5 skills shown (sorted by status: ready first),
    /// with a "view all" link below if the user has more than 5 — clicking
    /// jumps to the Skills tab where the full list lives.
    ///
    /// Originally labeled "Tool Status" (→ "工具状态" in zh-Hans), which
    /// was a UI/data-source mismatch: every other surface — the left-nav
    /// label, the Skills tab header, the help FAQ ("技能状态含义？"),
    /// and the openclaw CLI itself (`openclaw skills list`) — calls
    /// these "skills". Renamed to keep terminology consistent across
    /// the app.
    private var toolStatusList: some View {
        let skills = viewModel.skills
        let summary = viewModel.skillsSummary
        let visible = Array(skills.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            // Combined section header + count, matching the mockup's
            // single-line "Skills     X / Y enabled" presentation.
            HStack {
                Text("Skills")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if summary.total > 0 {
                    Text("\(summary.ready) / \(summary.total) enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Loading…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)

            if visible.isEmpty {
                Text("No skills detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(visible) { skill in
                    // Each row is a Button that jumps to the Skills tab
                    // — chevron and full row are clickable. Hover gives
                    // the standard pointer feedback so it's obviously
                    // interactive (was a static decoration before).
                    Button {
                        viewModel.selectedTab = .skills
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(skill.status == .ready ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            Text(skill.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .contentShape(Rectangle())  // make the entire row hit-testable
                    }
                    .buttonStyle(.plain)
                    .help(skill.description.isEmpty ? skill.name : skill.description)
                }
            }

            if skills.count > visible.count {
                Button {
                    viewModel.selectedTab = .skills
                } label: {
                    HStack {
                        Text("View all (\(skills.count))")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sessionInfoList: some View {
        let activeId = viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId]
        let meta = activeId.flatMap { sid in
            viewModel.sessionsByAgent[viewModel.selectedAgentId]?.first { $0.id == sid }
        }
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f
        }()
        return VStack(alignment: .leading, spacing: 6) {
            infoRow("Created",
                    value: meta.map { formatter.string(from: $0.createdAt) } ?? "—")
            infoRow("Messages",
                    value: "\(viewModel.chatMessages.count)")
            infoRow("Session ID",
                    value: activeId.map { Self.shortId($0) } ?? "—")
            infoRow("Uptime",
                    value: Self.formatUptime(viewModel.openclawService.uptime))
        }
    }

    private func infoRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.top, 4)
    }

    /// Activity feed sourced from chat messages — surfaces user/assistant
    /// turns with cancelled / timed-out states highlighted. A full activity
    /// log would pull from openclawService logs but for now this is enough
    /// to give the panel content while .activity tab is selected.
    private struct ActivityItem {
        let id: UUID
        let icon: String
        let color: SwiftUI.Color
        // Split into role + emoji so the role gets localized; concatenated
        // strings (e.g. "🤖 Assistant") would be treated as plain Strings
        // by Text and skip the xcstrings lookup.
        let isUser: Bool
        let emoji: String?
        let subtitle: String
    }

    private var recentActivity: [ActivityItem] {
        viewModel.chatMessages.suffix(20).reversed().map { msg in
            let icon: String
            let color: SwiftUI.Color
            switch msg.taskStatus {
            case .completed:
                icon = "checkmark.circle.fill"
                color = .green
            case .cancelled:
                icon = "xmark.circle.fill"
                color = .red
            case .timedOut:
                icon = "clock.fill"
                color = .orange
            case .background:
                icon = "tray.fill"
                color = .blue
            case .loading:
                icon = "ellipsis.circle"
                color = .secondary
            }
            let preview = msg.content.prefix(80).replacingOccurrences(of: "\n", with: " ")
            return ActivityItem(
                id: msg.id,
                icon: icon,
                color: color,
                isUser: msg.role == .user,
                emoji: msg.role == .user ? nil : msg.agentEmoji,
                subtitle: String(preview)
            )
        }
    }

    // MARK: - Helpers

    /// Strip a provider prefix like "getclawhub/" so the model name reads
    /// cleanly in tight UI ("deepseek-v4-pro" rather than the full path).
    static func stripProviderPrefix(_ s: String) -> String {
        if let slash = s.lastIndex(of: "/") {
            return String(s[s.index(after: slash)...])
        }
        return s
    }

    private static func shortId(_ id: UUID) -> String {
        let s = id.uuidString.lowercased()
        return s.prefix(8) + "…" + s.suffix(4)
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "00:00:00" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Input Mode Picker (above the chat input area)

/// Three-mode segmented picker matching the redesign: 聊天 / 执行任务 /
/// 代码模式.
///
/// **Currently hidden** (v1.1.46+). The three modes were never wired into
/// `sendMessage()` — they only changed the picker highlight. Shipping a UI
/// control that pretends to switch behavior but doesn't was misleading, so
/// the picker is removed from the input toolbar. The enum + view stay in
/// the codebase as a placeholder for the eventual wiring: each mode should
/// inject a prompt prefix and/or change the agent invocation flags before
/// `sendMessage()` runs.
enum ChatInputMode: String, CaseIterable {
    case chat
    case task
    case code

    var localizedLabel: LocalizedStringKey {
        switch self {
        case .chat: return "Chat"
        case .task: return "Run Task"
        case .code: return "Code Mode"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .task: return "terminal.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ChatInputModePicker: View {
    @Binding var mode: ChatInputMode

    var body: some View {
        HStack(spacing: 6) {
            Text("Mode:")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(ChatInputMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m.icon)
                            .font(.system(size: 10))
                        Text(m.localizedLabel)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(mode == m ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(mode == m ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Automation Tab

/// Shows scheduled automation jobs. Gateway logs are intentionally not shown
/// in this primary workflow.
struct TasksLogsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        CronTabView(viewModel: viewModel)
    }
}

// MARK: - Chat Session Row (sidebar)

/// Single row inside the Sessions sidebar section. Renders the title and
/// hover-only actions; the parent sidebar section drives `switchSession(to:)`.
struct ChatSessionRow: View {
    let meta: ChatSessionMetadata
    let isActive: Bool
    /// True when a foreground task is currently streaming inside this
    /// session (whether or not the session is the visible one).
    let isExecuting: Bool
    let isDeleteConfirming: Bool
    let onDeleteIntent: () -> Void
    let onDeleteConfirm: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(meta.title.isEmpty ? String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle) : meta.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
                .fontWeight(isActive ? .medium : .regular)
            Spacer(minLength: 4)

            if isHovering || isDeleteConfirming {
                Button(action: isDeleteConfirming ? onDeleteConfirm : onDeleteIntent) {
                    Image(systemName: isDeleteConfirming ? "trash.fill" : "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDeleteConfirming ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isDeleteConfirming ? Color.red : Color(NSColor.controlBackgroundColor))
                        }
                }
                .buttonStyle(.plain)
                .help(isDeleteConfirming
                      ? String(localized: "Confirm delete", bundle: LanguageManager.shared.localizedBundle)
                      : String(localized: "Delete", bundle: LanguageManager.shared.localizedBundle))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(isExecuting
              ? String(localized: "Task running", bundle: LanguageManager.shared.localizedBundle)
              : "\(meta.messageCount) · \(Self.fullRelative(meta.updatedAt))")
    }

    /// Compact form for inline sidebar display.
    /// Today    → "HH:mm"
    /// Yesterday→ "昨天"
    /// 2-6 days → "N 天前"
    /// Older    → "MM-dd"
    static func shortRelative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "昨天"
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 {
            return "\(days) 天前"
        }
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: date)
    }

    /// Verbose form used in the tooltip — keeps the abbreviated relative
    /// formatter for richer context on hover.
    static func fullRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    DashboardView(
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
    .frame(width: 960, height: 680)
}
