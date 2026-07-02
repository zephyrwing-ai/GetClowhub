import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

enum DashboardTypography {
    static let sidebarRow = Font.system(size: 14, weight: .regular)
    static let sidebarSectionTitle = Font.system(size: 14, weight: .regular)
    static let sidebarAgentName = Font.system(size: 14, weight: .regular)
    static let sidebarAgentNameActive = Font.system(size: 14, weight: .regular)
    static let sidebarSessionTitle = Font.system(size: 13.5, weight: .regular)
    static let composer = Font.system(size: 14, weight: .regular)
    static let composerPlaceholder = Font.system(size: 14, weight: .regular)
    static let message = Font.system(size: 14, weight: .regular)
    static let userMessage = Font.system(size: 14, weight: .regular)
    static let messageMeta = Font.system(size: 11, weight: .regular)

    static func sidebarAgent(active: Bool) -> Font {
        active ? sidebarAgentNameActive : sidebarAgentName
    }
}

enum DashboardSidebarMetrics {
    static let agentAvatarSize: CGFloat = 22
    static let agentTitleSpacing: CGFloat = 10
    static let disclosureChevronWidth: CGFloat = 12
    static let disclosureChevronHeight: CGFloat = 20
    static let sessionTitleLeadingSpacer: CGFloat = agentAvatarSize + agentTitleSpacing
    static let sessionRowContentHeight: CGFloat = 20
    static let sessionRowActionSize: CGFloat = 20
    static let sessionRowActionAreaWidth: CGFloat = sessionRowActionSize * 2 + 2
    static let sessionRowVerticalPadding: CGFloat = 4
}

private struct SessionRenamePresentation: Identifiable {
    let id: UUID
}

private struct RightInspectorContentUpdateID: Hashable {
    let selectedTab: DashboardViewModel.DashboardTab
    let selectedAgentId: String
    let terminalOpen: Bool
    let terminalHeight: CGFloat
    let selectedSettingsSection: String
    let marketplaceInstallRefreshID: Int
    let requestedUserMessageJumpId: UUID?
}

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @StateObject private var createAgentVM: SubAgentsViewModel
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    #endif
    @EnvironmentObject var languageManager: LanguageManager
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @AppStorage("appAccent") private var appAccent: String = "green"
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGlobalSessionSearchPresented = false
    @State private var globalSessionSearchText: String = ""
    @State private var isCreateAgentOverlayPresented = false
    @State private var expandedAgentIds: Set<String> = []
    @State private var workspaceSidebarExpanded = false
    @State private var isWorkspaceSidebarOpening = false
    @State private var isWorkspaceSidebarClosing = false
    @State private var workspaceSidebarExpandRequestID = 0
    @State private var workspaceSidebarCollapseRequestID = 0
    @State private var pendingWorkspaceSidebarCloseReset = false
    @State private var workspaceBrowserWidth: CGFloat = 280
    @State private var workspaceDetailWidth: CGFloat = 0
    @State private var selectedSettingsSection: SettingsPageSection = .profile
    @State private var marketplaceInstallRefreshID = 0
    @State private var sessionRenamePresentation: SessionRenamePresentation?
    @State private var sessionRenameDraft: String = ""
    @State private var requestedUserMessageJumpId: UUID?
    @State private var terminalOpen = false
    @State private var terminalHeight: CGFloat = 120
    @FocusState private var isGlobalSessionSearchFocused: Bool
    @FocusState private var isSessionRenameFocused: Bool

    private let workspaceSidebarMinWidth: CGFloat = 240
    private let workspaceSidebarMaxWidth: CGFloat = 420
    private let marketplaceDetailAnimation = Animation.spring(response: 0.26, dampingFraction: 0.86)
    private static let workspaceLayoutMetrics = OutputsSidebarLayoutMetrics()

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _createAgentVM = StateObject(wrappedValue: SubAgentsViewModel(openclawService: viewModel.openclawService))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTab: $viewModel.selectedTab,
                viewModel: viewModel,
                createAgentVM: createAgentVM,
                expandedAgentIds: $expandedAgentIds,
                onOpenGlobalSessionSearch: openGlobalSessionSearch,
                onRequestCreateAgent: presentCreateAgentOverlay,
                onRequestRenameSession: beginSessionRename,
                onOpenSettingsSection: openSettingsSection
            )
        } detail: {
            RightInspectorSplitView(
                isSidebarExpanded: isWorkspaceSidebarExpanded,
                sidebarWidth: max(workspaceColumnIdealWidth, Self.workspaceLayoutMetrics.browserWidth),
                minSidebarWidth: workspaceSidebarMinWidth,
                maxSidebarWidth: workspaceColumnMaxWidth,
                contentUpdateID: rightInspectorContentUpdateID,
                expandRequestID: workspaceSidebarExpandRequestID,
                collapseRequestID: workspaceSidebarCollapseRequestID,
                onSidebarExpandFinished: completeWorkspaceSidebarOpen,
                onSidebarCollapseFinished: completeWorkspaceSidebarClose
            ) {
                DetailContentView(
                    viewModel: viewModel,
                    workspaceSidebarController: workspaceSidebarController,
                    requestedUserMessageJumpId: $requestedUserMessageJumpId,
                    selectedSettingsSection: $selectedSettingsSection,
                    terminalOpen: $terminalOpen,
                    terminalHeight: $terminalHeight,
                    marketplaceInstallRefreshID: marketplaceInstallRefreshID,
                    onOpenMarketplaceDetail: presentMarketplaceDetail
                )
            } sidebar: {
                workspaceSidebarPane(width: max(workspaceColumnIdealWidth, Self.workspaceLayoutMetrics.browserWidth))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(colorSchemeForAppearance)
        .tint(AppAccentPalette.storedValue(appAccent).color)
        .background(TitlebarSeparatorSuppressor())
        .background(
            DashboardTitlebarAccessoryInstaller(
                isVisible: isChatTabActive,
                width: rightTitlebarAccessoryWidth
            ) {
                RightOutputsTitlebarAccessory(
                    isTerminalOpen: terminalOpen,
                    isExpanded: isWorkspaceSidebarExpanded,
                    toggleTerminal: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            terminalOpen.toggle()
                        }
                    },
                    toggle: toggleWorkspaceSidebar,
                    close: { hideWorkspaceSidebar(resetEditor: true) }
                )
            }
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let title = currentSessionTitle {
                    SessionTitleUserMessagesPopover(
                        title: title,
                        messages: currentSessionUserMessages,
                        onTapMessage: jumpToUserMessage
                    )
                }
            }
        }
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
        .overlay {
            if isCreateAgentOverlayPresented {
                createAgentOverlay
            }
        }
        .overlay {
            if sessionRenamePresentation != nil {
                sessionRenameOverlay
            }
        }
        .overlay {
            if let agent = viewModel.selectedMarketplaceAgent, shouldShowMarketplaceDetailOverlay {
                marketplaceDetailOverlay(for: agent)
            }
        }
        .animation(.easeInOut, value: viewModel.showSuccess)
        .animation(.easeInOut(duration: 0.16), value: isGlobalSessionSearchPresented)
        .animation(.easeInOut(duration: 0.16), value: isCreateAgentOverlayPresented)
        .animation(.easeInOut(duration: 0.16), value: sessionRenamePresentation?.id)
        .animation(marketplaceDetailAnimation, value: viewModel.selectedMarketplaceAgent?.id)
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

    private var activeTab: DashboardViewModel.DashboardTab {
        viewModel.selectedTab == .outputs ? .chat : viewModel.selectedTab
    }

    private var isChatTabActive: Bool {
        activeTab == .chat
    }

    private var currentSessionMetadata: ChatSessionMetadata? {
        guard let sessionId = viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId] else {
            return nil
        }
        return (viewModel.sessionsByAgent[viewModel.selectedAgentId] ?? []).first { $0.id == sessionId }
    }

    private var currentSessionTitle: String? {
        guard isChatTabActive, !viewModel.chatMessages.isEmpty else { return nil }
        let title = currentSessionMetadata?.title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }

    private var currentSessionUserMessages: [ChatMessage] {
        guard isChatTabActive else { return [] }
        return viewModel.chatMessages
            .filter { $0.role == .user }
    }

    private var hasWorkspaceDetailPanel: Bool {
        workspaceDetailWidth > 0
    }

    private func jumpToUserMessage(_ message: ChatMessage) {
        requestedUserMessageJumpId = message.id
    }

    private var isWorkspaceSidebarExpanded: Bool {
        isChatTabActive && (workspaceSidebarExpanded || hasWorkspaceDetailPanel)
    }

    private var shouldRetainWorkspaceSidebarContent: Bool {
        isChatTabActive && (workspaceSidebarExpanded || hasWorkspaceDetailPanel || isWorkspaceSidebarOpening || isWorkspaceSidebarClosing)
    }

    private var workspaceColumnIdealWidth: CGFloat {
        guard shouldRetainWorkspaceSidebarContent else { return 0 }
        return workspaceBrowserWidth + workspaceDetailWidth
    }

    private var workspaceColumnMaxWidth: CGFloat {
        workspaceSidebarMaxWidth + Self.workspaceLayoutMetrics.editorWidth
    }

    private var rightTitlebarAccessoryWidth: CGFloat {
        guard isChatTabActive else { return 0 }
        return 78
    }

    private var rightInspectorContentUpdateID: AnyHashable {
        AnyHashable(RightInspectorContentUpdateID(
            selectedTab: viewModel.selectedTab,
            selectedAgentId: viewModel.selectedAgentId,
            terminalOpen: terminalOpen,
            terminalHeight: terminalHeight,
            selectedSettingsSection: selectedSettingsSection.rawValue,
            marketplaceInstallRefreshID: marketplaceInstallRefreshID,
            requestedUserMessageJumpId: requestedUserMessageJumpId
        ))
    }

    private var activeWorkspaceRoot: WorkspaceSidebarRoot {
        if let projectId = currentSessionMetadata?.projectId,
           let project = viewModel.projectsById[projectId] {
            return WorkspaceSidebarRoot(
                displayName: project.displayName,
                path: project.rootPath,
                isProjectBound: true
            )
        }

        if let projectRoot = currentSessionMetadata?.projectRoot,
           !projectRoot.isEmpty {
            let displayName = currentSessionMetadata?.projectDisplayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return WorkspaceSidebarRoot(
                displayName: displayName?.isEmpty == false ? displayName! : URL(fileURLWithPath: projectRoot).lastPathComponent,
                path: projectRoot,
                isProjectBound: true
            )
        }

        let workspacePath = DashboardViewModel.resolveAgentWorkspace(viewModel.selectedAgentId)
        return WorkspaceSidebarRoot(
            displayName: "Agent Workspace",
            path: workspacePath,
            isProjectBound: false
        )
    }

    private var selectedWorkspacePath: String {
        activeWorkspaceRoot.path
    }

    private var currentAgentWorkspacePath: String {
        DashboardViewModel.resolveAgentWorkspace(viewModel.selectedAgentId)
    }

    private var workspaceSidebarController: WorkspaceSidebarController {
        WorkspaceSidebarController(
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
            hasEditor: hasWorkspaceDetailPanel,
            toggle: { toggleWorkspaceSidebar() }
        )
    }

    private func workspaceSidebarPane(width: CGFloat) -> some View {
        WorkspaceInspectorPane(
            root: activeWorkspaceRoot,
            browserWidth: min(workspaceBrowserWidth, width),
            editorWidth: Self.workspaceLayoutMetrics.editorWidth,
            onDetailWidthChanged: { detailWidth in
                workspaceDetailWidth = detailWidth
            },
            openFolder: openSelectedWorkspaceFolder
        )
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func toggleWorkspaceSidebar() {
        if isWorkspaceSidebarExpanded {
            hideWorkspaceSidebar(resetEditor: true)
        } else {
            revealWorkspaceSidebar()
        }
    }

    private func revealWorkspaceSidebar() {
        guard isChatTabActive else { return }
        guard !workspaceSidebarExpanded, !isWorkspaceSidebarOpening else { return }

        isWorkspaceSidebarClosing = false
        isWorkspaceSidebarOpening = true
        pendingWorkspaceSidebarCloseReset = false
        workspaceSidebarExpandRequestID += 1
    }

    private func hideWorkspaceSidebar(resetEditor: Bool) {
        guard shouldRetainWorkspaceSidebarContent else {
            if resetEditor {
                clearWorkspaceSidebarTransientState()
            }
            isWorkspaceSidebarOpening = false
            isWorkspaceSidebarClosing = false
            pendingWorkspaceSidebarCloseReset = false
            return
        }

        pendingWorkspaceSidebarCloseReset = pendingWorkspaceSidebarCloseReset || resetEditor
        if !isWorkspaceSidebarClosing {
            isWorkspaceSidebarOpening = false
            isWorkspaceSidebarClosing = true
            workspaceSidebarCollapseRequestID += 1
        }
    }

    private func completeWorkspaceSidebarOpen() {
        guard isWorkspaceSidebarOpening else { return }

        workspaceSidebarExpanded = true
        isWorkspaceSidebarOpening = false
        isWorkspaceSidebarClosing = false
        pendingWorkspaceSidebarCloseReset = false
    }

    private func completeWorkspaceSidebarClose() {
        guard isWorkspaceSidebarClosing else { return }

        let shouldReset = pendingWorkspaceSidebarCloseReset
        workspaceSidebarExpanded = false
        if shouldReset {
            clearWorkspaceSidebarTransientState()
        }
        pendingWorkspaceSidebarCloseReset = false
        isWorkspaceSidebarOpening = false
        isWorkspaceSidebarClosing = false
    }

    private func clearWorkspaceSidebarTransientState() {
        workspaceDetailWidth = 0
    }

    private func openSelectedWorkspaceFolder() {
        let workspaceURL = URL(fileURLWithPath: currentAgentWorkspacePath)
        try? FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(workspaceURL)
    }

    private var isDark: Bool {
        AppAppearanceMode.storedValue(appAppearance).resolvesDark(using: colorScheme)
    }

    private var colorSchemeForAppearance: ColorScheme? {
        AppAppearanceMode.storedValue(appAppearance).preferredColorScheme
    }

    private func openGlobalSessionSearch() {
        globalSessionSearchText = ""
        isGlobalSessionSearchPresented = true
        DispatchQueue.main.async {
            isGlobalSessionSearchFocused = true
        }
    }

    private func presentCreateAgentOverlay() {
        isCreateAgentOverlayPresented = true
    }

    private func dismissCreateAgentOverlay() {
        isCreateAgentOverlayPresented = false
    }

    private func handleCreatedAgent(_ agentId: String) {
        viewModel.loadAvailableAgents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.selectedAgentId = agentId
                viewModel.selectedTab = .chat
                expandedAgentIds.insert(agentId)
            }
        }
    }

    private var globalSearchResults: [ChatSessionMetadata] {
        Array(viewModel.chatSessionStore
            .searchSessions(query: globalSessionSearchText)
            .prefix(12))
    }

    private var createAgentOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(460, max(360, proxy.size.width - 64))

            ZStack {
                Color.black.opacity(isDark ? 0.24 : 0.12)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissCreateAgentOverlay()
                    }

                CreateAgentSheet(
                    viewModel: createAgentVM,
                    isPresented: Binding(
                        get: { isCreateAgentOverlayPresented },
                        set: { newValue in
                            if newValue {
                                isCreateAgentOverlayPresented = true
                            } else {
                                dismissCreateAgentOverlay()
                            }
                        }
                    ),
                    onCreatedWithId: { agentId in
                        handleCreatedAgent(agentId)
                    }
                )
                .frame(width: panelWidth)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(isDark ? 0.10 : 0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.34 : 0.16), radius: 32, x: 0, y: 20)
                .onTapGesture {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    private func beginSessionRename(_ meta: ChatSessionMetadata) {
        viewModel.switchSessionGlobally(to: meta.id)
        viewModel.selectedTab = .chat
        sessionRenameDraft = meta.title
        sessionRenamePresentation = SessionRenamePresentation(id: meta.id)
        DispatchQueue.main.async {
            isSessionRenameFocused = true
        }
    }

    private func saveSessionRename() {
        guard let presentation = sessionRenamePresentation else { return }
        viewModel.renameSession(presentation.id, to: sessionRenameDraft)
        dismissSessionRename()
    }

    private func dismissSessionRename() {
        sessionRenamePresentation = nil
        sessionRenameDraft = ""
        isSessionRenameFocused = false
    }

    private var sessionRenameOverlay: some View {
        GeometryReader { proxy in
            let panelWidth = min(420, max(320, proxy.size.width - 64))
            let canSave = !sessionRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let snowSurface = Color(red: 0.965, green: 0.973, blue: 0.955)
            let snowFieldSurface = Color(red: 0.925, green: 0.936, blue: 0.912)
            let snowText = Color(red: 0.10, green: 0.12, blue: 0.10)
            let snowSecondaryText = Color(red: 0.42, green: 0.44, blue: 0.40)

            DashboardModalOverlay(
                isDismissDisabled: false,
                scrimOpacity: isDark ? 0.28 : 0.16,
                verticalOffset: -44,
                onDismiss: dismissSessionRename
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(String(localized: "Rename chat", bundle: languageManager.localizedBundle))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(snowText)

                        Spacer()

                        Button {
                            dismissSessionRename()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(snowSecondaryText)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Close", bundle: languageManager.localizedBundle))
                    }

                    Text(String(localized: "Keep it short and recognizable", bundle: languageManager.localizedBundle))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(snowSecondaryText)

                    TextField(String(localized: "Chat name", bundle: languageManager.localizedBundle), text: $sessionRenameDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(snowText)
                        .focused($isSessionRenameFocused)
                        .onSubmit {
                            if canSave {
                                saveSessionRename()
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(snowFieldSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.10), lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        Spacer()

                        Button(String(localized: "Cancel", bundle: languageManager.localizedBundle), role: .cancel) {
                            dismissSessionRename()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button(String(localized: "Save", bundle: languageManager.localizedBundle)) {
                            saveSessionRename()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .frame(width: panelWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isDark
                                ? snowSurface.opacity(0.94)
                                : snowSurface
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(isDark ? 0.16 : 0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(isDark ? 0.36 : 0.18), radius: 34, x: 0, y: 22)
                .onTapGesture {}
                .onExitCommand {
                    dismissSessionRename()
                }
            }
        }
    }

    private func openSettingsSection(_ section: SettingsPageSection) {
        selectedSettingsSection = section
        viewModel.selectedTab = .config
    }

    private var shouldShowMarketplaceDetailOverlay: Bool {
        viewModel.selectedTab == .market
    }

    private func presentMarketplaceDetail(_ agent: MarketplaceAgent) {
        guard !viewModel.isRecruitingMarketplaceAgent else { return }
        withAnimation(marketplaceDetailAnimation) {
            viewModel.selectedMarketplaceAgent = agent
        }
    }

    private func dismissMarketplaceDetail() {
        guard !viewModel.isRecruitingMarketplaceAgent else { return }
        withAnimation(marketplaceDetailAnimation) {
            viewModel.selectedMarketplaceAgent = nil
        }
    }

    private func marketplaceDetailOverlay(for agent: MarketplaceAgent) -> some View {
        DashboardModalOverlay(
            isDismissDisabled: viewModel.isRecruitingMarketplaceAgent,
            onDismiss: dismissMarketplaceDetail
        ) {
            MarketplaceDetailView(
                agent: agent,
                openclawService: viewModel.openclawService,
                onInstalled: { _ in
                    viewModel.loadAvailableAgents()
                    marketplaceInstallRefreshID += 1
                },
                onClose: dismissMarketplaceDetail,
                onDismissDisabledChange: { disabled in
                    viewModel.isRecruitingMarketplaceAgent = disabled
                }
            )
            .id(agent.id)
        }
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
                            .tint(Color(NSColor.labelColor))
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

private let rightOutputsTitlebarAccessoryID = NSUserInterfaceItemIdentifier("GetClowHub.RightOutputsTitlebarAccessory")

private struct DashboardTitlebarAccessoryInstaller<Accessory: View>: NSViewRepresentable {
    let isVisible: Bool
    let width: CGFloat
    let height: CGFloat
    let accessory: Accessory

    init(
        isVisible: Bool,
        width: CGFloat,
        height: CGFloat = 44,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.isVisible = isVisible
        self.width = width
        self.height = height
        self.accessory = accessory()
    }

    func makeCoordinator() -> DashboardTitlebarAccessoryCoordinator {
        DashboardTitlebarAccessoryCoordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.update(
                window: view.window,
                isVisible: isVisible,
                width: width,
                height: height,
                rootView: AnyView(accessory)
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(
                window: nsView.window,
                isVisible: isVisible,
                width: width,
                height: height,
                rootView: AnyView(accessory)
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: DashboardTitlebarAccessoryCoordinator) {
        coordinator.remove()
    }
}

private final class DashboardTitlebarAccessoryCoordinator {
    private weak var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private var accessoryController: NSTitlebarAccessoryViewController?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    func update(
        window targetWindow: NSWindow?,
        isVisible: Bool,
        width: CGFloat,
        height: CGFloat,
        rootView: AnyView
    ) {
        guard isVisible, let targetWindow else {
            remove()
            return
        }

        if window !== targetWindow {
            remove()
            window = targetWindow
        }

        removeStaleAccessories(from: targetWindow)

        let hostingController = hostingController ?? NSHostingController(rootView: rootView)
        hostingController.rootView = rootView
        hostingController.view.identifier = rightOutputsTitlebarAccessoryID
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.hostingController = hostingController

        let accessoryController = accessoryController ?? NSTitlebarAccessoryViewController()
        if self.accessoryController == nil {
            accessoryController.layoutAttribute = .right
            accessoryController.view = hostingController.view
            targetWindow.addTitlebarAccessoryViewController(accessoryController)
            self.accessoryController = accessoryController
            widthConstraint = hostingController.view.widthAnchor.constraint(equalToConstant: max(width, 44))
            heightConstraint = hostingController.view.heightAnchor.constraint(equalToConstant: height)
            NSLayoutConstraint.activate([widthConstraint, heightConstraint].compactMap { $0 })
        }

        let targetWidth = max(width, 44)
        if let widthConstraint, abs(widthConstraint.constant - targetWidth) > 0.5 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = RightInspectorSplitMetrics.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                self.widthConstraint?.animator().constant = targetWidth
                hostingController.view.superview?.layoutSubtreeIfNeeded()
            }
        } else {
            widthConstraint?.constant = targetWidth
        }
        heightConstraint?.constant = height
    }

    func remove() {
        guard let accessoryController else {
            hostingController = nil
            widthConstraint = nil
            heightConstraint = nil
            window = nil
            return
        }

        if let window,
           let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessoryController }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }

        self.accessoryController = nil
        hostingController = nil
        widthConstraint = nil
        heightConstraint = nil
        window = nil
    }

    private func removeStaleAccessories(from window: NSWindow) {
        let indexedControllers = window.titlebarAccessoryViewControllers.enumerated()
        for (index, controller) in indexedControllers.reversed() {
            guard controller !== accessoryController,
                  controller.view.identifier == rightOutputsTitlebarAccessoryID else {
                continue
            }
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }
}


private struct RightOutputsTitlebarAccessory: View {
    let isTerminalOpen: Bool
    let isExpanded: Bool
    let toggleTerminal: () -> Void
    let toggle: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleTerminal) {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isTerminalOpen ? .accentColor : .secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help(isTerminalOpen ? "Hide Terminal" : "Show Terminal")

            Button(action: isExpanded ? close : toggle) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide Outputs" : "Show Outputs")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTab: DashboardViewModel.DashboardTab
    @Binding var expandedAgentIds: Set<String>
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var createAgentVM: SubAgentsViewModel
    let onOpenGlobalSessionSearch: () -> Void
    let onRequestCreateAgent: () -> Void
    let onRequestRenameSession: (ChatSessionMetadata) -> Void
    let onOpenSettingsSection: (SettingsPageSection) -> Void
    @EnvironmentObject var sparkleUpdater: SparkleUpdater
    @EnvironmentObject var languageManager: LanguageManager
    #if REQUIRE_LOGIN
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var membershipManager: MembershipManager
    #endif
    @AppStorage("appAppearance") private var appAppearance: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    private enum SidebarChromeAction: Hashable {
        case newChat
        case searchChats
    }

    // Agent context menu state
    @State private var deleteAgentConfirmId: String?

    // Chat session management state
    @State private var confirmingDeleteSessionId: UUID?

    // Marketplace state
    @State private var marketplaceSearchText = ""
    @State private var expandedDivisions: Set<String> = []
    @State private var expandedAgentDivisions: Set<String> = []
    @State private var hoveredSessionId: UUID?
    @State private var hoveredSidebarTab: DashboardViewModel.DashboardTab?
    @State private var hoveredSidebarAction: SidebarChromeAction?
    @State private var areAgentsCollapsed = false
    @State private var isPinnedSessionsExpanded = true
    @State private var isAgentSectionHeaderHovering = false

    init(
        selectedTab: Binding<DashboardViewModel.DashboardTab>,
        viewModel: DashboardViewModel,
        createAgentVM: SubAgentsViewModel,
        expandedAgentIds: Binding<Set<String>>,
        onOpenGlobalSessionSearch: @escaping () -> Void,
        onRequestCreateAgent: @escaping () -> Void,
        onRequestRenameSession: @escaping (ChatSessionMetadata) -> Void,
        onOpenSettingsSection: @escaping (SettingsPageSection) -> Void
    ) {
        self._selectedTab = selectedTab
        self._expandedAgentIds = expandedAgentIds
        self.viewModel = viewModel
        self.createAgentVM = createAgentVM
        self.onOpenGlobalSessionSearch = onOpenGlobalSessionSearch
        self.onRequestCreateAgent = onRequestCreateAgent
        self.onRequestRenameSession = onRequestRenameSession
        self.onOpenSettingsSection = onOpenSettingsSection
    }

    private var isDark: Bool {
        AppAppearanceMode.storedValue(appAppearance).resolvesDark(using: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarTopHeader
            sidebarMainList
            Divider()
            sidebarBottomBar
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        .alert("Remove Agent", isPresented: Binding<Bool>(
            get: { deleteAgentConfirmId != nil },
            set: { if !$0 { deleteAgentConfirmId = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let agentId = deleteAgentConfirmId {
                    Task {
                        let deleted = await createAgentVM.deleteAgent(agentId: agentId)
                        await MainActor.run {
                            if deleted {
                                viewModel.loadAvailableAgents()
                                expandedAgentIds.remove(agentId)
                                viewModel.removeDeletedAgentState(agentId: agentId)
                            } else {
                                viewModel.errorMessage = createAgentVM.lastActionError ?? "Failed to remove agent \(agentId)"
                                viewModel.showError = true
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
    }

    // MARK: - Sidebar Top Header

    /// Top of the sidebar — text-only app label. NavigationSplitView's own
    /// toggle in the window toolbar handles sidebar collapse.
    private var sidebarTopHeader: some View {
        HStack(spacing: 8) {
            Text("GetClawHub")
                .font(.system(size: 14, weight: .semibold))

            if sparkleUpdater.updateAvailable {
                Button {
                    cancelSessionDeleteConfirmation()
                    sparkleUpdater.checkForUpdates()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 10))
                        Text("v\(sparkleUpdater.latestVersion)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(isDark ? 0.16 : 0.10))
                    )
                }
                .buttonStyle(.plain)
                .help("Update to v\(sparkleUpdater.latestVersion)")
            }

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
        SmoothScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ServiceStatusBadge(viewModel: viewModel)
                    .padding(.bottom, 8)

                Button {
                    cancelSessionDeleteConfirmation()
                    viewModel.createNewSession()
                    selectedTab = .chat
                } label: {
                    let isNewChatActive = selectedTab == .chat
                        && viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId] == nil

                    sidebarRowContent(title: String(localized: "New chat", bundle: languageManager.localizedBundle), systemImage: "plus.circle")
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sidebarItemHighlightColor(
                                    isActive: isNewChatActive,
                                    isHovering: hoveredSidebarAction == .newChat
                                ))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    updateSidebarActionHover(.newChat, hovering: hovering)
                }

                Button {
                    cancelSessionDeleteConfirmation()
                    onOpenGlobalSessionSearch()
                } label: {
                    sidebarRowContent(title: String(localized: "Search chats", bundle: languageManager.localizedBundle), systemImage: "magnifyingglass")
                        .foregroundColor(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(sidebarItemHighlightColor(
                                    isActive: false,
                                    isHovering: hoveredSidebarAction == .searchChats
                                ))
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    updateSidebarActionHover(.searchChats, hovering: hovering)
                }
                .help(String(localized: "Search chats", bundle: languageManager.localizedBundle))

                navRow(.skills, title: String(localized: "Skills", bundle: languageManager.localizedBundle), systemImage: AppSystemSymbol.skills)
                navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "powerplug.portrait")
                navRow(.tasksLogs, title: String(localized: "Automation", bundle: languageManager.localizedBundle), systemImage: "clock.badge")
                navRow(.market, title: String(localized: "AgentsMarket", bundle: languageManager.localizedBundle), systemImage: "storefront")

                globalPinnedSessionsSection
                agentSectionContent

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func navRow(_ tab: DashboardViewModel.DashboardTab, title: String, systemImage: String, assetImage: String? = nil) -> some View {
        Button {
            cancelSessionDeleteConfirmation()
            selectedTab = tab
        } label: {
            sidebarRowContent(title: title, systemImage: systemImage, assetImage: assetImage)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(sidebarItemHighlightColor(
                            isActive: selectedTab == tab,
                            isHovering: hoveredSidebarTab == tab
                        ))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            updateSidebarTabHover(tab, hovering: hovering)
        }
    }

    private func sidebarRowContent(title: String, systemImage: String, assetImage: String? = nil) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(systemImage: systemImage, assetImage: assetImage)
                .frame(width: 18, height: 18)
            Text(title)
                .lineLimit(1)
            Spacer()
        }
        .font(DashboardTypography.sidebarRow)
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func sidebarIcon(systemImage: String, assetImage: String?) -> some View {
        if let assetImage {
            Image(assetImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: systemImage)
        }
    }

    // MARK: - Sessions Section Content (extracted so it stays readable)

    @ViewBuilder
    private func sessionsSectionContent(for agent: AgentOption) -> some View {
        let projectGroups = viewModel.projectSessionsByAgent[agent.id] ?? []
        let generalSessions = viewModel.generalSessionsByAgent[agent.id] ?? []

        if projectGroups.isEmpty && generalSessions.isEmpty {
            Text(String(localized: "No sessions yet", bundle: languageManager.localizedBundle))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
        } else {
            projectFoldersSectionContent(for: agent)
            generalSessionsSectionContent(for: agent)
        }
    }

    @ViewBuilder
    private func projectFoldersSectionContent(for agent: AgentOption) -> some View {
        let projectGroups = viewModel.projectSessionsByAgent[agent.id] ?? []

        ForEach(projectGroups) { group in
            projectFolderRow(group: group, agent: agent)
        }
    }

    @ViewBuilder
    private func generalSessionsSectionContent(for agent: AgentOption) -> some View {
        let generalSessions = viewModel.generalSessionsByAgent[agent.id] ?? []
        sessionRows(generalSessions, for: agent)
    }

    @ViewBuilder
    private func sessionRows(
        _ agentSessions: [ChatSessionMetadata],
        for agent: AgentOption? = nil,
        switchGlobally: Bool = false
    ) -> some View {
        ForEach(agentSessions) { meta in
            let isSessionActive = selectedTab == .chat
                && viewModel.selectedAgentId == meta.agentId
                && viewModel.selectedSessionIdByAgent[meta.agentId] == meta.id
            let isSessionHovering = hoveredSessionId == meta.id

            ChatSessionRow(
                meta: meta,
                isActive: isSessionActive,
                isExecuting: viewModel.hasInflightTask(inSession: meta.id),
                isHovering: isSessionHovering,
                isDeleteConfirming: confirmingDeleteSessionId == meta.id,
                onPinToggle: {
                    cancelSessionDeleteConfirmation()
                    viewModel.togglePinSession(meta.id)
                },
                onDeleteIntent: {
                    confirmingDeleteSessionId = meta.id
                },
                onDeleteConfirm: {
                    viewModel.deleteSession(meta.id)
                    confirmingDeleteSessionId = nil
                }
            )
            .padding(.horizontal, 8)
            .padding(.vertical, DashboardSidebarMetrics.sessionRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(sessionRowHighlightColor(isActive: isSessionActive, isHovering: isSessionHovering))
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                cancelSessionDeleteConfirmation()
                onRequestRenameSession(meta)
            }
            .onTapGesture {
                cancelSessionDeleteConfirmation()
                if switchGlobally {
                    viewModel.switchSessionGlobally(to: meta.id)
                } else {
                    viewModel.switchSession(to: meta.id)
                }
                selectedTab = .chat
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    if hovering {
                        hoveredSessionId = meta.id
                    } else if hoveredSessionId == meta.id {
                        hoveredSessionId = nil
                    }
                }
            }
            .contextMenu {
                Button {
                    cancelSessionDeleteConfirmation()
                    onRequestRenameSession(meta)
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

    private func projectFolderRow(group: ProjectSessionGroup, agent: AgentOption) -> some View {
        AgentProjectFolderRow(
            group: group,
            backgroundColor: { isHovering in
                sidebarItemHighlightColor(isActive: false, isHovering: isHovering)
            },
            onToggle: {
                cancelSessionDeleteConfirmation()
                viewModel.toggleProjectCollapse(agentId: agent.id, projectId: group.project.id)
            },
            onNewSession: {
                cancelSessionDeleteConfirmation()
                viewModel.createNewSession(forAgent: agent.id, projectId: group.project.id)
                selectedTab = .chat
            },
            onRevealInFinder: {
                viewModel.revealProjectInFinder(group.project.id)
            },
            onRemoveFromAgent: {
                viewModel.removeProject(group.project.id, fromAgent: agent.id)
            },
            sessions: {
                sessionRows(group.sessions, for: agent)
            }
        )
    }

    @ViewBuilder
    private var globalPinnedSessionsSection: some View {
        if !viewModel.pinnedSessions.isEmpty {
            SidebarCollapsibleRow(
                title: "Pinned",
                titleFont: DashboardTypography.sidebarAgent(active: false),
                isExpanded: isPinnedSessionsExpanded,
                rowHeight: 24,
                verticalPadding: 4,
                backgroundColor: { isHovering in
                    sidebarItemHighlightColor(isActive: false, isHovering: isHovering)
                },
                onToggle: {
                    cancelSessionDeleteConfirmation()
                    isPinnedSessionsExpanded.toggle()
                },
                icon: {
                    Image(systemName: "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                },
                actions: {
                    EmptyView()
                },
                children: {
                    sessionRows(viewModel.pinnedSessions, switchGlobally: true)
                }
            )
            .padding(.top, 6)
        }
    }

    // MARK: - Agent Section Content

    @ViewBuilder
    private var agentSectionContent: some View {
        let visibleAgents = viewModel.availableAgents.filter {
            !DashboardViewModel.internalAgentIds.contains($0.id)
        }

        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(String(localized: "Agent", bundle: languageManager.localizedBundle))
                    .font(DashboardTypography.sidebarSectionTitle)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 20)
                    .rotationEffect(.degrees(areAgentsCollapsed ? 0 : 90))
                    .opacity(isAgentSectionHeaderHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.16), value: areAgentsCollapsed)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggleAgentSectionCollapse()
            }
            .help(areAgentsCollapsed
                  ? String(localized: "Show agents", bundle: languageManager.localizedBundle)
                    : String(localized: "Hide agents", bundle: languageManager.localizedBundle))

        }
        .frame(height: 20)
        .overlay(alignment: .trailing) {
            Button {
                cancelSessionDeleteConfirmation()
                onRequestCreateAgent()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(isAgentSectionHeaderHovering ? 1 : 0)
            .disabled(!isAgentSectionHeaderHovering)
            .help(String(localized: "New Agent", bundle: languageManager.localizedBundle))
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isAgentSectionHeaderHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isAgentSectionHeaderHovering)

        Group {
            if !areAgentsCollapsed {
                Group {
                    if visibleAgents.isEmpty {
                        Text(String(localized: "No agents yet", bundle: languageManager.localizedBundle))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(visibleAgents) { agent in
                            agentSidebarRow(agent)
                        }
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: areAgentsCollapsed)
    }

    // MARK: - Sidebar Bottom Bar

    private var sidebarBottomBar: some View {
        SettingsShortcutPanelButton(
            viewModel: viewModel,
            isActive: selectedTab == .config,
            highlightColor: { isOpen in
                sidebarItemHighlightColor(isActive: selectedTab == .config, isHovering: isOpen)
            },
            onBeforeToggle: {
                cancelSessionDeleteConfirmation()
            },
            onOpenSettingsSection: onOpenSettingsSection
        )
        .padding(.horizontal, 12)
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

    private func agentSidebarRow(_ agent: AgentOption) -> some View {
        let isActive = viewModel.selectedAgentId == agent.id && selectedTab == .chat

        return SidebarCollapsibleRow(
            title: agent.name,
            titleFont: DashboardTypography.sidebarAgent(active: isActive),
            isExpanded: expandedAgentIds.contains(agent.id),
            rowHeight: 24,
            verticalPadding: 4,
            backgroundColor: { isHovering in
                sidebarItemHighlightColor(isActive: isActive, isHovering: isHovering)
            },
            onToggle: {
                toggleAgentSelection(agent)
            },
            icon: {
                AgentAvatarImage(size: DashboardSidebarMetrics.agentAvatarSize, isExpanded: expandedAgentIds.contains(agent.id))
            },
            actions: {
                Button {
                    cancelSessionDeleteConfirmation()
                    viewModel.openProject(forAgent: agent.id)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Add Work Folder...")

                Button {
                    createSession(for: agent)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle))
            },
            children: {
                sessionsSectionContent(for: agent)
            }
        )
        .contextMenu {
            Button {
                viewModel.openProject(forAgent: agent.id)
            } label: {
                Label("Add Work Folder...", systemImage: "folder.badge.plus")
            }
            Divider()
            if canDeleteAgent(agent) {
                Button(role: .destructive) {
                    deleteAgentConfirmId = agent.id
                } label: {
                    Label("Remove Agent", systemImage: "trash")
                }
            }
        }
    }

    private func agentRowWithContextMenu(_ agent: AgentOption) -> some View {
        SidebarCollapsibleRow(
            title: agent.name,
            titleFont: DashboardTypography.sidebarAgent(active: viewModel.selectedAgentId == agent.id),
            isExpanded: false,
            rowHeight: 24,
            verticalPadding: 4,
            backgroundColor: { _ in SwiftUI.Color.clear },
            onToggle: {},
            icon: {
                AgentAvatarImage(size: DashboardSidebarMetrics.agentAvatarSize)
            },
            actions: {
                Button {
                    cancelSessionDeleteConfirmation()
                    viewModel.openProject(forAgent: agent.id)
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Add Work Folder...")

                Button {
                    createSession(for: agent)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle))
            },
            children: {
                EmptyView()
            }
        )
        .tag(agent.id)
        .contextMenu {
            Button {
                viewModel.openProject(forAgent: agent.id)
            } label: {
                Label("Add Work Folder...", systemImage: "folder.badge.plus")
            }
            Divider()
            if canDeleteAgent(agent) {
                Button(role: .destructive) {
                    deleteAgentConfirmId = agent.id
                } label: {
                    Label("Remove Agent", systemImage: "trash")
                }
            }
        }
    }

    private func canDeleteAgent(_ agent: AgentOption) -> Bool {
        agent.id != "main"
            && agent.id != "commander"
            && !DashboardViewModel.internalAgentIds.contains(agent.id)
    }

    private func sidebarItemHighlightColor(isActive: Bool, isHovering: Bool) -> SwiftUI.Color {
        if isActive {
            return SwiftUI.Color.primary.opacity(isDark ? 0.15 : 0.085)
        }
        if isHovering {
            return SwiftUI.Color.primary.opacity(isDark ? 0.10 : 0.058)
        }
        return SwiftUI.Color.clear
    }

    private func updateSidebarTabHover(_ tab: DashboardViewModel.DashboardTab, hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if hovering {
                hoveredSidebarTab = tab
            } else if hoveredSidebarTab == tab {
                hoveredSidebarTab = nil
            }
        }
    }

    private func updateSidebarActionHover(_ action: SidebarChromeAction, hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if hovering {
                hoveredSidebarAction = action
            } else if hoveredSidebarAction == action {
                hoveredSidebarAction = nil
            }
        }
    }

    private func sessionRowHighlightColor(isActive: Bool, isHovering: Bool) -> SwiftUI.Color {
        if isActive {
            return SwiftUI.Color.primary.opacity(isDark ? 0.16 : 0.11)
        }
        if isHovering {
            return SwiftUI.Color.primary.opacity(isDark ? 0.11 : 0.07)
        }
        return SwiftUI.Color.clear
    }

    private func cancelSessionDeleteConfirmation() {
        confirmingDeleteSessionId = nil
    }

    private func toggleAgentSectionCollapse() {
        cancelSessionDeleteConfirmation()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            areAgentsCollapsed.toggle()
        }
    }

    private func toggleAgentSelection(_ agent: AgentOption) {
        cancelSessionDeleteConfirmation()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if expandedAgentIds.contains(agent.id) {
                expandedAgentIds.remove(agent.id)
            } else {
                expandedAgentIds.insert(agent.id)
            }
        }
    }

    private func createSession(for agent: AgentOption) {
        cancelSessionDeleteConfirmation()
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
        MarketplaceCatalog.shared.search(query: marketplaceSearchText, localeID: languageManager.currentLocale.identifier)
    }

    /// Agents grouped by division, used when not searching
    private var agentsByDivision: [(division: String, agents: [MarketplaceAgent])] {
        let catalog = MarketplaceCatalog.shared
        return catalog.divisions.compactMap { div in
            let agents = catalog.search(query: "", division: div, localeID: languageManager.currentLocale.identifier)
            guard !agents.isEmpty else { return nil }
            return (division: div, agents: agents)
        }
    }

    private var marketplaceList: some View {
        VStack(spacing: 0) {
            UnifiedSearchField(
                placeholder: String(localized: "Search agents...", bundle: languageManager.localizedBundle),
                text: $marketplaceSearchText
            )
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Agent list - tree view or flat search results.
            //
            // Selecting an agent updates the same selected agent used by
            // the market grid highlight and the root-level modal overlay.
            // It also switches the main content to the market tab so the
            // sidebar selection, page title, grid, and detail modal stay
            // synchronized around one current agent.
            List(selection: Binding<MarketplaceAgent?>(
                get: { viewModel.selectedMarketplaceAgent },
                set: { newAgent in
                    guard !viewModel.isRecruitingMarketplaceAgent else { return }
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                        viewModel.selectedMarketplaceAgent = newAgent
                        if newAgent != nil {
                            viewModel.selectedTab = .market
                        }
                    }
                }
            )) {
                if marketplaceSearchText.isEmpty {
                    // Tree view grouped by division
                    ForEach(agentsByDivision, id: \.division) { group in
                        let emoji = Self.divisionEmoji[group.division] ?? "📁"
                        let divisionName = MarketplaceCatalog.shared.localizedDivisionName(group.division, localeID: languageManager.currentLocale.identifier)
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
                            Text(verbatim: "\(emoji) \(divisionName) (\(group.agents.count))")
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

struct SidebarCollapsibleRow<Icon: View, Actions: View, Children: View>: View {
    private static var expansionAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86)
    }

    private static var hoverAnimation: Animation {
        .easeInOut(duration: 0.12)
    }

    private static var childTransition: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    let title: String
    let titleFont: Font
    let isExpanded: Bool
    let rowHeight: CGFloat
    let verticalPadding: CGFloat
    let backgroundColor: (Bool) -> SwiftUI.Color
    let onToggle: () -> Void
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let children: () -> Children

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    children()
                }
                .transition(Self.childTransition)
                .clipped()
            }
        }
        .animation(Self.expansionAnimation, value: isExpanded)
        .clipped()
    }

    private var rowContent: some View {
        HStack(spacing: DashboardSidebarMetrics.agentTitleSpacing) {
            icon()
                .frame(width: DashboardSidebarMetrics.agentAvatarSize, height: DashboardSidebarMetrics.agentAvatarSize)

            Text(title)
                .font(titleFont)
                .lineLimit(1)

            chevron

            Spacer(minLength: 8)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .trailing) {
            HStack(spacing: 2) {
                actions()
            }
            .opacity(isHovering ? 1 : 0)
            .disabled(!isHovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(isHovering))
        )
        .onTapGesture {
            withAnimation(Self.expansionAnimation) {
                onToggle()
            }
        }
        .onHover { hovering in
            withAnimation(Self.hoverAnimation) {
                isHovering = hovering
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(
                width: DashboardSidebarMetrics.disclosureChevronWidth,
                height: DashboardSidebarMetrics.disclosureChevronHeight
            )
            .opacity(isHovering || isExpanded ? 1 : 0)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.easeInOut(duration: 0.16), value: isExpanded)
            .animation(Self.hoverAnimation, value: isHovering)
    }
}

// MARK: - Pulsing Dot (green breathing animation)

// MARK: - Marketplace Agent Row

private struct MarketplaceAgentRow: View {
    let agent: MarketplaceAgent
    @EnvironmentObject var languageManager: LanguageManager

    private var display: MarketplaceAgentDisplay {
        agent.localizedDisplay(localeID: languageManager.currentLocale.identifier)
    }

    var body: some View {
        HStack(spacing: 10) {
            AgentAvatarImage(size: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(display.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if !display.description.isEmpty {
                    Text(display.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Text(display.division)
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

private struct DetailContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let workspaceSidebarController: WorkspaceSidebarController
    @Binding var requestedUserMessageJumpId: UUID?
    @Binding var selectedSettingsSection: SettingsPageSection
    @Binding var terminalOpen: Bool
    @Binding var terminalHeight: CGFloat
    let marketplaceInstallRefreshID: Int
    let onOpenMarketplaceDetail: (MarketplaceAgent) -> Void
    @State private var collabPanelWidth: CGFloat = 320
    @State private var dragStartWidth: CGFloat = 320

    private let collabPanelMinWidth: CGFloat = 220
    private let collabPanelMaxWidth: CGFloat = 500
    private let collabCollapsedWidth: CGFloat = 24

    private var activeTab: DashboardViewModel.DashboardTab {
        viewModel.selectedTab == .outputs ? .chat : viewModel.selectedTab
    }

    var body: some View {
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

            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            let showChat = activeTab == .chat
            ChatView(
                viewModel: viewModel,
                requestedUserMessageJumpId: $requestedUserMessageJumpId,
                terminalOpen: $terminalOpen,
                terminalHeight: $terminalHeight,
                hideAgentPicker: false
            )
                .environment(\.workspaceSidebarController, workspaceSidebarController)
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
                        MarketplaceView(
                            selectedAgent: viewModel.selectedMarketplaceAgent,
                            installRefreshID: marketplaceInstallRefreshID,
                            onSelectAgent: onOpenMarketplaceDetail
                        )
                    case .tasksLogs:
                        TasksLogsTabView(viewModel: viewModel)
                    case .config:
                        ConfigTabView(
                            viewModel: viewModel,
                            selectedSection: $selectedSettingsSection
                        )
                    case .skills:
                        SkillsTabView(
                            openclawService: viewModel.openclawService,
                            notifySuccess: viewModel.showSuccessMessage,
                            notifyError: viewModel.showErrorMessage
                        )
                    case .models:
                        ModelsTabView(viewModel: viewModel)
                    case .outputs:
                        EmptyView()
                    case .channels:
                        ChannelsTabView(viewModel: viewModel)
                    case .plugins:
                        PluginsTabView(
                            openclawService: viewModel.openclawService,
                            notifySuccess: viewModel.showSuccessMessage,
                            notifyError: viewModel.showErrorMessage
                        )
                    case .cron:
                        CronTabView(viewModel: viewModel)
                    case .logs:
                        LogsTabView(viewModel: viewModel)
                    }
                }
            }
        }
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

struct PendingComposerMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    var attachments: [URL]

    init(id: UUID = UUID(), text: String, attachments: [URL] = []) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }
}

private enum ChatAutoScrollMode: Equatable {
    case followingBottom
    case userDetached
    case sessionJumping
}

private struct ChatScrollIntentObserver: NSViewRepresentable {
    let onScrollPositionChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollPositionChange: onScrollPositionChange)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScrollPositionChange = onScrollPositionChange

        DispatchQueue.main.async {
            guard let scrollView = Self.nearestScrollView(from: nsView) else { return }
            context.coordinator.attach(to: scrollView)
        }
    }

    private static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            if let scrollView = candidate.enclosingScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }

    final class Coordinator {
        var onScrollPositionChange: (Bool) -> Void
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?

        init(onScrollPositionChange: @escaping (Bool) -> Void) {
            self.onScrollPositionChange = onScrollPositionChange
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else {
                reportPosition(in: scrollView)
                return
            }

            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }

            self.scrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let scrollView else { return }
                self?.reportPosition(in: scrollView)
            }

            reportPosition(in: scrollView)
        }

        private func reportPosition(in scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else {
                onScrollPositionChange(true)
                return
            }

            scrollView.layoutSubtreeIfNeeded()
            documentView.layoutSubtreeIfNeeded()

            let clipView = scrollView.contentView
            let documentHeight = documentView.bounds.height
            let viewportHeight = clipView.bounds.height
            guard documentHeight > viewportHeight + 1 else {
                onScrollPositionChange(true)
                return
            }

            let offsetY = clipView.bounds.origin.y
            let distanceToBottom: CGFloat
            if documentView.isFlipped {
                let maxOffset = max(0, documentHeight - viewportHeight)
                distanceToBottom = maxOffset - offsetY
            } else {
                distanceToBottom = offsetY
            }

            onScrollPositionChange(distanceToBottom <= 24)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var requestedUserMessageJumpId: UUID?
    @Binding var terminalOpen: Bool
    @Binding var terminalHeight: CGFloat
    var hideAgentPicker: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputText = ""
    // The `ChatInputMode` picker (聊天/执行任务/代码模式) used to live here
    // but was hidden in v1.1.46 — see the toolbar row below and the
    // `ChatInputModePicker` definition for the disabled state's reasoning.
    @State private var eventMonitor: Any?
    @State private var queryHistory: [String] = UserDefaults.standard.stringArray(forKey: "chatQueryHistory") ?? []
    @State private var historyIndex: Int = -1
    // Slash command autocomplete
    @State private var slashSelectedIndex: Int = 0
    @FocusState private var isInputFocused: Bool
    @State private var focusMonitor: Any?
    // Skills panel
    @State private var skillsSelectedIndex: Int = 0
    @State private var skillJustSelected: Bool = false
    // @ Agent mention panel
    @State private var agentSelectedIndex: Int = 0
    @State private var agentJustSelected: Bool = false
    // Composer model selector
    @State private var showComposerSelector = false
    // File attachments
    @State private var attachedFiles: [URL] = []
    // Scroll debounce for streaming content
    @State private var scrollDebounceWork: DispatchWorkItem?
    // Smart scroll: follow only while the user is reading the latest messages.
    @State private var chatAutoScrollMode: ChatAutoScrollMode = .followingBottom
    @State private var chatScrollIsAtBottom = true
    @State private var scheduledBottomScrollGeneration = 0
    @State private var scrollEventMonitor: Any?
    // Store ScrollViewProxy so sendMessage() can scroll to bottom
    @State private var chatScrollProxy: ScrollViewProxy?
    @State private var highlightedMessageId: UUID?
    @State private var highlightedMessageFlashOn = false
    @State private var highlightFlashTask: Task<Void, Never>?
    // Create agent sheet
    @State private var showCreateAgentSheet = false
    @StateObject private var createAgentVM: SubAgentsViewModel
    @State private var pendingComposerMessagesBySession: [UUID: [PendingComposerMessage]] = [:]
    @State private var renderObservationStartBySession: [UUID: ContinuousClock.Instant] = [:]
    private static let layoutMetrics = OutputsSidebarLayoutMetrics()
    private static let emptyChatContentYOffset: CGFloat = -48
    private let composerEditorHeight: CGFloat = 76
    private let composerSuggestionPanelMaxHeight: CGFloat = 184

    init(
        viewModel: DashboardViewModel,
        requestedUserMessageJumpId: Binding<UUID?> = .constant(nil),
        terminalOpen: Binding<Bool> = .constant(false),
        terminalHeight: Binding<CGFloat> = .constant(120),
        hideAgentPicker: Bool = false
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._requestedUserMessageJumpId = requestedUserMessageJumpId
        self._terminalOpen = terminalOpen
        self._terminalHeight = terminalHeight
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

    private var currentActiveSessionId: UUID? {
        viewModel.selectedSessionIdByAgent[viewModel.selectedAgentId]
    }

    private var currentPendingComposerMessages: [PendingComposerMessage] {
        guard let sessionId = currentActiveSessionId else { return [] }
        return pendingComposerMessagesBySession[sessionId] ?? []
    }

    private var currentForegroundTaskMessageId: UUID? {
        guard let sessionId = currentActiveSessionId else { return nil }
        return viewModel.foregroundTaskIds.first { viewModel.taskSessionMap[$0] == sessionId }
    }

    private var shouldShowStopButton: Bool {
        viewModel.isSendingMessage
            && inputText.trimmingCharacters(in: .whitespaces).isEmpty
            && attachedFiles.isEmpty
            && currentForegroundTaskMessageId != nil
    }

    private var shouldFollowChatBottom: Bool {
        chatAutoScrollMode == .followingBottom || chatAutoScrollMode == .sessionJumping
    }

    // MARK: - Chat Message List (extracted for compiler performance)

    @ViewBuilder
    private func chatScrollContent(proxy: ScrollViewProxy) -> some View {
        let scrollView = ChatTimelineSurface(
            messages: viewModel.chatMessages,
            viewModel: viewModel,
            proxy: proxy,
            columnMaxWidth: Self.layoutMetrics.chatColumnMaxWidth,
            highlightedMessageId: highlightedMessageId,
            highlightedMessageFlashOn: highlightedMessageFlashOn,
            onConfirmEditResend: { original, editedText in
                viewModel.rewindToMessage(original, replacementText: editedText)
            },
            onCancel: { viewModel.cancelChat($0.id) }
        )
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
                    logChatMessagesCountChanged()
                    // Only auto-scroll while the user is following the latest message.
                    if shouldFollowChatBottom {
                        // Use animated scroll so LazyVStack can progressively create views
                        // during the scroll animation, avoiding white flash from instant jump
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            scrollToBottomIfAllowed()
                        }
                    }
                }
        } else {
            scrollView
                .onChange(of: viewModel.chatMessages.count) { _ in
                    logChatMessagesCountChanged()
                    if shouldFollowChatBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            scrollToBottomIfAllowed()
                        }
                    }
                }
                .onAppear {
                    if !viewModel.chatMessages.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottomIfAllowed()
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollToBottomIfAllowed()
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
    private var readyComposerSkills: [SkillInfo] {
        viewModel.skills.filter { $0.status == .ready }
    }

    private var filteredSkills: [SkillInfo] {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        // Exact "/skills" or "/skills " prefix
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return [] }
        let keyword = trimmed.hasPrefix("/skills ") ? String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces) : ""
        let allSkills = readyComposerSkills
        if keyword.isEmpty { return allSkills }
        return allSkills.filter { skill in
            let catalogItem = catalogItem(for: skill)
            let display = catalogItem.map { I18n.skillDisplay(for: $0) }
            return I18n.localizedSearchFields(
                [
                    skill.name,
                    display?.displayName ?? "",
                    display?.description ?? skill.description
                ],
                originals: [
                    catalogItem?.displayName ?? skill.name,
                    catalogItem?.description ?? skill.description,
                    skill.description,
                    skill.source
                ]
            )
            .joined(separator: " ")
            .lowercased()
            .contains(keyword)
        }
    }

    private var skillCatalogItemsByName: [String: SkillCatalogItem] {
        SkillNameIndex.firstByName(viewModel.skillCatalog) { $0.name }
    }

    private func catalogItem(for skill: SkillInfo) -> SkillCatalogItem? {
        skillCatalogItemsByName[skill.name]
    }

    private func localizedSkillDescription(for skill: SkillInfo) -> String? {
        if let catalogItem = catalogItem(for: skill) {
            return nonBlankString(I18n.skillDisplay(for: catalogItem).description)
        }
        return nonBlankString(skill.description)
    }

    private func nonBlankString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localizedSkillHelp(for skill: SkillInfo) -> String {
        localizedSkillDescription(for: skill) ?? skill.name
    }

    private var showSkillsPanel: Bool {
        if skillJustSelected { return false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed == "/skills" || trimmed.hasPrefix("/skills ") else { return false }
        guard !readyComposerSkills.isEmpty else { return false }
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

    private var showComposerSuggestions: Bool {
        showSlashPanel || showSkillsPanel || showAgentPanel
    }

    private var composerSuggestionSelectedBackground: SwiftUI.Color {
        Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08)
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
            .offset(y: Self.emptyChatContentYOffset)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelineChatSurface: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .topTrailing) {
                    chatScrollContent(proxy: proxy)
                        .onAppear {
                            chatScrollProxy = proxy
                            if !viewModel.chatMessages.isEmpty && shouldFollowChatBottom {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    scrollToBottomIfAllowed()
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToBottomIfAllowed()
                                }
                            }
                        }
                    ChatScrollIntentObserver(onScrollPositionChange: { isAtBottom in
                        handleChatScrollPositionChange(isAtBottom: isAtBottom)
                    })
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
            }
            .id("chatScrollView")

            composerArea(maxWidth: Self.layoutMetrics.chatColumnMaxWidth, horizontalPadding: 16, bottomPadding: 16)
        }
    }

    private func handleChatScrollPositionChange(isAtBottom: Bool) {
        guard chatScrollIsAtBottom != isAtBottom else { return }
        chatScrollIsAtBottom = isAtBottom

        if isAtBottom && chatAutoScrollMode == .userDetached {
            chatAutoScrollMode = .followingBottom
        }
    }

    private func composerArea(maxWidth: CGFloat, horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        VStack(spacing: 8) {
            if !currentPendingComposerMessages.isEmpty {
                PendingComposerQueueView(
                    messages: currentPendingComposerMessages,
                    onSend: sendPendingComposerMessage,
                    onEdit: editPendingComposerMessage,
                    onDelete: deletePendingComposerMessage
                )
            }

            composerInputCard
                .anchorPreference(key: ComposerInputCardBoundsKey.self, value: .bounds) { $0 }
        }
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
        .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
        .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
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
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(cmd.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(index == slashSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
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
            .frame(maxHeight: composerSuggestionPanelMaxHeight)
        }
        .autocompletePanelStyle()
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
                                let description = localizedSkillDescription(for: skill)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text(skill.name)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let description {
                                        Text(description)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    if !skill.source.isEmpty {
                                        Text(skill.source)
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(index == skillsSelectedIndex ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == skillsSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
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
                .frame(maxHeight: composerSuggestionPanelMaxHeight)
            }
        }
        .autocompletePanelStyle()
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
                                        .foregroundColor(.primary)
                                    if agent.id != agent.name {
                                        Text(agent.id)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if agent.id == viewModel.selectedAgentId {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(index == agentSelectedIndex ? .primary : .secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == agentSelectedIndex ? composerSuggestionSelectedBackground : Color.clear)
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
                .frame(maxHeight: composerSuggestionPanelMaxHeight)
            }
        }
        .autocompletePanelStyle()
    }

    private var composerInputCard: some View {
        ChatComposerView(
            viewModel: viewModel,
            inputText: $inputText,
            attachedFiles: $attachedFiles,
            showComposerSelector: $showComposerSelector,
            isInputFocused: $isInputFocused,
            isInputLocked: isInputLocked,
            shouldShowStopButton: shouldShowStopButton,
            currentForegroundTaskMessageId: currentForegroundTaskMessageId,
            canSend: canSend,
            sendButtonFillColor: sendButtonFillColor,
            sendButtonIconColor: sendButtonIconColor,
            composerEditorHeight: composerEditorHeight,
            onOpenFilePicker: openFilePicker,
            onSendMessage: sendMessage,
            onCancelMessage: { viewModel.cancelChat($0) }
        )
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

    private func closeComposerSelector() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showComposerSelector = false
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
    private func composerSuggestionOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor, showComposerSuggestions {
                let inputFrame = proxy[anchor]
                let panelTopOffset = max(12, inputFrame.minY - composerSuggestionPanelMaxHeight - 8)

                ZStack(alignment: .topLeading) {
                    composerFloatingPanels
                        .frame(width: inputFrame.width)
                        .frame(maxHeight: composerSuggestionPanelMaxHeight, alignment: .bottomLeading)
                        .offset(x: inputFrame.minX, y: panelTopOffset)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .zIndex(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .allowsHitTesting(showComposerSuggestions)
                .animation(.easeInOut(duration: 0.15), value: showSlashPanel)
                .animation(.easeInOut(duration: 0.15), value: showSkillsPanel)
                .animation(.easeInOut(duration: 0.15), value: showAgentPanel)
            }
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

                    ComposerModelPanel(
                        modelGroups: viewModel.availableModelGroups,
                        currentModel: viewModel.activeComposerModel,
                        defaultModel: viewModel.modelOverview.defaultModel,
                        isOpen: $showComposerSelector,
                        onSelectModel: viewModel.selectComposerModel
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.trailing, trailingOffset)
                    .padding(.bottom, bottomOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                    .zIndex(1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .animation(.easeInOut(duration: 0.18), value: showComposerSelector)
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if viewModel.chatMessages.isEmpty {
                emptyChatSurface
            } else {
                timelineChatSurface
            }

            if terminalOpen {
                terminalPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: terminalOpen)
    }

    var body: some View {
        chatContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlayPreferenceValue(ComposerInputCardBoundsKey.self) { anchor in
                composerSuggestionOverlay(anchor: anchor)
            }
            .overlayPreferenceValue(ComposerSelectorButtonBoundsKey.self) { anchor in
                composerSelectorOverlay(anchor: anchor)
            }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: requestedUserMessageJumpId) { messageId in
            guard let messageId else { return }
            jumpToUserMessage(messageId)
            requestedUserMessageJumpId = nil
        }
        .onAppear {
            viewModel.loadAvailableAgents()
            if viewModel.skills.isEmpty {
                Task { await viewModel.loadSkillMarket() }
            }

            // Monitor scroll wheel events to detect user scrolling
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
                scrollEventMonitor = nil
            }
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                if event.scrollingDeltaY < 0 {
                    chatAutoScrollMode = .userDetached
                    scheduledBottomScrollGeneration += 1
                }

                return event
            }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handleCopyShortcut(event) {
                    return nil
                }

                guard let responder = event.window?.firstResponder, responder is NSTextView else {
                    return event
                }
                // Don't intercept keys when the code editor's NSTextView is focused
	                if let tv = responder as? NSTextView, tv.identifier?.rawValue == "codeEditorTextView" {
	                    return event
	                }

	                // macOS TextField editing uses a shared NSTextView field editor.
	                // Those field editors belong to the active TextField, not to the
	                // chat composer, so composer shortcuts/focus must ignore them.
	                if let tv = responder as? NSTextView, tv.isFieldEditor {
	                    return event
	                }

	                // Don't intercept keys when a CommitTextField (rename/new file) is focused
	                if let tv = responder as? NSTextView,
	                   tv.identifier?.rawValue == "commitTextField" {
                    return event
                }

                if let tv = responder as? NSTextView,
                   tv.identifier?.rawValue == "inlineMessageEditorTextView" {
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
	                    if let responder = NSApp.keyWindow?.firstResponder,
	                       let textView = responder as? NSTextView,
	                       !textView.isFieldEditor {
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
            if let monitor = scrollEventMonitor {
                NSEvent.removeMonitor(monitor)
                scrollEventMonitor = nil
            }
            highlightFlashTask?.cancel()
            highlightFlashTask = nil
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
        .onChange(of: viewModel.composerPrefill) { newValue in
            guard let prefill = newValue else { return }
            inputText = prefill
            attachedFiles = []
            historyIndex = -1
            withAnimation(.easeOut(duration: 0.15)) {
                isInputFocused = true
            }
            viewModel.composerPrefill = nil
        }
        .onChange(of: viewModel.isSendingMessage) { isSending in
            if !isSending {
                drainPendingComposerQueueIfPossible()
            }
        }
        .onChange(of: currentActiveSessionId) { _ in
            drainPendingComposerQueueIfPossible()
            beginRenderObservationForCurrentSession()
            scheduleSessionSwitchScrollToBottom()
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
        return hasText || hasFiles
    }

    private func handleCopyShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c" else {
            return false
        }

        if NativeSelectableTextSelectionRegistry.copySelectedTextFromFirstResponder(nil) {
            return true
        }

        return NativeSelectableTextSelectionRegistry.copyActiveSelection()
    }

    private var sendButtonFillColor: SwiftUI.Color {
        canSend || shouldShowStopButton
            ? Color.primary.opacity(0.62)
            : Color(NSColor.quaternaryLabelColor)
    }

    private var sendButtonIconColor: SwiftUI.Color {
        canSend || shouldShowStopButton
            ? Color(NSColor.windowBackgroundColor)
            : Color(NSColor.tertiaryLabelColor)
    }

    /// Whether the input area (text + attachment) should be locked.
    /// Session-scoped — see comment in `canSend`. Switching to a
    /// different session of the same agent unlocks the input even if
    /// the previous session has a task still streaming in the
    /// inactive-sessions map.
    private var isInputLocked: Bool {
        false
    }

    private func sendMessage() {
        var text = inputText.trimmingCharacters(in: .whitespaces)
        let files = attachedFiles
        guard !text.isEmpty || !files.isEmpty else { return }
        inputText = ""
        attachedFiles = []

        if viewModel.isSendingMessage {
            enqueuePendingComposerMessage(text: text, attachments: files)
            return
        }

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
            let clarifyingText = String(localized: "Understanding requirements...", bundle: LanguageManager.shared.localizedBundle)
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander"))

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
                            content: String(localized: "Starting task execution...", bundle: LanguageManager.shared.localizedBundle),
                            agentId: "commander"
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
                                agentId: "commander"
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
            viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: "", agentId: "commander", taskStatus: .loading, id: thinkingId))
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
                            agentId: "commander"
                        ))
                        viewModel.isSendingMessage = false
                    }
                } else {
                    // Commander says this needs collab — proceed with full flow
                    await MainActor.run {
                        let clarifyingText = String(localized: "Understanding requirements...", bundle: LanguageManager.shared.localizedBundle)
                        viewModel.chatMessagesByAgent["commander", default: []].append(ChatMessage(role: .assistant, content: clarifyingText, agentId: "commander"))

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
        followChatBottomFromUserAction()

        Task {
            await viewModel.sendChatMessage(text, attachments: files)
            if isResetCommand {
                await MainActor.run { viewModel.clearChat() }
            }
        }
    }

    private func enqueuePendingComposerMessage(text: String, attachments: [URL]) {
        guard let sessionId = currentActiveSessionId else { return }
        let pending = PendingComposerMessage(text: text, attachments: attachments)
        pendingComposerMessagesBySession[sessionId, default: []].append(pending)
    }

    private func deletePendingComposerMessage(_ message: PendingComposerMessage) {
        guard let sessionId = currentActiveSessionId else { return }
        pendingComposerMessagesBySession[sessionId, default: []].removeAll { $0.id == message.id }
        if pendingComposerMessagesBySession[sessionId]?.isEmpty == true {
            pendingComposerMessagesBySession.removeValue(forKey: sessionId)
        }
    }

    private func editPendingComposerMessage(_ message: PendingComposerMessage) {
        deletePendingComposerMessage(message)
        inputText = message.text
        attachedFiles = message.attachments
        historyIndex = -1
        withAnimation(.easeOut(duration: 0.15)) {
            isInputFocused = true
        }
    }

    private func sendPendingComposerMessage(_ message: PendingComposerMessage) {
        if viewModel.isSendingMessage {
            promotePendingComposerMessage(message)
            return
        }

        deletePendingComposerMessage(message)
        inputText = message.text
        attachedFiles = message.attachments
        followChatBottomFromUserAction()
        sendMessage()
    }

    private func promotePendingComposerMessage(_ message: PendingComposerMessage) {
        guard let sessionId = currentActiveSessionId,
              var queue = pendingComposerMessagesBySession[sessionId],
              let index = queue.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        let promoted = queue.remove(at: index)
        queue.insert(promoted, at: 0)
        pendingComposerMessagesBySession[sessionId] = queue
    }

    private func drainPendingComposerQueueIfPossible() {
        guard !viewModel.isSendingMessage,
              let sessionId = currentActiveSessionId,
              var queue = pendingComposerMessagesBySession[sessionId],
              !queue.isEmpty else {
            return
        }

        let next = queue.removeFirst()
        if queue.isEmpty {
            pendingComposerMessagesBySession.removeValue(forKey: sessionId)
        } else {
            pendingComposerMessagesBySession[sessionId] = queue
        }

        inputText = next.text
        attachedFiles = next.attachments
        followChatBottomFromUserAction()
        sendMessage()
    }

    /// Scroll chat to the latest message with animation.
    private func scheduleSessionSwitchScrollToBottom() {
        chatAutoScrollMode = .sessionJumping
        scheduledBottomScrollGeneration += 1
        let generation = scheduledBottomScrollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            logScheduledBottomScroll(checkpoint: "0.05")
            scrollToBottomIfAllowed(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            logScheduledBottomScroll(checkpoint: "0.25")
            scrollToBottomIfAllowed(generation: generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            logScheduledBottomScroll(checkpoint: "0.70")
            scrollToBottomIfAllowed(generation: generation)
            if scheduledBottomScrollGeneration == generation,
               chatAutoScrollMode == .sessionJumping {
                chatAutoScrollMode = .followingBottom
            }
        }
    }

    private func scrollToBottomIfAllowed(generation: Int? = nil) {
        if let generation, scheduledBottomScrollGeneration != generation { return }
        guard chatAutoScrollMode != .userDetached else { return }
        guard let proxy = chatScrollProxy else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("chatBottom", anchor: .bottom)
        }
    }

    private func followChatBottomFromUserAction() {
        chatAutoScrollMode = .followingBottom
        scheduledBottomScrollGeneration += 1
        scrollToBottomIfAllowed()
    }

    private func beginRenderObservationForCurrentSession() {
        guard let sessionId = currentActiveSessionId else { return }
        renderObservationStartBySession[sessionId] = ContinuousClock.now
        chatRenderPerfLog.info("phase=session_changed session=\(sessionId.uuidString, privacy: .public) message_count=\(viewModel.chatMessages.count, privacy: .public)")
    }

    private func logChatMessagesCountChanged() {
        guard let sessionId = currentActiveSessionId else { return }
        if renderObservationStartBySession[sessionId] == nil {
            renderObservationStartBySession[sessionId] = ContinuousClock.now
        }
        let elapsedText = renderElapsedMillisecondsText(for: sessionId)
        chatRenderPerfLog.info("phase=messages_count_changed session=\(sessionId.uuidString, privacy: .public) message_count=\(viewModel.chatMessages.count, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
    }

    private func logScheduledBottomScroll(checkpoint: String) {
        guard let sessionId = currentActiveSessionId else { return }
        let elapsedText = renderElapsedMillisecondsText(for: sessionId)
        chatRenderPerfLog.info("phase=scheduled_bottom_scroll checkpoint=\(checkpoint, privacy: .public) session=\(sessionId.uuidString, privacy: .public) message_count=\(viewModel.chatMessages.count, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
    }

    private func renderElapsedMillisecondsText(for sessionId: UUID) -> String {
        guard let start = renderObservationStartBySession[sessionId] else { return "n/a" }
        return dashboardElapsedMillisecondsText(since: start)
    }

    private func jumpToUserMessage(_ messageId: UUID) {
        guard viewModel.chatMessages.contains(where: { $0.id == messageId && $0.role == .user }) else { return }
        chatAutoScrollMode = .userDetached
        scheduledBottomScrollGeneration += 1
        withAnimation(.easeInOut(duration: 0.24)) {
            chatScrollProxy?.scrollTo(messageId, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            triggerUserMessageHighlight(messageId)
        }
    }

    private func triggerUserMessageHighlight(_ messageId: UUID) {
        highlightFlashTask?.cancel()
        highlightedMessageId = messageId
        highlightedMessageFlashOn = false

        highlightFlashTask = Task { @MainActor in
            for step in 0..<6 {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.13)) {
                    highlightedMessageFlashOn = step % 2 == 0
                }
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                highlightedMessageFlashOn = false
            }
            if highlightedMessageId == messageId {
                highlightedMessageId = nil
            }
            highlightFlashTask = nil
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
        guard skill.status == .ready else { return }
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
    func autocompletePanelStyle() -> some View {
        self
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct ComposerInputCardBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct ComposerSelectorButtonBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct ComposerModelSelector: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isOpen: Bool

    private var modelLabel: String {
        let raw = viewModel.activeComposerModel
        let resolved = raw.isEmpty ? viewModel.modelOverview.defaultModel : raw
        let cleaned = stripProviderPrefix(resolved)
        return cleaned.isEmpty || cleaned == "-" ? "Model" : cleaned
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOpen.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.system(size: 12, weight: .medium))

                Text(modelLabel)
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
        .help("Model")
        .anchorPreference(key: ComposerSelectorButtonBoundsKey.self, value: .bounds) { anchor in
            isOpen ? anchor : nil
        }
    }
}

private struct ComposerModelPanel: View {
    let modelGroups: [ProviderModelGroup]
    let currentModel: String
    let defaultModel: String
    @Binding var isOpen: Bool
    let onSelectModel: (String) -> Void

    private static let maxModelPanelHeight: CGFloat = 420

    private var allModelIds: Set<String> {
        Set(modelGroups.flatMap { $0.models.map(\.id) })
    }

    private var effectiveSelectedModel: String {
        currentModel.isEmpty ? defaultModel : currentModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Model")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !effectiveSelectedModel.isEmpty
                        && effectiveSelectedModel != "-"
                        && !allModelIds.contains(effectiveSelectedModel) {
                        Button {
                            selectModel(effectiveSelectedModel)
                        } label: {
                            selectorRow(
                                title: stripProviderPrefix(effectiveSelectedModel),
                                subtitle: nil,
                                selected: true,
                                showsDisclosure: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(modelGroups) { group in
                        if !group.models.isEmpty {
                            sectionHeader(for: group)

                            ForEach(group.models) { model in
                                Button {
                                    selectModel(model.id)
                                } label: {
                                    selectorRow(
                                        title: stripProviderPrefix(model.name),
                                        subtitle: nil,
                                        selected: model.id == effectiveSelectedModel,
                                        showsDisclosure: false
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: Self.maxModelPanelHeight)
        .panelChrome(cornerRadius: 22)
    }

    private func sectionHeader(for group: ProviderModelGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider()
                .opacity(0.55)
                .padding(.top, 6)
            HStack(spacing: 7) {
                Image(systemName: group.providerKey == "getclawhub" ? "cloud" : "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(group.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(group.models.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private func selectorRow(
        title: String,
        subtitle: String?,
        selected: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: subtitle == nil ? 44 : 52)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.secondary.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func selectModel(_ model: String) {
        withAnimation(.easeInOut(duration: 0.16)) {
            onSelectModel(model)
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
        VStack(alignment: .leading, spacing: 6) {
            WorkStatusHeader(
                start: message.timestamp,
                end: nil,
                activityEvents: message.activityEvents
            )
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct PendingComposerQueueView: View {
    let messages: [PendingComposerMessage]
    let onSend: (PendingComposerMessage) -> Void
    let onEdit: (PendingComposerMessage) -> Void
    let onDelete: (PendingComposerMessage) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(messages) { message in
                HStack(spacing: 8) {
                    Text(message.text.isEmpty ? attachmentSummary(for: message) : message.text)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !message.attachments.isEmpty {
                        Text("\(message.attachments.count)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    MessageActionIcon(
                        systemName: "paperplane",
                        tint: .secondary,
                        help: "发送这条",
                        action: { onSend(message) }
                    )

                    MessageActionIcon(
                        systemName: "pencil",
                        tint: .secondary,
                        help: "编辑待发送内容",
                        action: { onEdit(message) }
                    )

                    MessageActionIcon(
                        systemName: "xmark",
                        tint: .secondary,
                        help: "删除待发送内容",
                        action: { onDelete(message) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func attachmentSummary(for message: PendingComposerMessage) -> String {
        message.attachments.count == 1 ? "1 个附件" : "\(message.attachments.count) 个附件"
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

struct ChatBubble: View {
    let message: ChatMessage
    let allowsRichMarkdown: Bool
    let isJumpHighlighted: Bool
    /// Confirmed edit-resend for a user message. The destructive rewind happens
    /// only after the inline editor's confirm action calls this callback.
    var onConfirmEditResend: ((ChatMessage, String) -> Void)? = nil
    /// Cancel the in-flight run for this message. When set, a cancel button
    /// appears next to the streaming spinner so a run can be stopped mid-stream.
    var onCancel: ((ChatMessage) -> Void)? = nil
    @State private var isHovering = false
    @State private var cachedMediaURLs: [URL] = []
    @State private var lastMediaScanContent: String = ""
    @State private var isEditingForResend = false
    @State private var editDraft = ""
    @State private var isRichMarkdownActivated = false

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
                // Attachment thumbnails (user-attached files)
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                if showsTopWorkStatus {
                    WorkStatusHeader(
                        start: message.timestamp,
                        end: message.completedAt,
                        activityEvents: message.activityEvents
                    )
                }

                if !message.content.isEmpty {
	                    // Bubble body: prefer native MarkdownUI for ordinary
	                    // assistant text so session switches and streaming do
	                    // not cold-mount a WKWebView for every message. Fall
	                    // back to WebKit only for complex content that native
	                    // MarkdownUI cannot represent well here (tables, math,
	                    // raw HTML).
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
                                    AssistantMessageContentView(
                                        content: message.content,
                                        isStreaming: isStreamingState,
                                        allowsRichMarkdown: allowsRichMarkdown || isRichMarkdownActivated
                                    )
	                                    .fixedSize(horizontal: false, vertical: true)
		                                    .padding(10)
	                                    .background(isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
	                                    .cornerRadius(12)
	                            } else if isEditingForResend {
                                InlineUserMessageEditor(
                                    text: $editDraft,
                                    onCommit: confirmEditResend,
                                    onCancel: cancelEditResend
                                )
                                .frame(minHeight: 76)
	                                .padding(8)
	                                .background(isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
		                                .cornerRadius(12)
	                            } else {
                                    NativeSelectableMarkdownView(
                                        content: message.content,
                                        fullTextCopyFallback: message.content,
                                        parsesMarkdown: false,
                                        fontSize: 14,
                                        lineSpacing: 2,
                                        paragraphSpacing: 0
                                    )
                                        .fixedSize(horizontal: false, vertical: true)
			                                    .padding(10)
			                                    .background(isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
                                        .cornerRadius(12)
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
                        if !isStreamingState && !message.content.isEmpty && !isEditingForResend {
                            HStack(spacing: 2) {
                                MessageActionIcon(
                                    systemName: copied ? "checkmark" : "square.on.square",
                                    tint: copied ? .green : .secondary,
                                    help: copied ? "已复制" : "复制",
                                    action: { performCopy(message.content) }
	                                )
                                if canActivateRichMarkdown {
                                    MessageActionIcon(
                                        systemName: "doc.richtext",
                                        tint: .secondary,
                                        help: "渲染复杂内容",
                                        action: { isRichMarkdownActivated = true }
                                    )
                                }
                                // Edit & resend only makes sense for the user's
                                // own messages (you edit your prompt, not the
                                // assistant's output), so the rewind icon is
                                // gated to .user bubbles.
                                if onConfirmEditResend != nil && message.role == .user {
                                    MessageActionIcon(
                                        systemName: "arrow.uturn.backward",
                                        tint: .secondary,
                                        help: "编辑重发",
                                        action: { beginEditResend() }
                                    )
                                }
                                if let ts = message.timestamp {
                                    Text(Self.formatTimestamp(ts))
                                        .font(DashboardTypography.messageMeta)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                        .padding(.leading, 4)
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

                // Detected media files from assistant response
                if !cachedMediaURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cachedMediaURLs, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .onAppear {
            logBubbleAppear()
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

    private func logBubbleAppear() {
        chatRenderPerfLog.info("phase=bubble_appear message=\(message.id.uuidString, privacy: .public) role=\(message.role.rawValue, privacy: .public) status=\(message.taskStatus.rawValue, privacy: .public) content_length=\(message.content.count, privacy: .public) attachment_count=\(message.attachments.count, privacy: .public) activity_count=\(message.activityEvents.count, privacy: .public) allows_rich_markdown=\(allowsRichMarkdown || isRichMarkdownActivated, privacy: .public)")
    }

    private var bubbleBackgroundColor: SwiftUI.Color {
        message.role == .user
            ? Color.gray.opacity(0.14)
            : Color(NSColor.controlBackgroundColor)
    }

    private var jumpHighlightBackgroundColor: SwiftUI.Color {
        Color.gray.opacity(0.42)
    }

    /// True while the message is still being generated — covers both the
    /// foreground `.loading` and `.background` (running detached) statuses.
    /// Used to gate the hover toolbar; we don't want a stale "Copy
    /// half-streamed text" affordance.
    private var isStreamingState: Bool {
        message.role == .assistant
            && (message.taskStatus == .loading || message.taskStatus == .background)
    }

    private var showsTopWorkStatus: Bool {
        message.role == .assistant
            && (isStreamingState || message.completedAt != nil)
    }

    private func beginEditResend() {
        editDraft = message.content
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = true
            isHovering = true
        }
    }

    private var canActivateRichMarkdown: Bool {
        message.role == .assistant
            && !isStreamingState
            && !allowsRichMarkdown
            && !isRichMarkdownActivated
            && MarkdownRenderPolicy.isComplexMarkdown(message.content)
    }

    private func cancelEditResend() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = false
        }
        editDraft = ""
    }

    private func confirmEditResend() {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelEditResend()
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = false
        }
        onConfirmEditResend?(message, trimmed)
        editDraft = ""
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

private struct InlineUserMessageEditor: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            InlineMessageEditorTextView(
                text: $text,
                onCommit: onCommit,
                onCancel: onCancel
            )
            .frame(minHeight: 54, maxHeight: 160)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .help("取消")

                Button(action: onCommit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(NSColor.windowBackgroundColor))
                        .frame(width: 26, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.62))
                        }
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("确认并发送")
            }
        }
    }
}

private struct InlineMessageEditorTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommitAwareTextView()
        textView.identifier = NSUserInterfaceItemIdentifier("inlineMessageEditorTextView")
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.insertionPointColor = NSColor.labelColor

        scrollView.documentView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommitAwareTextView else { return }
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class CommitAwareTextView: NSTextView {
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36,
               !event.modifierFlags.contains(.shift),
               !hasMarkedText() {
                onCommit?()
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            super.keyDown(with: event)
        }
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
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                            .frame(width: 40, height: 40)
                        if isDirectory {
                            WorkspaceFolderIcon(isExpanded: false, size: 20)
                        } else {
                            Image(systemName: fileIconName)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(attachmentTypeLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 22)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 206, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.trailing, 5)
        }
    }

    private var attachmentTypeLabel: String {
        if isDirectory { return "FOLDER" }
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    private var fileIconName: String {
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
                AgentAvatarImage(size: 28)

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
                await viewModel.loadSkillMarket()
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
                    AgentAvatarImage(size: 24)
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
                            if !item.isUser {
                                AgentAvatarImage(size: 12)
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
            AgentAvatarImage(size: 36)
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
                            Label(a.name, systemImage: "checkmark")
                        } else {
                            Text(a.name)
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
                    .help(localizedSkillHelp(for: skill))
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

    private func localizedSkillHelp(for skill: SkillInfo) -> String {
        if let catalogItem = SkillNameIndex.firstByName(viewModel.skillCatalog, name: { $0.name })[skill.name] {
            let localizedDescription = I18n.skillDisplay(for: catalogItem).description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !localizedDescription.isEmpty {
                return localizedDescription
            }
        }
        let rawDescription = skill.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawDescription.isEmpty ? skill.name : rawDescription
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
        let isUser: Bool
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
    let isHovering: Bool
    let isDeleteConfirming: Bool
    let onPinToggle: () -> Void
    let onDeleteIntent: () -> Void
    let onDeleteConfirm: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: DashboardSidebarMetrics.sessionTitleLeadingSpacer)

            Text(meta.title.isEmpty ? String(localized: "New chat", bundle: LanguageManager.shared.localizedBundle) : meta.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(.primary)
                .font(DashboardTypography.sidebarSessionTitle)
                .fontWeight(isActive ? .medium : .regular)
            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button(action: onPinToggle) {
                    Image(systemName: meta.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: DashboardSidebarMetrics.sessionRowActionSize, height: DashboardSidebarMetrics.sessionRowActionSize)
                }
                .buttonStyle(.plain)
                .help(meta.isPinned
                      ? String(localized: "Unpin", bundle: LanguageManager.shared.localizedBundle)
                      : String(localized: "Pin", bundle: LanguageManager.shared.localizedBundle))

                Button(action: isDeleteConfirming ? onDeleteConfirm : onDeleteIntent) {
                    Image(systemName: isDeleteConfirming ? "trash.fill" : "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isDeleteConfirming ? .red : .secondary)
                        .frame(width: DashboardSidebarMetrics.sessionRowActionSize, height: DashboardSidebarMetrics.sessionRowActionSize)
                }
                .buttonStyle(.plain)
                .help(isDeleteConfirming
                      ? String(localized: "Confirm delete", bundle: LanguageManager.shared.localizedBundle)
                      : String(localized: "Delete", bundle: LanguageManager.shared.localizedBundle))
            }
            .frame(width: DashboardSidebarMetrics.sessionRowActionAreaWidth, alignment: .trailing)
            .opacity(isHovering || isDeleteConfirming ? 1 : 0)
            .disabled(!(isHovering || isDeleteConfirming))
        }
        .frame(height: DashboardSidebarMetrics.sessionRowContentHeight)
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
