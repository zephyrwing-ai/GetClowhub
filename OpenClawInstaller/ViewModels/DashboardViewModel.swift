import Foundation
import Combine
import AppKit
import SwiftUI
import os.log

private let chatLog = Logger(subsystem: "com.openclaw.installer", category: "Chat")

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var openclawService: OpenClawService
    @Published var settings: AppSettingsManager
    @Published var systemEnvironment: SystemEnvironment

    // Debug logging
    private let chatDebugLog = OSLog(subsystem: "com.openclaw.chat", category: "debug")
    private func logChat(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date()).suffix(12)
        let fullMsg = "[\(timestamp)] \(message)"
        print(fullMsg)
        os_log("[CHAT] %{public}@", log: chatDebugLog, type: .debug, fullMsg)
    }

    // UI State
    @Published var selectedTab: DashboardTab = .chat
    @Published var isPerformingAction = false
    @Published var showError = false
    @Published var errorMessage: String = ""
    @Published var showSuccess = false
    @Published var successMessage: String = ""

    // Configuration
    @Published var editedPort: String = ""
    @Published var editedAuthToken: String = ""
    @Published var editedModelBaseUrl: String = ""
    @Published var editedModelApiKey: String = ""

    // Provider Preset
    let presetManager = ProviderPresetManager()
    @Published var availableProviders: [ProviderPreset] = []
    @Published var editedSelectedProviderKey: String = ""
    @Published var editedProviderApi: String = "openai-completions"
    @Published var editedConfiguredModels: [PresetModel] = []
    @Published var showProviderSwitchConfirm = false
    @Published var editedActiveServiceSource: String = "custom" // "getclawhub" or "custom"
    @Published var editedGetClawHubApiKey: String = "" // Editable API key for GetClawHub
    var pendingProviderKey: String = ""

    /// Computed: true when any edited field differs from saved settings.
    /// Works because editedXxx are @Published — any change triggers SwiftUI re-render,
    /// which re-evaluates this property.
    var hasUnsavedChanges: Bool {
        let s = settings.settings
        return editedPort != String(s.gatewayPort)
            || editedAuthToken != s.gatewayAuthToken
            || editedModelBaseUrl != s.modelBaseUrl
            || editedModelApiKey != s.modelApiKey
            || editedSelectedProviderKey != s.selectedProviderKey
            || editedProviderApi != s.providerApi
            || editedConfiguredModels != s.configuredModels
            || editedActiveServiceSource != s.activeServiceSource
    }

    // Gateway logs
    @Published var gatewayLogs: [String] = []
    @Published var isLoadingLogs = false

    // Collab
    @Published var collabViewModel: CollabViewModel?
    @Published var showCollabPanel = false
    @Published var collabPanelCollapsed = false

    // Budget
    @Published var budgetService = BudgetService()
    @Published var budgetSnapshots: [BudgetSnapshot] = []
    @Published var budgetRules: [BudgetRule] = []
    @Published var isLoadingBudgets = false

    // Diagnostics
    @Published var diagnosticReport: String = ""
    @Published var showDiagnostics = false
    private var logRefreshTimer: Timer?
    private var budgetMonitorTimer: Timer?

    private let _commandExecutor: CommandExecutor
    private var cancellables = Set<AnyCancellable>()

    #if REQUIRE_LOGIN
    // MembershipManager reference for GetClawHub save logic
    weak var membershipManager: MembershipManager?
    #endif
    // Gateway WebSocket client for chat
    @Published var gatewayClient: GatewayClient

    // Maps msgId → runId for active WebSocket chat runs
    private var activeChatRuns: [UUID: String] = [:]

    init(
        openclawService: OpenClawService,
        settings: AppSettingsManager,
        systemEnvironment: SystemEnvironment,
        commandExecutor: CommandExecutor
    ) {
        self.openclawService = openclawService
        self.settings = settings
        self.systemEnvironment = systemEnvironment
        self._commandExecutor = commandExecutor

        // Initialize gateway WebSocket client for chat abort
        self.gatewayClient = GatewayClient(
            port: settings.settings.gatewayPort,
            authToken: settings.settings.gatewayAuthToken,
            credentialsProvider: {
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let configPath = "\(homeDir)/.openclaw/openclaw.json"
                guard let data = FileManager.default.contents(atPath: configPath),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let gateway = dict["gateway"] as? [String: Any] else {
                    return (port: 3000, authToken: "")
                }
                let port = gateway["port"] as? Int ?? 3000
                let token = (gateway["auth"] as? [String: Any])?["token"] as? String ?? ""
                return (port: port, authToken: token)
            }
        )

        // Initialize edited values from real config
        self.editedPort = String(settings.settings.gatewayPort)
        self.editedAuthToken = settings.settings.gatewayAuthToken
        self.editedModelBaseUrl = settings.settings.modelBaseUrl
        self.editedModelApiKey = settings.settings.modelApiKey
        self.editedSelectedProviderKey = settings.settings.selectedProviderKey
        self.editedProviderApi = settings.settings.providerApi
        self.editedConfiguredModels = settings.settings.configuredModels
        self.editedActiveServiceSource = settings.settings.activeServiceSource

        // Load available providers from preset (exclude getclawhub — it has its own section)
        self.availableProviders = presetManager.loadPresets().filter { $0.key != "getclawhub" }

        // If no config file exists, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }

        // Forward nested ObservableObject changes so SwiftUI views re-render
        // (@Published on reference types only fires when the reference is replaced,
        //  not when the inner object's properties change)
        openclawService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Initialize budget rules mirror from BudgetService
        self.budgetRules = budgetService.config.rules

        // Connect gateway WebSocket when service is running
        if openclawService.status == .running {
            gatewayClient.connect()
        }

        // Auto-connect/disconnect gateway WS based on service status
        openclawService.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                if status == .running && !self.gatewayClient.isConnected {
                    self.gatewayClient.connect()
                } else if status != .running {
                    self.gatewayClient.disconnect()
                }
            }
            .store(in: &cancellables)

        // ─── Chat session persistence ───
        // 1. Build the metadata mirror from disk so the sidebar can render
        //    history immediately, before the user ever opens chat.
        rebuildSessionsMirror()
        // 2. For every agent that already has stored sessions, restore the
        //    most-recent one into chatMessagesByAgent so reopening chat shows
        //    the previous conversation rather than an empty state.
        restoreActiveSessionsFromStore()
        // 3. Watch chatMessagesByAgent and persist the in-memory view back to
        //    the active session on disk — debounced so a streamed assistant
        //    reply collapses into one disk write.
        $chatMessagesByAgent
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] dict in
                self?.persistChangedSessions(from: dict)
            }
            .store(in: &cancellables)
    }

    deinit {
        Task { @MainActor in
            openclawService.stopMonitoring()
            gatewayClient.disconnect()
            logRefreshTimer?.invalidate()
            logRefreshTimer = nil
        }
    }

    // MARK: - Public Access to CommandExecutor

    var commandExecutor: CommandExecutor {
        self._commandExecutor
    }

    // Plugins
    @Published var plugins: [PluginInfo] = []
    @Published var isLoadingPlugins = false

    // Channels
    @Published var channels: [ChannelInfo] = []
    @Published var isLoadingChannels = false

    // Weixin QR Login
    @Published var weixinQRImage: NSImage?
    @Published var weixinLoginStatus: WeixinLoginStatus = .idle
    var weixinLoginProcess: Process?

    enum WeixinLoginStatus: Equatable {
        case idle
        case waitingScan
        case success
        case failed(String)
    }

    // Models
    @Published var models: [ModelInfo] = []
    @Published var modelOverview: ModelOverview = ModelOverview()
    @Published var fallbackModels: [String] = []
    @Published var imageFallbackModels: [String] = []
    @Published var isLoadingModels = false

    // Cron Jobs
    @Published var cronJobs: [CronJobInfo] = []
    @Published var isLoadingCronJobs = false

    // Sessions Summary (for Status tab monitoring)
    @Published var sessionsSummary: SessionsSummary?
    @Published var isLoadingSessionsSummary = false

    // MARK: - Sidebar Mode

    enum SidebarMode: String {
        case config = "config"
        case teams = "teams"
        case market = "market"
    }

    @Published var sidebarMode: SidebarMode = .config
    @Published var selectedMarketplaceAgent: MarketplaceAgent?

    // MARK: - Tab Management

    enum DashboardTab: String, CaseIterable, Hashable {
        case chat = "Chat"
        case status = "Status"
        case budget = "Budget"
        case billing = "Billing"
        case persona = "Persona"
        case subAgents = "Multi-Agent"
        case config = "Configuration"
        case skills = "Skills"
        case models = "Models"
        case channels = "Channels"
        case plugins = "Plugins"
        case cron = "Cron"
        case logs = "Logs"

        var icon: String {
            switch self {
            case .chat: return "message.fill"
            case .status: return "chart.bar.fill"
            case .budget: return "dollarsign.gauge.chart.lefthalf.righthalf"
            case .billing: return "creditcard.fill"
            case .persona: return "person.text.rectangle"
            case .subAgents: return "person.3.fill"
            case .config: return "gearshape"
            case .skills: return "bolt.fill"
            case .models: return "cube.fill"
            case .channels: return "bubble.left.and.bubble.right.fill"
            case .plugins: return "puzzlepiece.fill"
            case .cron: return "clock.badge"
            case .logs: return "doc.text.magnifyingglass"
            }
        }
    }

    func selectTab(_ tab: DashboardTab) {
        selectedTab = tab
    }

    // MARK: - Service Control

    func startService() async {
        isPerformingAction = true

        do {
            try await openclawService.start()
            showSuccessMessage("Service started successfully")
        } catch {
            showErrorMessage("Failed to start service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func stopService() async {
        isPerformingAction = true

        do {
            try await openclawService.stop()
            showSuccessMessage("Service stopped successfully")
        } catch {
            showErrorMessage("Failed to stop service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func restartService() async {
        isPerformingAction = true

        do {
            try await openclawService.restart()
            showSuccessMessage("Service restarted successfully")
        } catch {
            showErrorMessage("Failed to restart service: \(error.localizedDescription)")
        }

        isPerformingAction = false
    }

    func refreshStatus() async {
        await openclawService.checkStatus()
    }

    // MARK: - Configuration Management

    /// Sync the edited text fields from in-memory settings (no file I/O).
    /// Safe to call from onAppear — does not trigger @Published on AppSettingsManager.
    func syncEditedFieldsFromSettings() {
        editedPort = String(settings.settings.gatewayPort)
        editedAuthToken = settings.settings.gatewayAuthToken
        editedModelBaseUrl = settings.settings.modelBaseUrl
        editedModelApiKey = settings.settings.modelApiKey
        editedSelectedProviderKey = settings.settings.selectedProviderKey
        editedProviderApi = settings.settings.providerApi
        editedConfiguredModels = settings.settings.configuredModels
        availableProviders = presetManager.loadPresets().filter { $0.key != "getclawhub" }

        // If no config file exists yet, populate from preset defaults
        if editedModelBaseUrl.isEmpty,
           let preset = availableProviders.first(where: { $0.key == editedSelectedProviderKey }) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
        }
    }

    /// Reload from disk and sync fields.
    func loadConfiguration() {
        settings.loadFromFile()
        syncEditedFieldsFromSettings()
    }

    func saveConfiguration() async {
        isPerformingAction = true

        // Validate port
        guard let port = Int(editedPort), port > 0, port < 65536 else {
            showErrorMessage("Invalid port number. Must be between 1 and 65535")
            isPerformingAction = false
            return
        }

        // Update settings in memory
        settings.settings.gatewayPort = port
        settings.settings.gatewayAuthToken = editedAuthToken
        settings.settings.modelBaseUrl = editedModelBaseUrl
        settings.settings.modelApiKey = editedModelApiKey
        settings.settings.selectedProviderKey = editedSelectedProviderKey
        settings.settings.providerApi = editedProviderApi
        settings.settings.configuredModels = editedConfiguredModels
        settings.settings.activeServiceSource = editedActiveServiceSource

        // Write to ~/.openclaw/openclaw.json
        if settings.saveToFile() {
            // If GetClawHub is active and user edited the API key, update getclawhub provider
            if editedActiveServiceSource == "getclawhub" && !editedGetClawHubApiKey.isEmpty {
                let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
                let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
                #if REQUIRE_LOGIN
                // Filter by membership allowed models if available
                let models: [PresetModel]
                if let allowedModels = membershipManager?.membership?.models, !allowedModels.isEmpty {
                    let allowedSet = Set(allowedModels)
                    models = allPresetModels.filter { allowedSet.contains($0.id) }
                } else {
                    models = allPresetModels
                }
                #else
                let models = allPresetModels
                #endif
                AppSettingsManager.writeGetClawHubProvider(apiKey: editedGetClawHubApiKey, models: models, baseUrl: baseUrl)
            }
            showSuccessMessage("Configuration saved to openclaw.json")
        } else {
            showErrorMessage("Failed to save configuration file")
        }

        isPerformingAction = false
    }

    func saveAndRestartService() async {
        await saveConfiguration()

        if openclawService.status == .running {
            await restartService()
        }
    }

    func resetConfiguration() {
        loadConfiguration()
    }

    func openConfigFile() {
        settings.openConfigFile()
    }

    // MARK: - Provider Switching

    /// Request to switch provider — shows confirmation alert
    func requestSwitchProvider(to key: String) {
        if key == editedSelectedProviderKey { return }
        pendingProviderKey = key
        showProviderSwitchConfirm = true
    }

    /// Confirm provider switch — fills baseUrl, api, models from preset
    func confirmSwitchProvider() {
        let key = pendingProviderKey
        editedSelectedProviderKey = key
        if let preset = presetManager.findProvider(byKey: key) {
            editedModelBaseUrl = preset.baseUrl
            editedProviderApi = preset.api
            editedConfiguredModels = preset.models
            editedModelApiKey = ""
        }
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    /// Cancel provider switch
    func cancelSwitchProvider() {
        pendingProviderKey = ""
        showProviderSwitchConfirm = false
    }

    // MARK: - Model List Editing

    /// Add a model to the edited models list
    func addModel(_ model: PresetModel) {
        editedConfiguredModels.append(model)
    }

    /// Remove a model at the given index
    func removeModel(at index: Int) {
        guard index >= 0, index < editedConfiguredModels.count else { return }
        editedConfiguredModels.remove(at: index)
    }

    /// Open the providers preset file in TextEdit
    func openProviderPresetFile() {
        presetManager.openPresetFile()
    }

    // MARK: - Logs Management

    /// Load gateway logs from file
    func loadGatewayLogs() async {
        isLoadingLogs = true
        gatewayLogs = await openclawService.readGatewayLogs(lines: 200)
        isLoadingLogs = false
    }

    /// Start auto-refreshing logs every few seconds
    func startLogRefresh(interval: TimeInterval = 3.0) {
        stopLogRefresh()
        Task {
            await loadGatewayLogs()
        }
        logRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadGatewayLogs()
            }
        }
    }

    /// Stop auto-refreshing logs
    func stopLogRefresh() {
        logRefreshTimer?.invalidate()
        logRefreshTimer = nil
    }

    func clearLogs() {
        openclawService.clearLogs()
        showSuccessMessage("Logs cleared")
    }

    func exportLogs() -> String {
        return openclawService.getLogsString()
    }

    func openLogFile() {
        openclawService.openLogs()
    }

    // MARK: - Dashboard Actions

    func openDashboard() {
        openclawService.openDashboard(authToken: settings.settings.gatewayAuthToken)
    }

    // MARK: - Collab

    func getOrCreateCollabViewModel() -> CollabViewModel {
        if let existing = collabViewModel {
            return existing
        }
        let vm = CollabViewModel(dashboardViewModel: self)
        collabViewModel = vm
        return vm
    }

    func runDiagnostics() async {
        isPerformingAction = true

        let output = await openclawService.runDoctor()
        diagnosticReport = output
        showDiagnostics = true

        isPerformingAction = false
    }

    // MARK: - Quick Actions

    func performQuickAction(_ action: QuickAction) async {
        switch action {
        case .start:
            await startService()
        case .stop:
            await stopService()
        case .restart:
            await restartService()
        case .openDashboard:
            openDashboard()
        case .viewLogs:
            openLogFile()
        case .runDiagnostics:
            await runDiagnostics()
        }
    }

    enum QuickAction {
        case start
        case stop
        case restart
        case openDashboard
        case viewLogs
        case runDiagnostics
    }

    // MARK: - UI Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true

        // Auto-hide after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            showError = false
        }
    }

    private func showSuccessMessage(_ message: String) {
        successMessage = message
        showSuccess = true

        // Auto-hide after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSuccess = false
        }
    }

    // MARK: - Skills Management

    @Published var skills: [SkillInfo] = []
    @Published var skillsSummary: SkillsSummary = SkillsSummary()
    @Published var isLoadingSkills = false
    @Published var selectedSkillDetail: SkillDetailInfo?
    @Published var isLoadingSkillDetail = false

    /// Load skills list by running `openclaw skills list`
    func loadSkills() async {
        isLoadingSkills = true
        let output = await openclawService.runCommand(
            "openclaw skills list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        let (parsed, summary) = Self.parseSkillsList(output: output)
        skills = parsed.sorted { a, b in
            if a.status != b.status {
                return a.status == .ready
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        skillsSummary = summary
        isLoadingSkills = false
    }

    /// Parse `openclaw skills list` table output.
    /// Table format: │ Status │ Skill │ Description │ Source │
    static func parseSkillsList(output: String?) -> ([SkillInfo], SkillsSummary) {
        guard let output = output else { return ([], SkillsSummary()) }

        var results: [SkillInfo] = []
        var summary = SkillsSummary()

        // Parse header "Skills (35/81 ready)"
        for line in output.components(separatedBy: .newlines) {
            if line.contains("Skills (") && line.contains("ready)") {
                if let range = line.range(of: "\\((\\d+)/(\\d+)\\s+ready\\)", options: .regularExpression) {
                    let match = String(line[range])
                    let nums = match.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
                    if nums.count >= 2 {
                        summary.ready = Int(nums[0]) ?? 0
                        summary.total = Int(nums[1]) ?? 0
                    }
                }
                break
            }
        }

        // Current row accumulator (for multiline cells)
        var currentStatus: String?
        var currentName: String?
        var currentDesc: String?
        var currentSource: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip border lines and non-table lines
            guard trimmed.hasPrefix("│") else { continue }

            // Skip header row
            if trimmed.contains("Status") && trimmed.contains("Skill") && trimmed.contains("Description") && trimmed.contains("Source") {
                continue
            }

            // Split by │ and trim
            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // cells[0]="" cells[1]=Status cells[2]=Skill cells[3]=Description cells[4]=Source
            guard cells.count >= 5 else { continue }

            let status = cells[1]
            // Strip leading emoji from skill name (e.g. "📦 feishu-doc" -> "feishu-doc")
            let skill = cells[2].drop(while: { !$0.isASCII })
                .trimmingCharacters(in: .whitespaces)
            let desc = cells[3]
            let source = cells[4]

            // Check if this is a new row (status column is non-empty)
            if !status.isEmpty {
                // Flush previous row
                if let prevName = currentName, !prevName.isEmpty {
                    results.append(SkillInfo(
                        name: prevName,
                        status: currentStatus?.contains("ready") == true ? .ready : .missing,
                        description: currentDesc ?? "",
                        source: currentSource ?? ""
                    ))
                }
                currentStatus = status
                currentName = skill
                currentDesc = desc
                currentSource = source
            } else {
                // Continuation line — append description
                if !skill.isEmpty {
                    currentName = (currentName ?? "") + skill
                }
                if !desc.isEmpty {
                    currentDesc = ((currentDesc ?? "") + " " + desc).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Flush last row
        if let prevName = currentName, !prevName.isEmpty {
            results.append(SkillInfo(
                name: prevName,
                status: currentStatus?.contains("ready") == true ? .ready : .missing,
                description: currentDesc ?? "",
                source: currentSource ?? ""
            ))
        }

        return (results, summary)
    }

    /// Load detail info for a specific skill
    func loadSkillDetail(_ skillName: String) async {
        isLoadingSkillDetail = true
        let output = await openclawService.runCommand(
            "openclaw skills info '\(skillName)' 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        selectedSkillDetail = Self.parseSkillInfo(output: output, skillName: skillName)
        isLoadingSkillDetail = false
    }

    /// Parse `openclaw skills info <name>` output
    static func parseSkillInfo(output: String?, skillName: String) -> SkillDetailInfo? {
        guard let output = output else { return nil }

        var status = ""
        var description = ""
        var source = ""
        var path = ""
        var requirements: [String] = []
        var isReady = false

        var inRequirements = false
        var inDescription = true

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip noise lines
            if trimmed.hasPrefix("[agent-scope]") || trimmed.hasPrefix("Config warnings:")
                || trimmed.hasPrefix("- plugins.") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("│") || trimmed.hasPrefix("◇") || trimmed.hasPrefix("├") { continue }

            // Status line: "📦 brainstorming ✓ Ready" or "🎮 discord ✗ Missing requirements"
            if trimmed.contains("Ready") || trimmed.contains("Missing") {
                if trimmed.contains("Ready") {
                    status = "Ready"
                    isReady = true
                } else {
                    status = "Missing requirements"
                    isReady = false
                }
                inDescription = true
                continue
            }

            if trimmed.hasPrefix("Details:") {
                inDescription = false
                inRequirements = false
                continue
            }

            if trimmed.hasPrefix("Requirements:") {
                inDescription = false
                inRequirements = true
                continue
            }

            if trimmed.hasPrefix("Tip:") {
                break
            }

            if trimmed.hasPrefix("Source:") {
                source = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed.hasPrefix("Path:") {
                path = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if inRequirements {
                if trimmed.hasPrefix("Config:") || trimmed.hasPrefix("Bins:") {
                    requirements.append(trimmed)
                }
                continue
            }

            if inDescription && !trimmed.hasPrefix("Details:") && !trimmed.hasPrefix("Source:")
                && !trimmed.hasPrefix("Path:") {
                if !description.isEmpty { description += " " }
                description += trimmed
            }
        }

        return SkillDetailInfo(
            name: skillName,
            status: status,
            isReady: isReady,
            description: description,
            source: source,
            path: path,
            requirements: requirements
        )
    }

    // MARK: - Chat

    @Published var chatMessagesByAgent: [String: [ChatMessage]] = [:]
    /// Computed view into the currently selected agent's messages.
    var chatMessages: [ChatMessage] {
        get { chatMessagesByAgent[selectedAgentId] ?? [] }
        set { chatMessagesByAgent[selectedAgentId] = newValue }
    }

    // MARK: - Chat Session Persistence
    //
    // M1 of the chat-history feature: persist every per-agent conversation to
    // disk so it survives app restart, and surface session metadata to the
    // sidebar (M2 will render it). The "active" session is always the most
    // recent one per agent — multi-session UX comes in later milestones.
    //
    // chatMessagesByAgent stays the live source of truth for the chat view;
    // we mirror its changes (debounced) into the active ChatSession on disk.
    let chatSessionStore = ChatSessionStore()
    /// Per-agent metadata of every session, sorted (pinned first, then newest).
    /// Filtered to exclude archived sessions; archived ones live in the store.
    @Published var sessionsByAgent: [String: [ChatSessionMetadata]] = [:]
    /// The currently visible session for each agent. Switching this swaps
    /// chatMessagesByAgent[agentId] to the loaded session's messages.
    @Published var selectedSessionIdByAgent: [String: UUID] = [:]

    /// Refresh `sessionsByAgent` from the store's index. Pinned-first then
    /// newest-first within each agent. Archived sessions are excluded so the
    /// sidebar list stays clean; the underlying file remains on disk.
    func rebuildSessionsMirror() {
        var grouped: [String: [ChatSessionMetadata]] = [:]
        for meta in chatSessionStore.index where !meta.isArchived {
            grouped[meta.agentId, default: []].append(meta)
        }
        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
        sessionsByAgent = grouped
    }

    /// On launch, for every agent with stored history, load the newest session
    /// and seed chatMessagesByAgent with its messages. Without this, the chat
    /// view would render empty until the user types something even though
    /// their previous conversation is sitting on disk.
    private func restoreActiveSessionsFromStore() {
        for (agentId, metas) in sessionsByAgent {
            guard let mostRecent = metas.first,
                  let session = chatSessionStore.loadSession(id: mostRecent.id) else {
                continue
            }
            selectedSessionIdByAgent[agentId] = session.id
            chatMessagesByAgent[agentId] = session.messages
        }
    }

    /// Mirror every agent's in-memory messages back to its active session on
    /// disk. Called from a debounced sink, so token-by-token streaming
    /// produces one write per ~500ms idle window. Lazily creates a session
    /// the first time an agent gets a message.
    private func persistChangedSessions(from dict: [String: [ChatMessage]]) {
        for (agentId, messages) in dict where !messages.isEmpty {
            let sessionId = ensureActiveSessionId(forAgent: agentId, seedMessages: messages)
            // Build the session we want on disk — start from the loaded copy
            // (preserves pin/archive state) and overwrite mutable fields.
            var session = chatSessionStore.loadSession(id: sessionId)
                ?? ChatSession(id: sessionId, agentId: agentId, messages: messages)

            // Cheap equality check: same count + same trailing message id ⇒
            // nothing new to persist (e.g. unrelated agent's dict mutation
            // re-fired the publisher).
            if session.messages.count == messages.count,
               session.messages.last?.id == messages.last?.id,
               !session.title.isEmpty {
                continue
            }

            session.messages = messages
            session.updatedAt = Date()
            // Auto-derive title once, only while still on the placeholder.
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: messages)
            }
            chatSessionStore.saveSessionDebounced(session)
        }
        // Even if no messages changed, the index may have new metadata
        // (titles, message counts) — rebuild the published mirror.
        rebuildSessionsMirror()
    }

    // MARK: - Session UI Actions

    /// Switch the current agent's active session to `sessionId`. Flushes the
    /// in-memory thread of the previous session to disk first so partial
    /// state isn't lost when the user clicks back.
    func switchSession(to sessionId: UUID) {
        let agentId = selectedAgentId
        flushActiveSession(forAgent: agentId)
        guard let target = chatSessionStore.loadSession(id: sessionId) else { return }
        selectedSessionIdByAgent[agentId] = sessionId
        chatMessagesByAgent[agentId] = target.messages
        rebuildSessionsMirror()
    }

    /// Mint a fresh empty session for the current agent and switch to it.
    /// Used by the "+ New Session" sidebar button.
    @discardableResult
    func createNewSession() -> UUID {
        let agentId = selectedAgentId
        flushActiveSession(forAgent: agentId)
        let new = ChatSession(agentId: agentId)
        chatSessionStore.saveSession(new)
        selectedSessionIdByAgent[agentId] = new.id
        chatMessagesByAgent[agentId] = []
        rebuildSessionsMirror()
        return new.id
    }

    /// Cancel any pending debounced write for the agent's current session and
    /// commit its in-memory messages to disk synchronously. Safe to call
    /// when there is no active session — it's a no-op.
    private func flushActiveSession(forAgent agentId: String) {
        guard let sid = selectedSessionIdByAgent[agentId] else { return }
        let messages = chatMessagesByAgent[agentId] ?? []
        var current = chatSessionStore.loadSession(id: sid)
            ?? ChatSession(id: sid, agentId: agentId, messages: messages)
        current.messages = messages
        current.updatedAt = Date()
        if current.title == ChatSession.defaultTitle {
            current.title = ChatSession.deriveTitle(from: messages)
        }
        chatSessionStore.flush(id: sid, current: current)
    }

    /// Return the active session id for `agentId`, creating one if needed.
    /// `seedMessages` is the current in-memory thread; used to derive a title
    /// if we have to mint a fresh session.
    @discardableResult
    private func ensureActiveSessionId(forAgent agentId: String, seedMessages: [ChatMessage] = []) -> UUID {
        if let existing = selectedSessionIdByAgent[agentId] {
            return existing
        }
        // Reuse the newest non-archived session for this agent if one exists
        // (e.g. the picker pointed at a known agent but selection wasn't seeded).
        if let recent = chatSessionStore.sessions(forAgent: agentId).first {
            selectedSessionIdByAgent[agentId] = recent.id
            return recent.id
        }
        // Mint a new session and persist it immediately so subsequent
        // lookups see it in the index.
        let title = ChatSession.deriveTitle(from: seedMessages)
        let new = ChatSession(agentId: agentId, title: title, messages: seedMessages)
        chatSessionStore.saveSession(new)
        selectedSessionIdByAgent[agentId] = new.id
        return new.id
    }
    @Published var isSendingMessage = false  // true when any foreground task is active
    @Published var foregroundTaskIds: Set<UUID> = []  // message IDs of foreground (blocking) tasks
    @Published var backgroundTaskIds: Set<UUID> = []  // message IDs of background tasks
    var taskAgentMap: [UUID: String] = [:]  // msgId → agentId for per-agent tracking

    /// Whether the currently selected agent has a foreground task running.
    var isCurrentAgentSending: Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == selectedAgentId })
    }

    /// Check if a specific agent has a foreground task running.
    func isAgentExecuting(_ agentId: String) -> Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == agentId })
    }
    @Published var selectedAgentId: String = "main"
    @Published var availableAgents: [AgentOption] = [AgentOption(id: "main", name: "main", emoji: "🤖", description: "", model: "", division: "")]

    // Agent Settings Panel state
    @Published var agentSettingsOpen: Bool = false
    @Published var selectedAgentDetail: SubAgentInfo?
    @Published var availableModelsForSettings: [ModelOption] = []

    /// Internal agents managed by the app, hidden from user-facing lists.
    static let internalAgentIds: Set<String> = ["help-assistant"]

    func loadAvailableAgents() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        var agents: [AgentOption] = []

        let previousSelectedAgentId = selectedAgentId

        // Ensure commander exists in openclaw.json before loading
        Self.ensureCommanderInConfig(configPath: configPath, baseDir: baseDir)

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any],
           let agentList = agentsSection["list"] as? [[String: Any]] {
            for entry in agentList {
                guard let agentId = entry["id"] as? String else { continue }

                // Skip internal agents (commander, help-assistant) from user-facing lists
                if Self.internalAgentIds.contains(agentId) { continue }

                // Determine workspace path for this agent
                let workspace: String
                if let ws = entry["workspace"] as? String {
                    workspace = (ws as NSString).expandingTildeInPath
                } else if agentId == "main" {
                    workspace = (baseDir as NSString).appendingPathComponent("workspace")
                } else {
                    workspace = (baseDir as NSString).appendingPathComponent("workspace-\(agentId)")
                }

                // Read IDENTITY.md and parse emoji/name from file first, fall back to config
                let identityPath = (workspace as NSString).appendingPathComponent("IDENTITY.md")
                let identityContent = (try? String(contentsOfFile: identityPath, encoding: .utf8)) ?? ""
                let parsed = PersonaViewModel.parseIdentity(identityContent)

                let identity = entry["identity"] as? [String: Any]

                let name: String = {
                    if !parsed.name.isEmpty { return parsed.name }
                    if let n = identity?["name"] as? String, !n.isEmpty { return n }
                    return entry["name"] as? String ?? agentId
                }()

                let emoji: String = {
                    if !parsed.emoji.isEmpty { return parsed.emoji }
                    return identity?["emoji"] as? String ?? "🤖"
                }()

                // Extract agent description from IDENTITY.md (text after ---) and SOUL.md
                let agentDescription = Self.extractAgentDescription(workspace: workspace, identityContent: identityContent)

                let model = entry["model"] as? String ?? ""

                // Resolve division: from IDENTITY.md first, then marketplace catalog, then "Custom"
                let division: String = {
                    if !parsed.division.isEmpty { return parsed.division }
                    if let marketplaceAgent = MarketplaceCatalog.shared.agents.first(where: { $0.id == agentId }) {
                        return marketplaceAgent.division
                    }
                    if agentId == "main" || agentId == "commander" { return "" }
                    return "Custom"
                }()

                agents.append(AgentOption(id: agentId, name: name, emoji: emoji, description: agentDescription, model: model, division: division))
            }
        }

        // Ensure "main" is always present
        if !agents.contains(where: { $0.id == "main" }) {
            // Even for main fallback, try reading from IDENTITY.md
            let mainWorkspace = (baseDir as NSString).appendingPathComponent("workspace")
            let mainIdentityPath = (mainWorkspace as NSString).appendingPathComponent("IDENTITY.md")
            let mainContent = (try? String(contentsOfFile: mainIdentityPath, encoding: .utf8)) ?? ""
            let mainParsed = PersonaViewModel.parseIdentity(mainContent)
            let mainName = mainParsed.name.isEmpty ? "main" : mainParsed.name
            let mainEmoji = mainParsed.emoji.isEmpty ? "🤖" : mainParsed.emoji
            let mainDesc = Self.extractAgentDescription(workspace: mainWorkspace, identityContent: mainContent)
            agents.insert(AgentOption(id: "main", name: mainName, emoji: mainEmoji, description: mainDesc, model: "", division: ""), at: 0)
        }

        availableAgents = agents

        // Only reset selection if current agent no longer exists and it was not explicitly set by user
        if !agents.contains(where: { $0.id == previousSelectedAgentId }) {
            selectedAgentId = "main"
        } else {
            // Restore the previous selection to preserve chat history
            selectedAgentId = previousSelectedAgentId
        }
    }

    /// Ensure commander agent entry exists in openclaw.json.
    /// Called early in loadAvailableAgents() so commander is always visible in the UI.
    private static func ensureCommanderInConfig(configPath: String, baseDir: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var agentList = agentsSection["list"] as? [[String: Any]] ?? []

        // Already exists — nothing to do
        if agentList.contains(where: { ($0["id"] as? String) == "commander" }) { return }

        let agentDir = (baseDir as NSString).appendingPathComponent("agents/commander/agent")
        let workspaceDir = (baseDir as NSString).appendingPathComponent("workspace-commander")

        // Create directories
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        // Write IDENTITY.md
        let identityContent = """
        # IDENTITY.md - Who Am I?

        - **Name:** Commander
        - **Creature:** AI Task Orchestrator
        - **Vibe:** Precise, structured, efficient
        - **Emoji:** 🎯
        """
        let identityPath = (workspaceDir as NSString).appendingPathComponent("IDENTITY.md")
        try? identityContent.write(toFile: identityPath, atomically: true, encoding: .utf8)

        // Add commander entry to config
        let commanderEntry: [String: Any] = [
            "id": "commander",
            "name": "commander",
            "default": false,
            "identity": [
                "name": "Commander",
                "emoji": "🎯"
            ],
            "agentDir": agentDir,
            "workspace": workspaceDir
        ]
        agentList.append(commanderEntry)
        agentsSection["list"] = agentList
        json["agents"] = agentsSection

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    /// Extract a concise agent description from IDENTITY.md (free text after ---),
    /// SOUL.md ("## You Are" or "## 🧠 Your Identity & Memory" Role line),
    /// and AGENTS.md ("## When to Use" section).
    static func extractAgentDescription(workspace: String, identityContent: String) -> String {
        var parts: [String] = []

        // 1. IDENTITY.md: text after the first "---" separator
        if let separatorRange = identityContent.range(of: "\n---") {
            let afterSeparator = String(identityContent[separatorRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterSeparator.isEmpty && !afterSeparator.hasPrefix("This isn't just metadata") && !afterSeparator.hasPrefix("_Fill") {
                parts.append(afterSeparator)
            }
        }

        // 2. SOUL.md: extract "## You Are" section content
        let soulPath = (workspace as NSString).appendingPathComponent("SOUL.md")
        if let soulContent = try? String(contentsOfFile: soulPath, encoding: .utf8) {
            // Try "## You Are" first (user-created agents)
            if let youAreRange = soulContent.range(of: "## You Are") {
                let afterYouAre = String(soulContent[youAreRange.upperBound...])
                let sectionContent: String
                if let nextHeading = afterYouAre.range(of: "\n## ") {
                    sectionContent = String(afterYouAre[..<nextHeading.lowerBound])
                } else {
                    sectionContent = afterYouAre
                }
                let trimmed = sectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            }
            // Fallback: "## 🧠 Your Identity & Memory" — extract Role line (marketplace agents)
            else if parts.isEmpty, let identityRange = soulContent.range(of: "Identity", options: .caseInsensitive) {
                let afterHeader = String(soulContent[identityRange.upperBound...])
                let sectionEnd = afterHeader.range(of: "\n## ")?.lowerBound ?? afterHeader.endIndex
                let section = String(afterHeader[..<sectionEnd])

                // Extract "- **Role**: ..." line
                for line in section.components(separatedBy: "\n") {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.lowercased().contains("**role**") {
                        let roleText = trimmedLine
                            .replacingOccurrences(of: "- **Role**:", with: "")
                            .replacingOccurrences(of: "- **Role:**", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !roleText.isEmpty {
                            parts.append(roleText)
                        }
                        break
                    }
                }
            }
        }

        // 3. AGENTS.md: extract "## When to Use" section
        let agentsPath = (workspace as NSString).appendingPathComponent("AGENTS.md")
        if let agentsContent = try? String(contentsOfFile: agentsPath, encoding: .utf8) {
            if let whenRange = agentsContent.range(of: "## When to Use") {
                let afterWhen = String(agentsContent[whenRange.upperBound...])
                let sectionContent: String
                if let nextHeading = afterWhen.range(of: "\n## ") {
                    sectionContent = String(afterWhen[..<nextHeading.lowerBound])
                } else {
                    sectionContent = afterWhen
                }
                let trimmed = sectionContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append("When: \(trimmed)")
                }
            }
        }

        // Combine and truncate to keep prompt compact
        let combined = parts.joined(separator: " | ")
        if combined.count > 300 {
            return String(combined.prefix(300)) + "..."
        }
        return combined
    }

    // MARK: - Chat Helpers

    private func sessionKeyForAgent(_ agentId: String) -> String {
        return "agent:\(agentId):main"
    }

    /// Extensions that the gateway accepts as image attachments (via base64 in `content` field).
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    /// Process attachments: images → base64 attachments array; other files → pass file path in message.
    /// Returns (imageAttachments, textToAppend).
    private func processAttachments(_ urls: [URL]) -> (attachments: [[String: Any]], inlineText: String) {
        var imageAttachments: [[String: Any]] = []
        var textParts: [String] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent

            // Image files → send as base64 attachment (gateway only accepts image/*)
            if Self.imageExtensions.contains(ext) {
                guard let data = try? Data(contentsOf: url) else {
                    os_log(.error, "processAttachments: failed to read image file: %{public}@", fileName)
                    continue
                }
                let base64 = data.base64EncodedString()
                os_log(.info, "processAttachments: image '%{public}@' ext=%{public}@ base64Len=%d", fileName, ext, base64.count)
                let mimeType: String
                switch ext {
                case "png": mimeType = "image/png"
                case "jpg", "jpeg": mimeType = "image/jpeg"
                case "gif": mimeType = "image/gif"
                case "webp": mimeType = "image/webp"
                default: mimeType = "image/png"
                }
                imageAttachments.append([
                    "type": "image",
                    "mimeType": mimeType,
                    "content": base64
                ])
                // Also pass the file path in the message so the AI knows which image file this is
                textParts.append("Attached image file: \(url.path)")
                continue
            }

            // Non-image files → pass local file path so the AI agent can read it directly
            os_log(.info, "processAttachments: non-image '%{public}@' ext=%{public}@ → passing path", fileName, ext)
            textParts.append("Attachment file: \(url.path)")
        }

        let inlineText = textParts.isEmpty ? "" : "\n\n" + textParts.joined(separator: "\n\n")
        return (imageAttachments, inlineText)
    }

    private func updateMessage(msgId: UUID, content: String, status: ChatMessage.TaskStatus, agentId: String, agentEmoji: String?) {
        if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByAgent[agentId] ?? []
            messages[idx] = ChatMessage(
                role: .assistant, content: content,
                agentId: agentId, agentEmoji: agentEmoji,
                taskStatus: status, id: msgId
            )
            chatMessagesByAgent[agentId] = messages
            logChat("UPDATE_MSG: agent=\(agentId), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
        } else {
            logChat("UPDATE_FAILED: agent=\(agentId), msgId=\(msgId.uuidString.prefix(8)) NOT FOUND!")
        }
    }

    private func appendBackgroundNotification(agentId: String, agentEmoji: String?, completed: Bool, msgId: UUID) {
        let agentName = availableAgents.first(where: { $0.id == agentId })?.name ?? agentId
        if completed {
            let notifyContent = String(format: String(localized: "✅ Background task from **%@** completed", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji, scrollTargetId: msgId)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        } else {
            let notifyContent = String(format: String(localized: "⚠️ Background task from **%@** timed out", bundle: LanguageManager.shared.localizedBundle), agentName)
            let notifyMsg = ChatMessage(role: .assistant, content: notifyContent, agentId: agentId, agentEmoji: agentEmoji)
            chatMessagesByAgent[agentId, default: []].append(notifyMsg)
        }
    }

    func sendChatMessage(_ text: String, attachments: [URL] = []) async {
        // Route to commander only when the user is on the commander tab
        if let collabVM = collabViewModel, collabVM.isRunning,
           selectedAgentId == "commander",
           !text.hasPrefix("/") {
            let currentAgent = selectedAgentId
            let userMessage = ChatMessage(role: .user, content: text)
            chatMessagesByAgent[currentAgent, default: []].append(userMessage)
            isSendingMessage = true
            let reply = await collabVM.handleUserMessage(text)
            let noReply = String(localized: "No response from AI.", bundle: LanguageManager.shared.localizedBundle)
            chatMessagesByAgent[currentAgent, default: []].append(ChatMessage(role: .assistant, content: reply ?? noReply, agentId: "commander", agentEmoji: "🎯"))
            isSendingMessage = false
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
        let currentAgentId = selectedAgentId
        chatMessagesByAgent[currentAgentId, default: []].append(userMessage)
        logChat("USER_MSG: agent=\(currentAgentId), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        let currentAgentEmoji = availableAgents.first(where: { $0.id == currentAgentId })?.emoji
        let sessionKey = sessionKeyForAgent(currentAgentId)

        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessagesByAgent[currentAgentId, default: []].append(placeholderMsg)
        logChat("PLACEHOLDER: agent=\(currentAgentId), msgId=\(msgId.uuidString.prefix(8)), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        // Track as foreground task
        foregroundTaskIds.insert(msgId)
        taskAgentMap[msgId] = currentAgentId
        isSendingMessage = true

        // Check gateway connection
        guard gatewayClient.isConnected else {
            let errorMsg = String(localized: "Gateway is not connected. Please check the service status.", bundle: LanguageManager.shared.localizedBundle)
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            foregroundTaskIds.remove(msgId)
            taskAgentMap.removeValue(forKey: msgId)
            isSendingMessage = !foregroundTaskIds.isEmpty
            return
        }

        // Process attachments: images → base64 attachments; text files → inline in message
        let processed = processAttachments(attachments)
        let finalMessage = text + processed.inlineText

        // Subscribe to events BEFORE sending to avoid race condition
        let subscriberId = msgId.uuidString
        let eventStream = gatewayClient.subscribeToEvents(subscriberId: subscriberId)

        // Send the message
        let runId = await gatewayClient.chatSend(
            sessionKey: sessionKey,
            message: finalMessage,
            attachments: processed.attachments.isEmpty ? nil : processed.attachments
        )

        guard let runId = runId else {
            let errorMsg = String(localized: "Failed to send message. Please try again.", bundle: LanguageManager.shared.localizedBundle)
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            foregroundTaskIds.remove(msgId)
            taskAgentMap.removeValue(forKey: msgId)
            isSendingMessage = !foregroundTaskIds.isEmpty
            return
        }

        activeChatRuns[msgId] = runId
        chatLog.info("chat.send ok: runId=\(runId), subscriberId=\(subscriberId), bgTasks=\(self.backgroundTaskIds.count)")

        // Inactivity timeout: only triggers when the WebSocket connection itself goes silent.
        // Gateway broadcasts tick/heartbeat events regularly, so as long as the connection
        // is alive, lastMessageReceivedAt keeps updating — even when the agent is busy
        // running tools with no chat output.
        let inactivityLimit: TimeInterval = 3600  // 60 min with zero WebSocket messages → dead connection
        let timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // check every 10s
                guard let self = self, !Task.isCancelled else { return }
                // Use the gateway-level timestamp: ANY WebSocket message (tick, chat, heartbeat…)
                // proves the connection is alive, so only timeout if *nothing* arrived.
                let elapsed = Date().timeIntervalSince(self.gatewayClient.lastMessageReceivedAt)
                if elapsed >= inactivityLimit {
                    // No WebSocket messages at all for inactivityLimit — connection is dead
                    if self.activeChatRuns[msgId] != nil {
                        self.gatewayClient.unsubscribe(subscriberId: subscriberId)
                        let timeoutMsg = String(localized: "The task timed out and has been terminated. You can try again or switch to another agent.", bundle: LanguageManager.shared.localizedBundle)
                        await MainActor.run {
                            if let idx = self.chatMessagesByAgent[currentAgentId]?.firstIndex(where: { $0.id == msgId }) {
                                let msg = self.chatMessagesByAgent[currentAgentId]![idx]
                                let content = msg.content.isEmpty
                                    ? timeoutMsg
                                    : msg.content + "\n\n---\n> ⚠️ " + timeoutMsg
                                self.updateMessage(msgId: msgId, content: content, status: .timedOut, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                            }
                            self.activeChatRuns.removeValue(forKey: msgId)
                            self.foregroundTaskIds.remove(msgId)
                            self.backgroundTaskIds.remove(msgId)
                            self.taskAgentMap.removeValue(forKey: msgId)
                            self.isSendingMessage = !self.foregroundTaskIds.isEmpty
                        }
                    }
                    return
                }
            }
        }

        // Guarantee cleanup: no matter how the stream loop exits, reset state
        defer {
            timeoutTask.cancel()
            gatewayClient.unsubscribe(subscriberId: subscriberId)
            // Cleanup must happen on MainActor since these are @Published properties
            Task { @MainActor in
                self.activeChatRuns.removeValue(forKey: msgId)
                self.foregroundTaskIds.remove(msgId)
                self.backgroundTaskIds.remove(msgId)
                self.taskAgentMap.removeValue(forKey: msgId)
                self.isSendingMessage = !self.foregroundTaskIds.isEmpty
            }
        }

        // Stream events
        var accumulatedText = ""
        var receivedTerminalEvent = false
        var emptyFinalCount = 0
        // Throttle message updates to prevent CPU 100% during fast streaming
        var lastUpdateTime = Date()
        let updateThrottleInterval: TimeInterval = 0.1  // Update at most every 100ms
        streamLoop: for await event in eventStream {

            switch event {
            case .delta(let eventRunId, _, let text):
                guard eventRunId == runId else { continue }
                // Skip empty deltas (e.g. tool_use blocks with no text content)
                guard !text.isEmpty else {
                    chatLog.debug("chat delta: EMPTY text skipped, runId=\(eventRunId)")
                    continue
                }
                chatLog.debug("chat delta: runId=\(eventRunId), textLen=\(text.count)")
                // Gateway sends full accumulated text in each delta, so use replacement
                accumulatedText = text
                // A real delta arrived — reset the premature-final counter
                emptyFinalCount = 0

                // Only update UI if enough time has passed (throttle to prevent CPU 100%)
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval {
                    lastUpdateTime = now
                    // Only update if not already in a terminal state
                    if let idx = chatMessagesByAgent[currentAgentId]?.firstIndex(where: { $0.id == msgId }),
                       chatMessagesByAgent[currentAgentId]![idx].taskStatus != .cancelled {
                        updateMessage(msgId: msgId, content: accumulatedText, status: chatMessagesByAgent[currentAgentId]![idx].taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                    }
                }

            case .final_(let eventRunId, let eventSessionKey, let text):
                guard eventRunId == runId else { continue }
                chatLog.info("chat final: runId=\(eventRunId), textLen=\(text.count), accumulatedLen=\(accumulatedText.count)")
                var finalText = text.isEmpty ? accumulatedText : text
                // Fallback: when gateway final has no content (e.g. tool-heavy responses where
                // stripInlineDirectiveTagsForDisplay filtered all text), fetch from chat history
                if finalText.isEmpty {
                    chatLog.info("chat final empty — fetching chat.history as fallback")
                    if let historyText = await gatewayClient.fetchLastAssistantMessage(sessionKey: eventSessionKey) {
                        chatLog.info("chat.history fallback: got \(historyText.count) chars")
                        finalText = historyText
                    }
                }
                // If still no content, the gateway may have sent a premature final
                // while the task is still running (e.g. intermediate sub-run ended).
                // Skip the first empty final, but accept on the second — to avoid
                // background tasks getting stuck in "running" state forever.
                if finalText.isEmpty {
                    emptyFinalCount += 1
                    if emptyFinalCount < 2 {
                        chatLog.warning("chat final has no content — ignoring premature final #\(emptyFinalCount), continuing to wait")
                        continue
                    }
                    chatLog.warning("chat final has no content — accepting after \(emptyFinalCount) empty finals")
                    let doneMsg = String(localized: "Task completed.", bundle: LanguageManager.shared.localizedBundle)
                    finalText = accumulatedText.isEmpty ? doneMsg : accumulatedText
                }
                receivedTerminalEvent = true
                let wasBackground = backgroundTaskIds.contains(msgId)
                updateMessage(msgId: msgId, content: finalText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                if wasBackground {
                    appendBackgroundNotification(agentId: currentAgentId, agentEmoji: currentAgentEmoji, completed: true, msgId: msgId)
                }
                break streamLoop

            case .aborted(let eventRunId, _):
                guard eventRunId == runId else { continue }
                receivedTerminalEvent = true
                if let idx = chatMessagesByAgent[currentAgentId]?.firstIndex(where: { $0.id == msgId }),
                   chatMessagesByAgent[currentAgentId]![idx].taskStatus != .cancelled {
                    let cancelledLabel = String(localized: "Task cancelled.", bundle: LanguageManager.shared.localizedBundle)
                    let content = accumulatedText.isEmpty
                        ? cancelledLabel
                        : accumulatedText + "\n\n---\n> " + cancelledLabel
                    updateMessage(msgId: msgId, content: content, status: .cancelled, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                }
                break streamLoop

            case .error(let eventRunId, _, let message):
                guard eventRunId == runId else { continue }
                receivedTerminalEvent = true
                let errorContent = "⚠️ " + message
                // Ensure UI update happens on MainActor
                await MainActor.run {
                    self.updateMessage(msgId: msgId, content: errorContent, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                }
                chatLog.warning("chat error: runId=\(runId), message=\(message)")
                break streamLoop
            }
        }

        // Stream ended without a terminal event (e.g. WebSocket reconnected, continuation finished).
        // Show whatever we have so far instead of leaving the message in a loading state.
        if !receivedTerminalEvent {
            chatLog.warning("chat stream ended WITHOUT terminal event: runId=\(runId), accumulatedLen=\(accumulatedText.count)")
            if let idx = chatMessagesByAgent[currentAgentId]?.firstIndex(where: { $0.id == msgId }),
               chatMessagesByAgent[currentAgentId]![idx].taskStatus != .completed && chatMessagesByAgent[currentAgentId]![idx].taskStatus != .cancelled && chatMessagesByAgent[currentAgentId]![idx].taskStatus != .timedOut {
                let disconnectNote = String(localized: "Connection was interrupted. The response may be incomplete.", bundle: LanguageManager.shared.localizedBundle)
                let content = accumulatedText.isEmpty
                    ? disconnectNote
                    : accumulatedText + "\n\n---\n> ⚠️ " + disconnectNote
                updateMessage(msgId: msgId, content: content, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            }
        }
    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard foregroundTaskIds.contains(msgId) else { return }
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.insert(msgId)
        isSendingMessage = !foregroundTaskIds.isEmpty

        // Update message status to background (search all agents)
        for agentId in chatMessagesByAgent.keys {
            if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
                let msg = chatMessagesByAgent[agentId]![idx]
                let bgLabel = String(localized: "⏳ Task running in background...", bundle: LanguageManager.shared.localizedBundle)
                let content = msg.content.isEmpty ? bgLabel : msg.content
                var messages = chatMessagesByAgent[agentId]!
                messages[idx] = ChatMessage(
                    role: .assistant, content: content,
                    agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                    taskStatus: .background, id: msgId
                )
                chatMessagesByAgent[agentId] = messages
                return
            }
        }
    }

    /// Cancel an in-progress chat task.
    /// Sends chat.abort via WebSocket and terminates the event stream.
    func cancelChat(_ msgId: UUID) {
        // 1. Look up runId and send abort via gateway WebSocket
        let runId = activeChatRuns[msgId]
        let sessionKey = sessionKeyForAgent(selectedAgentId)
        Task {
            _ = await gatewayClient.abortChat(sessionKey: sessionKey, runId: runId)
        }

        // 2. Terminate the event stream for this message
        gatewayClient.unsubscribe(subscriberId: msgId.uuidString)
        activeChatRuns.removeValue(forKey: msgId)

        // 3. Update message status to cancelled (search all agents)
        for agentId in chatMessagesByAgent.keys {
            if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
                let msg = chatMessagesByAgent[agentId]![idx]
                let cancelledLabel = String(localized: "Task cancelled by user.", bundle: LanguageManager.shared.localizedBundle)
                let content = msg.content.isEmpty
                    ? cancelledLabel
                    : msg.content + "\n\n---\n> " + cancelledLabel
                var messages = chatMessagesByAgent[agentId]!
                messages[idx] = ChatMessage(
                    role: .assistant, content: content,
                    agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                    taskStatus: .cancelled, id: msgId
                )
                chatMessagesByAgent[agentId] = messages
                break
            }
        }

        // 4. Cleanup tracking
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.remove(msgId)
        taskAgentMap.removeValue(forKey: msgId)
        isSendingMessage = !foregroundTaskIds.isEmpty
    }

    /// Filter out system prompt lines from openclaw agent output
    nonisolated static func filterAgentOutput(_ output: String?) -> String? {
        guard let output = output else { return nil }
        // Strip ANSI escape codes first
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
        let filtered = cleaned
            .components(separatedBy: "\n")
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                if trimmed.hasPrefix("[agent-scope]") { return false }
                if trimmed.hasPrefix("[plugins]") { return false }
                if trimmed.hasPrefix("[agent/embedded]") { return false }
                if trimmed.hasPrefix("Gateway agent failed") { return false }
                if trimmed.hasPrefix("Gateway target:") { return false }
                if trimmed.hasPrefix("Source: local") { return false }
                if trimmed.hasPrefix("Bind: loopback") { return false }
                if trimmed.hasPrefix("Config:") && trimmed.contains("openclaw.json") { return false }
                if trimmed.hasPrefix("Config warnings:") { return false }
                if trimmed.hasPrefix("Config overwrite:") { return false }
                if trimmed.hasPrefix("- plugins.") { return false }
                if trimmed.hasPrefix("- ") && trimmed.contains("plugin") && trimmed.contains("detected") { return false }
                if trimmed.contains("plugins.allow is empty") { return false }
                if trimmed.contains("Multiple agents marked default") { return false }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.isEmpty ? nil : filtered
    }

    func clearChat() {
        chatMessages.removeAll()
        // Reset the backend session for the current agent to avoid token overflow
        resetAgentSession(agentId: selectedAgentId)
    }

    /// Reset the backend session files for an agent so the next message starts fresh.
    private func resetAgentSession(agentId: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(homeDir)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        let fm = FileManager.default

        // Read sessions.json to find the active session ID for the main channel
        let sessionKey = "agent:\(agentId):main"
        guard let data = fm.contents(atPath: sessionsJsonPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[sessionKey] as? [String: Any],
              let sessionId = entry["sessionId"] as? String else {
            NSLog("[Chat] resetAgentSession: no active session found for %@", agentId)
            return
        }

        // Rename the .jsonl file to .jsonl.reset.<timestamp>
        let jsonlPath = "\(sessionsDir)/\(sessionId).jsonl"
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(jsonlPath).reset.\(timestamp)"
        if fm.fileExists(atPath: jsonlPath) {
            try? fm.moveItem(atPath: jsonlPath, toPath: backupPath)
            NSLog("[Chat] resetAgentSession: renamed %@ -> %@", jsonlPath, backupPath)
        }

        // Remove the session entry from sessions.json so backend creates a new one
        root.removeValue(forKey: sessionKey)
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: sessionsJsonPath))
            NSLog("[Chat] resetAgentSession: removed session key %@ from sessions.json", sessionKey)
        }
    }

    // MARK: - Status Summary

    func getStatusSummary() -> String {
        let status = openclawService.status.rawValue
        let version = openclawService.version.isEmpty ? "Unknown" : openclawService.version

        if openclawService.status == .running {
            let uptime = formatUptime(openclawService.uptime)
            return "\(status) • v\(version) • Uptime: \(uptime)"
        } else {
            return "\(status) • v\(version)"
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }

    // MARK: - Plugin Management

    /// Refresh the installed plugins list by running `openclaw plugins list`
    func loadPlugins() async {
        isLoadingPlugins = true
        // Strip ANSI color codes for clean parsing
        let output = await openclawService.runCommand(
            "openclaw plugins list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        plugins = Self.parsePluginList(output: output)
            .sorted { a, b in
                if a.enabled != b.enabled { return a.enabled }
                return a.channel.localizedCaseInsensitiveCompare(b.channel) == .orderedAscending
            }
        isLoadingPlugins = false
    }

    /// Parse `openclaw plugins list` table output.
    /// Table format: │ Name │ ID │ Status │ Source │ Version │
    /// Status values: "loaded", "disabled"
    /// A new row starts when the Status cell is non-empty.
    /// Continuation lines (Status empty) may carry overflow text for Name or ID.
    static func parsePluginList(output: String?) -> [PluginInfo] {
        guard let output = output else { return [] }

        var results: [PluginInfo] = []
        var currentName: String?
        var currentId: String?
        var currentStatus: String?
        var currentSource: String?
        var currentVersion: String?

        func flushRow() {
            guard var name = currentName, let status = currentStatus else { return }
            var id = currentId ?? ""
            let source = currentSource ?? ""
            let version = currentVersion ?? ""

            // If ID is empty, try to extract from Source ("stock:plugin-id/..." or "global:plugin-id/...")
            if id.isEmpty, !source.isEmpty,
               let colonIdx = source.firstIndex(of: ":"),
               let slashIdx = source[source.index(after: colonIdx)...].firstIndex(of: "/") {
                id = String(source[source.index(after: colonIdx)..<slashIdx])
            }

            // Last resort: derive ID from name
            if id.isEmpty {
                id = name.replacingOccurrences(of: "@openclaw/", with: "")
            }

            if name.isEmpty { name = id }

            let enabled = status == "loaded"

            // Determine origin from source prefix
            let origin: PluginOrigin
            if source.hasPrefix("stock:") {
                origin = .bundled
            } else if source.hasPrefix("global:") {
                origin = .global
            } else {
                origin = .unknown
            }

            results.append(PluginInfo(
                channel: name,
                pluginId: id,
                installed: true,
                enabled: enabled,
                source: source,
                version: version,
                origin: origin
            ))
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("│") else { continue }
            if trimmed.contains("Name") && trimmed.contains("Status") && trimmed.contains("Source") {
                continue
            }

            let cells = trimmed.components(separatedBy: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4 else { continue }

            let name = cells[1]
            let pluginId = cells[2]
            let status = cells[3]
            let source = cells.count >= 5 ? cells[4] : ""
            let version = cells.count >= 6 ? cells[5] : ""

            if !status.isEmpty {
                // New row — flush previous
                flushRow()
                currentName = name
                currentId = pluginId
                currentStatus = status
                currentSource = source
                currentVersion = version
            } else {
                // Continuation line — append Name overflow
                if !name.isEmpty, let existing = currentName {
                    if existing.hasSuffix("/") || existing.hasSuffix("-") {
                        currentName = existing + name
                    } else {
                        currentName = existing + " " + name
                    }
                }
                // Append ID overflow (IDs never contain spaces, always direct concat)
                if !pluginId.isEmpty {
                    if let existing = currentId, !existing.isEmpty {
                        currentId = existing + pluginId
                    } else {
                        currentId = pluginId
                    }
                }
            }
        }
        flushRow()

        return results
    }

    /// Enable a plugin
    func enablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins enable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to enable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) enabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Disable a plugin
    func disablePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand("openclaw plugins disable \(plugin.pluginId) 2>&1")
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to disable \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) disabled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Install a plugin from npm package name or local path
    /// - Parameters:
    ///   - spec: npm package name (e.g. `@openclaw/discord`) or local file/directory path
    ///   - link: if true, uses `--link` flag (for local directory development)
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
            showErrorMessage("Failed to install plugin: \(output)")
        } else {
            showSuccessMessage("Plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Install the Weixin plugin via npx
    func installWeixinPlugin() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "npx -y @tencent-weixin/openclaw-weixin-cli@latest install 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to install Weixin plugin: \(output)")
        } else {
            showSuccessMessage("Weixin plugin installed successfully")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Uninstall a user-installed (global) plugin
    func uninstallPlugin(_ plugin: PluginInfo) async {
        guard plugin.origin == .global else {
            showErrorMessage("Built-in plugins cannot be uninstalled. Use Disable instead.")
            return
        }
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins uninstall \(plugin.pluginId) --force 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to uninstall \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) uninstalled")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Update a single plugin
    func updatePlugin(_ plugin: PluginInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update \(plugin.pluginId) 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to update \(plugin.channel): \(output)")
        } else {
            showSuccessMessage("\(plugin.channel) updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Update all plugins
    func updateAllPlugins() async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw plugins update --all 2>&1", timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to update plugins: \(output)")
        } else {
            showSuccessMessage("All plugins updated")
        }
        await loadPlugins()
        isPerformingAction = false
    }

    /// Get detailed info about a plugin
    func getPluginInfo(_ plugin: PluginInfo) async -> String? {
        let output = await openclawService.runCommand(
            "openclaw plugins info \(plugin.pluginId) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        return output
    }

    // MARK: - Channel Management

    /// Available channel types for adding
    static let availableChannelTypes = [
        "telegram", "whatsapp", "discord", "irc", "googlechat", "slack",
        "signal", "imessage", "feishu", "nostr", "msteams", "mattermost",
        "nextcloud-talk", "matrix", "dingtalk", "bluebubbles", "line",
        "zalo", "synology-chat", "tlon", "weixin"
    ]

    /// Load channels by running `openclaw channels status`
    func loadChannels() async {
        isLoadingChannels = true
        let output = await openclawService.runCommand(
            "openclaw channels status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        channels = Self.parseChannelStatus(output: output)
            .filter { $0.enabled }
            .sorted { a, b in
                let aPriority = a.configured && a.linked ? 0 : a.configured ? 1 : 2
                let bPriority = b.configured && b.linked ? 0 : b.configured ? 1 : 2
                if aPriority != bPriority { return aPriority < bPriority }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        isLoadingChannels = false
    }

    /// Parse `openclaw channels status` output.
    /// Lines like: `- WhatsApp default: enabled, configured, not linked, stopped, disconnected, dm:pairing, error:not linked`
    /// or: `- DingTalk default: enabled, configured`
    /// Stops at "Warnings:" or "Tip:" sections to avoid parsing non-channel lines.
    static func parseChannelStatus(output: String?) -> [ChannelInfo] {
        guard let output = output else { return [] }

        var results: [ChannelInfo] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop parsing at non-channel sections
            let lower = trimmed.lowercased()
            if lower.hasPrefix("warnings:") || lower.hasPrefix("tip:") || lower.hasPrefix("docs:") || lower.hasPrefix("usage:") {
                break
            }

            // Match lines starting with "- ChannelName accountId: status1, status2, ..."
            guard trimmed.hasPrefix("- ") else { continue }
            let content = String(trimmed.dropFirst(2))

            // Split at first ":"
            guard let colonIdx = content.firstIndex(of: ":") else { continue }
            let nameAndAccount = content[content.startIndex..<colonIdx]
                .trimmingCharacters(in: .whitespaces)
            let statusPart = content[content.index(after: colonIdx)...]
                .trimmingCharacters(in: .whitespaces)

            // The status part must contain "enabled" or "disabled" to be a channel line
            let statusLower = statusPart.lowercased()
            guard statusLower.contains("enabled") || statusLower.contains("disabled") else { continue }

            // Split name and account: "WhatsApp default" -> name="WhatsApp", account="default"
            let nameParts = nameAndAccount.components(separatedBy: " ")
            let channelName: String
            let account: String
            if nameParts.count >= 2 {
                channelName = nameParts.dropLast().joined(separator: " ")
                account = nameParts.last!
            } else {
                channelName = nameAndAccount
                account = "default"
            }

            // Parse status tags
            let tags = statusPart.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }

            let enabled = tags.contains("enabled")
            let configured = tags.contains("configured")
            let notConfigured = tags.contains("not configured")
            let linked = tags.contains("linked")
            let notLinked = tags.contains("not linked")

            // Extract error message if present
            var errorMsg: String?
            for tag in tags {
                if tag.hasPrefix("error:") {
                    errorMsg = String(tag.dropFirst(6))
                }
            }

            results.append(ChannelInfo(
                name: channelName,
                account: account,
                enabled: enabled,
                configured: configured && !notConfigured,
                linked: notLinked ? false : (linked || configured),
                error: errorMsg,
                statusTags: tags
            ))
        }

        return results
    }

    /// Add a channel with token
    func addChannel(channelType: String, token: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw channels add --channel \(channelType) --token '\(token)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add \(channelType): \(output)")
        } else {
            showSuccessMessage("\(channelType) channel added")
        }
        await loadChannels()
        isPerformingAction = false
    }

    func addChannel(channelType: String, appKey: String, appSecret: String) async {
        isPerformingAction = true
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        let fm = FileManager.default

        do {
            guard let data = fm.contents(atPath: configPath),
                  var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                showErrorMessage("Failed to read openclaw.json")
                isPerformingAction = false
                return
            }

            var channels = root["channels"] as? [String: Any] ?? [:]
            let channelConfig: [String: Any]
            if channelType == "feishu" {
                channelConfig = [
                    "connectionMode": "websocket",
                    "appId": appKey,
                    "appSecret": appSecret,
                    "dmPolicy": "open",
                    "enabled": true,
                    "groupPolicy": "open",
                    "requireMention": false
                ]
            } else {
                channelConfig = [
                    "allowFrom": ["*"],
                    "clientId": appKey,
                    "clientSecret": appSecret,
                    "dmPolicy": "open",
                    "enableAICard": false,
                    "enabled": true,
                    "groupPolicy": "open",
                    "requireMention": true
                ]
            }
            channels[channelType] = channelConfig
            root["channels"] = channels

            let updatedData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try updatedData.write(to: URL(fileURLWithPath: configPath))
            showSuccessMessage("\(channelType) channel added")
        } catch {
            showErrorMessage("Failed to add \(channelType): \(error.localizedDescription)")
        }

        await loadChannels()
        isPerformingAction = false
    }

    /// Remove a channel
    func removeChannel(_ channel: ChannelInfo) async {
        isPerformingAction = true
        let channelType = channel.name.lowercased()
        let output = await openclawService.runCommand(
            "openclaw channels remove --channel \(channelType) --account \(channel.account) --delete 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove \(channel.name): \(output)")
        } else {
            // Also disable the channel so it won't reappear in status list
            disableChannelInConfig(channelType)
            showSuccessMessage("\(channel.name) channel removed")
        }
        await loadChannels()
        isPerformingAction = false
    }

    /// Set enabled=false for a channel in openclaw.json
    private func disableChannelInConfig(_ channelType: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        let fm = FileManager.default
        guard let data = fm.contents(atPath: configPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var channels = root["channels"] as? [String: Any] ?? [:]
        var chConfig = channels[channelType] as? [String: Any] ?? [:]
        chConfig["enabled"] = false
        channels[channelType] = chConfig
        root["channels"] = channels
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Weixin QR Login

    /// Start Weixin channel login by streaming `openclaw channels login --channel openclaw-weixin`.
    /// Uses `script` to wrap the command in a pseudo-terminal (PTY) so that openclaw
    /// flushes its output immediately instead of buffering it in a pipe.
    func loginWeixinChannel() {
        weixinLoginStatus = .waitingScan
        weixinQRImage = nil
        cancelWeixinLogin()

        // Debug logging — writes to /tmp/weixin_debug.log
        let _ = FileManager.default.createFile(atPath: "/tmp/weixin_debug.log", contents: nil)
        let debugLog = FileHandle(forWritingAtPath: "/tmp/weixin_debug.log")
        let dbgLock = NSLock()
        let dbg: @Sendable (String) -> Void = { msg in
            let line = "[\(Date())] \(msg)\n"
            dbgLock.lock()
            debugLog?.write(line.data(using: .utf8) ?? Data())
            dbgLock.unlock()
        }

        let enrichedPath = OpenClawService.buildEnrichedPath()
        dbg("PATH=\(enrichedPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c",
                             "openclaw channels login --channel openclaw-weixin 2>&1"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        weixinLoginProcess = process

        // Use readabilityHandler for non-blocking streaming
        let handle = pipe.fileHandleForReading
        let accumulatedLock = NSLock()
        var accumulated = ""

        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                dbg("readabilityHandler: empty data (EOF)")
                fileHandle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else {
                dbg("readabilityHandler: failed to decode \(data.count) bytes as UTF-8")
                return
            }

            accumulatedLock.lock()
            accumulated += chunk
            let current = accumulated
            accumulatedLock.unlock()

            dbg("chunk(\(data.count) bytes): \(chunk.prefix(200))")

            let cleaned = DashboardViewModel.stripAnsiCodes(current)

            // Check for success
            let lower = cleaned.lowercased()
            if lower.contains("successfully") || lower.contains("登录成功") || lower.contains("连接成功") {
                dbg("SUCCESS detected")
                DispatchQueue.main.async {
                    self?.weixinLoginStatus = .success
                    Task { [weak self] in
                        await self?.loadChannels()
                    }
                }
                return
            }

            // Try to parse QR
            let lines = cleaned.components(separatedBy: .newlines)
            let qrCharCount = cleaned.unicodeScalars.filter { "█▄▀".unicodeScalars.contains($0) }.count
            dbg("lines=\(lines.count), qrChars=\(qrCharCount)")

            if let qrImage = DashboardViewModel.parseAsciiQRCode(from: cleaned) {
                dbg("QR IMAGE PARSED OK, size=\(qrImage.size)")
                accumulatedLock.lock()
                accumulated = ""
                accumulatedLock.unlock()
                DispatchQueue.main.async {
                    self?.weixinQRImage = qrImage
                    self?.weixinLoginStatus = .waitingScan
                }
            } else {
                dbg("QR parse returned nil")
            }
        }

        // Start the process
        do {
            try process.run()
            dbg("Process started, pid=\(process.processIdentifier)")
        } catch {
            dbg("Failed to start process: \(error)")
            weixinLoginStatus = .failed("Failed to start login: \(error.localizedDescription)")
            return
        }

        // Monitor process termination
        process.terminationHandler = { [weak self] proc in
            dbg("Process terminated, status=\(proc.terminationStatus)")
            // Give readabilityHandler a moment to process remaining data
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self?.weixinLoginStatus != .success && self?.weixinQRImage == nil {
                    accumulatedLock.lock()
                    let finalAccum = accumulated
                    accumulatedLock.unlock()
                    dbg("Final accumulated length=\(finalAccum.count)")
                    dbg("Final accumulated content:\n\(String(finalAccum.prefix(2000)))")

                    let cleaned = DashboardViewModel.stripAnsiCodes(finalAccum)
                    if let qrImage = DashboardViewModel.parseAsciiQRCode(from: cleaned) {
                        dbg("Late QR parse succeeded!")
                        self?.weixinQRImage = qrImage
                        self?.weixinLoginStatus = .waitingScan
                    } else if proc.terminationStatus != 0 {
                        self?.weixinLoginStatus = .failed("Login process exited with code \(proc.terminationStatus)")
                    }
                }
                debugLog?.closeFile()
            }
        }
    }

    /// Cancel any in-progress Weixin login
    func cancelWeixinLogin() {
        if let process = weixinLoginProcess, process.isRunning {
            process.terminate()
        }
        weixinLoginProcess = nil
    }

    /// Reset Weixin login state
    func resetWeixinLogin() {
        cancelWeixinLogin()
        weixinQRImage = nil
        weixinLoginStatus = .idle
    }

    /// Strip ANSI escape codes from terminal output
    nonisolated static func stripAnsiCodes(_ text: String) -> String {
        // Cache compiled regex to avoid recompilation on every call
        // This is critical for performance when processing large amounts of terminal output
        let ansiRegex: NSRegularExpression
        if let cached = ansiRegexCache {
            ansiRegex = cached
        } else {
            // Match CSI sequences: ESC[ ... final_byte
            // Also match OSC sequences: ESC] ... BEL
            guard let regex = try? NSRegularExpression(
                pattern: "\u{1B}\\[[0-9;]*[a-zA-Z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}\\([A-Z]",
                options: []
            ) else { return text }
            ansiRegexCache = regex
            ansiRegex = regex
        }
        return ansiRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    // Static cache for compiled ANSI regex
    nonisolated(unsafe) static var ansiRegexCache: NSRegularExpression?

    /// Parse ASCII QR code block from command output and render it as an NSImage
    nonisolated static func parseAsciiQRCode(from output: String) -> NSImage? {
        let lines = output.components(separatedBy: .newlines)

        // QR block characters used by qrcode-terminal (small mode)
        let qrBlockScalars: Set<Unicode.Scalar> = [
            "\u{2588}", // █ FULL BLOCK
            "\u{2580}", // ▀ UPPER HALF BLOCK
            "\u{2584}", // ▄ LOWER HALF BLOCK
        ]
        var qrLines: [String] = []
        var inQR = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if inQR { break }
                continue
            }
            // Count actual QR block characters (not spaces)
            let blockCount = trimmed.unicodeScalars.filter { qrBlockScalars.contains($0) }.count
            // A valid QR line has many block chars and only contains block chars + spaces
            let allQR = trimmed.unicodeScalars.allSatisfy { qrBlockScalars.contains($0) || $0 == " " }
            if allQR && blockCount >= 5 && trimmed.count > 10 {
                inQR = true
                qrLines.append(trimmed)
            } else if inQR {
                break
            }
        }

        guard qrLines.count >= 5 else { return nil }

        // Each character in the ASCII QR maps to a 1-wide x 2-tall pixel region:
        // "█" = both top and bottom black
        // "▀" = top black, bottom white
        // "▄" = top white, bottom black
        // " " = both white
        let cols = qrLines.map { $0.count }.max() ?? 0
        let rows = qrLines.count * 2  // Each text line = 2 pixel rows

        let pixelSize = 4  // Scale each module to 4x4 pixels
        let imgWidth = cols * pixelSize
        let imgHeight = rows * pixelSize

        guard imgWidth > 0, imgHeight > 0 else { return nil }

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: imgWidth,
            pixelsHigh: imgHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = bitmapRep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx

        // Fill white background
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: imgWidth, height: imgHeight).fill()

        for (lineIdx, line) in qrLines.enumerated() {
            for (colIdx, char) in line.enumerated() {
                let topBlack: Bool
                let bottomBlack: Bool

                switch char {
                case "█":
                    topBlack = true; bottomBlack = true
                case "▀":
                    topBlack = true; bottomBlack = false
                case "▄":
                    topBlack = false; bottomBlack = true
                default:
                    topBlack = false; bottomBlack = false
                }

                // Note: NSImage coordinate system is flipped (0,0 = bottom-left)
                let x = colIdx * pixelSize

                if topBlack {
                    let y = imgHeight - (lineIdx * 2) * pixelSize - pixelSize
                    NSColor.black.setFill()
                    NSRect(x: x, y: y, width: pixelSize, height: pixelSize).fill()
                }
                if bottomBlack {
                    let y = imgHeight - (lineIdx * 2 + 1) * pixelSize - pixelSize
                    NSColor.black.setFill()
                    NSRect(x: x, y: y, width: pixelSize, height: pixelSize).fill()
                }
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: imgWidth, height: imgHeight))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Cron Job Management

    /// Load cron jobs by running `openclaw cron list --json`
    func loadCronJobs() async {
        isLoadingCronJobs = true
        let output = await openclawService.runCommand(
            "openclaw cron list --all --json 2>&1",
            timeout: 60
        )
        cronJobs = Self.parseCronJobList(output: output)
        isLoadingCronJobs = false
    }

    /// Parse `openclaw cron list --json` output
    static func parseCronJobList(output: String?) -> [CronJobInfo] {
        guard let output = output else { return [] }

        // Strip ANSI escape codes
        let ansiPattern = "\\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Try to extract JSON from the output (skip any non-JSON lines)
        let lines = cleaned.components(separatedBy: .newlines)
        var jsonString = ""
        var inJson = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inJson {
                if trimmed == "[" || trimmed.hasPrefix("[{") || trimmed.hasPrefix("[\"") {
                    inJson = true
                } else if trimmed.hasPrefix("{") {
                    inJson = true
                }
            }
            if inJson {
                jsonString += line + "\n"
            }
        }

        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else { return [] }

        // Try parsing as {"jobs": [...]} or as [...]
        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let jobsArray = wrapper["jobs"] as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        } else if let jobsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jobsArray.compactMap { Self.parseCronJobDict($0) }
        }

        return []
    }

    /// Parse a single cron job dictionary
    private static func parseCronJobDict(_ dict: [String: Any]) -> CronJobInfo? {
        guard let id = dict["id"] as? String else { return nil }

        let name = dict["name"] as? String ?? id

        // schedule is a nested object: { kind, expr, tz }
        let scheduleObj = dict["schedule"] as? [String: Any]
        let schedule = scheduleObj?["expr"] as? String ?? dict["schedule"] as? String ?? ""
        let timezone = scheduleObj?["tz"] as? String ?? dict["timezone"] as? String ?? ""

        let agentId = dict["agentId"] as? String ?? dict["agent_id"] as? String ?? ""
        let sessionTarget = dict["sessionTarget"] as? String ?? dict["session_target"] as? String ?? ""

        // message is nested in payload: { kind, message, timeoutSeconds }
        let payloadObj = dict["payload"] as? [String: Any]
        let message = payloadObj?["message"] as? String ?? dict["message"] as? String ?? ""

        let enabled = dict["enabled"] as? Bool ?? true

        // nextRun / lastRun are timestamps in state: { nextRunAtMs, lastRunAtMs }
        let stateObj = dict["state"] as? [String: Any]
        let nextRun = Self.formatTimestamp(stateObj?["nextRunAtMs"])
        let lastRun = Self.formatTimestamp(stateObj?["lastRunAtMs"])

        let status = dict["status"] as? String ?? (enabled ? "idle" : "disabled")
        let model = dict["model"] as? String ?? ""

        return CronJobInfo(
            cronId: id,
            name: name,
            schedule: schedule,
            timezone: timezone,
            agentId: agentId,
            sessionTarget: sessionTarget,
            message: message,
            enabled: enabled,
            nextRun: nextRun,
            lastRun: lastRun,
            status: status,
            model: model
        )
    }

    /// Format a millisecond timestamp to a readable date string
    private static func formatTimestamp(_ value: Any?) -> String {
        guard let ms = value as? Double ?? (value as? Int).map({ Double($0) }) else { return "" }
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Add a new cron job
    func addCronJob(name: String, schedule: String, timezone: String, agentId: String, message: String, sessionTarget: String) async {
        isPerformingAction = true
        var cmd = "openclaw cron add --name '\(name)' --cron '\(schedule)'"
        if !timezone.isEmpty {
            cmd += " --tz '\(timezone)'"
        }
        if !agentId.isEmpty {
            cmd += " --agent '\(agentId)'"
        }
        if !sessionTarget.isEmpty {
            cmd += " --session-target '\(sessionTarget)'"
        }
        if !message.isEmpty {
            let escapedMessage = message.replacingOccurrences(of: "'", with: "'\\''")
            cmd += " --message '\(escapedMessage)'"
        }
        cmd += " --json 2>&1"

        let output = await openclawService.runCommand(cmd)
        if let output = output, output.lowercased().contains("error") && !output.contains("{") {
            showErrorMessage("Failed to add cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(name)' created")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Enable a cron job
    func enableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron enable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to enable cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' enabled")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Disable a cron job
    func disableCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron disable \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to disable cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' disabled")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Remove a cron job
    func removeCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron rm \(job.cronId) 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' removed")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    /// Manually run a cron job
    func runCronJob(_ job: CronJobInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw cron run \(job.cronId) 2>&1",
            timeout: 120
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to run cron job: \(output)")
        } else {
            showSuccessMessage("Cron job '\(job.name)' triggered")
        }
        await loadCronJobs()
        isPerformingAction = false
    }

    // MARK: - Sessions Summary (Status Tab Monitoring)

    /// Load agent sessions summary by running `openclaw sessions --all-agents --json`
    func loadSessionsSummary() async {
        isLoadingSessionsSummary = true
        let output = await openclawService.runCommand(
            "openclaw sessions --all-agents --json 2>&1", timeout: 15
        )
        sessionsSummary = Self.parseSessionsSummary(output: output)
        isLoadingSessionsSummary = false
    }

    /// Parse `openclaw sessions --all-agents --json` output into a SessionsSummary.
    /// Output may contain non-JSON prefix (warnings), so we find the first `[`.
    /// Sessions are aggregated by agentId. Main sessions have keys ending in `:main` (no `:cron:`).
    /// Tokens are accumulated across ALL sessions (including cron).
    static func parseSessionsSummary(output: String?) -> SessionsSummary? {
        guard let output = output else { return nil }

        // Strip ANSI escape codes
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Find first '{' or '[' to locate JSON start
        var sessions: [[String: Any]] = []

        if let objStart = cleaned.firstIndex(of: "{") {
            // Output is a JSON object like { "sessions": [...] }
            let jsonString = String(cleaned[objStart...])
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["sessions"] as? [[String: Any]] {
                sessions = arr
            }
        }

        // Fallback: try parsing as top-level array if object parsing yielded nothing
        if sessions.isEmpty, let arrStart = cleaned.firstIndex(of: "[") {
            let arrString = String(cleaned[arrStart...])
            if let arrData = arrString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: arrData) as? [[String: Any]] {
                sessions = parsed
            }
        }

        guard !sessions.isEmpty else { return nil }

        // Accumulate totals across all sessions
        var totalInput = 0
        var totalOutput = 0
        var totalTokens = 0

        // Group by agentId for agent-level info
        // Key: agentId, Value: (model, inputTokens, outputTokens, totalTokens, latestUpdatedAt, sessionCount)
        struct AgentAccum {
            var model: String = ""
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var totalTokens: Int = 0
            var latestUpdatedAt: Double = 0
            var sessionCount: Int = 0
        }
        var agentMap: [String: AgentAccum] = [:]

        for session in sessions {
            let key = session["key"] as? String ?? ""
            let agentId = session["agentId"] as? String ?? ""
            let inputTk = session["inputTokens"] as? Int ?? 0
            let outputTk = session["outputTokens"] as? Int ?? 0
            let totalTk = session["totalTokens"] as? Int ?? 0
            let model = session["model"] as? String ?? ""
            let updatedAt = session["updatedAt"] as? Double ?? 0

            // Accumulate total tokens across ALL sessions
            totalInput += inputTk
            totalOutput += outputTk
            totalTokens += totalTk

            // Aggregate all sessions by agentId (main, cron, dingtalk, etc.)
            if !agentId.isEmpty {
                var accum = agentMap[agentId] ?? AgentAccum()
                accum.model = model
                accum.inputTokens += inputTk
                accum.outputTokens += outputTk
                accum.totalTokens += totalTk
                accum.sessionCount += 1
                if updatedAt > accum.latestUpdatedAt {
                    accum.latestUpdatedAt = updatedAt
                }
                agentMap[agentId] = accum
            }
        }

        // Build AgentSessionInfo array sorted by latest activity
        let agents = agentMap.map { (agentId, accum) -> AgentSessionInfo in
            let lastActive: Date? = accum.latestUpdatedAt > 0
                ? Date(timeIntervalSince1970: accum.latestUpdatedAt / 1000.0)
                : nil
            return AgentSessionInfo(
                agentId: agentId,
                model: accum.model,
                inputTokens: accum.inputTokens,
                outputTokens: accum.outputTokens,
                totalTokens: accum.totalTokens,
                lastActiveAt: lastActive,
                sessionCount: accum.sessionCount
            )
        }.sorted { a, b in
            (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
        }

        return SessionsSummary(
            agents: agents,
            totalInput: totalInput,
            totalOutput: totalOutput,
            totalTokens: totalTokens,
            totalSessions: sessions.count
        )
    }

    // MARK: - Budget Management

    /// Sync the budgetRules @Published mirror from the nested budgetService.
    /// Call this after any mutation to budgetService.config.rules so SwiftUI re-renders.
    func syncBudgetRules() {
        budgetRules = budgetService.config.rules
    }

    /// Load budget status by combining session data with budget rules and model costs.
    func loadBudgets() async {
        os_log("[DashboardViewModel] Auto-refreshing budgets at %@", log: OSLog.default, type: .info, Date().description)
        isLoadingBudgets = true

        // Try to load session data (may remain nil if service is not running)
        await loadSessionsSummary()
        os_log("[DashboardViewModel] Loaded sessions: %d tokens", log: OSLog.default, type: .info, sessionsSummary?.totalTokens ?? 0)

        budgetService.loadConfig()
        syncBudgetRules()
        budgetSnapshots = budgetService.evaluate(
            sessions: sessionsSummary,
            modelCosts: settings.settings.configuredModels
        )
        os_log("[DashboardViewModel] Updated %d budget snapshots", log: OSLog.default, type: .info, budgetSnapshots.count)

        isLoadingBudgets = false

        #if REQUIRE_LOGIN
        // Also load official service billing in parallel
        await loadKeysBilling()
        #endif
    }

    #if REQUIRE_LOGIN
    /// Load official service key billing from GetClawHub backend.
    func loadKeysBilling() async {
        await membershipManager?.fetchKeysBilling()
    }
    #endif

    // MARK: - Budget Monitoring

    func startBudgetMonitor() {
        print("[DashboardViewModel] Starting budget monitor with 30-second interval")
        budgetMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadBudgets()
            }
        }
        // Also load immediately
        Task {
            await loadBudgets()
        }
    }

    func stopBudgetMonitor() {
        print("[DashboardViewModel] Stopping budget monitor")
        budgetMonitorTimer?.invalidate()
        budgetMonitorTimer = nil
    }

    // MARK: - Model Management

    /// Load models overview, model list, and fallback lists
    func loadModels() async {
        isLoadingModels = true
        async let statusOutput = openclawService.runCommand(
            "openclaw models status 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let listOutput = openclawService.runCommand(
            "openclaw models list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let fbOutput = openclawService.runCommand(
            "openclaw models fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        async let imgFbOutput = openclawService.runCommand(
            "openclaw models image-fallbacks list 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'"
        )
        modelOverview = Self.parseModelStatus(output: await statusOutput)
        models = Self.parseModelList(output: await listOutput)
            .sorted { a, b in
                // Image-capable models first
                if a.supportsImage != b.supportsImage { return a.supportsImage }
                // Then by context length descending
                let aCtx = Self.parseContextLength(a.contextLength)
                let bCtx = Self.parseContextLength(b.contextLength)
                if aCtx != bCtx { return aCtx > bCtx }
                return a.modelId.localizedCaseInsensitiveCompare(b.modelId) == .orderedAscending
            }
        fallbackModels = Self.parseFallbackList(output: await fbOutput)
        imageFallbackModels = Self.parseFallbackList(output: await imgFbOutput)
        isLoadingModels = false
    }

    /// Parse `models status` output for overview info
    static func parseModelStatus(output: String?) -> ModelOverview {
        guard let output = output else { return ModelOverview() }

        var overview = ModelOverview()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()

            if lower.hasPrefix("default") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.defaultModel = value
                }
            } else if lower.hasPrefix("image model") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageModel = value == "-" ? nil : value
                }
            } else if lower.hasPrefix("fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.fallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("image fallbacks") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.imageFallbacks = value == "-" ? "" : value
                }
            } else if lower.hasPrefix("aliases") {
                if let value = Self.extractStatusValue(trimmed) {
                    overview.aliases = value == "-" ? "" : value
                }
            }
        }
        return overview
    }

    /// Extract value after ": " in a status line
    private static func extractStatusValue(_ line: String) -> String? {
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Parse `fallbacks list` or `image-fallbacks list` output.
    /// Format: "Fallbacks (N):" followed by "- model1" lines, or "- none"
    static func parseFallbackList(output: String?) -> [String] {
        guard let output = output else { return [] }
        var results: [String] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if value.lowercased() == "none" || value.isEmpty { continue }
            results.append(value)
        }
        return results
    }

    /// Parse context length string like "128k", "200k", "1M" into a comparable integer.
    static func parseContextLength(_ str: String) -> Int {
        let s = str.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasSuffix("m") {
            return (Int(s.dropLast()) ?? 0) * 1_000_000
        } else if s.hasSuffix("k") {
            return (Int(s.dropLast()) ?? 0) * 1_000
        }
        return Int(s) ?? 0
    }

    /// Parse `models list` output using fixed column positions from header.
    static func parseModelList(output: String?) -> [ModelInfo] {
        guard let output = output else { return [] }

        var results: [ModelInfo] = []
        // Column positions parsed from header
        var colInput = 0
        var colCtx = 0
        var colLocal = 0
        var colAuth = 0
        var colTags = 0
        var headerFound = false

        for line in output.components(separatedBy: .newlines) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // Detect header and extract column positions
            if !headerFound {
                if let rModel = line.range(of: "Model"),
                   let rInput = line.range(of: "Input"),
                   let rCtx = line.range(of: "Ctx"),
                   let rAuth = line.range(of: "Auth"),
                   let rTags = line.range(of: "Tags") {
                    colInput = line.distance(from: line.startIndex, to: rInput.lowerBound)
                    colCtx = line.distance(from: line.startIndex, to: rCtx.lowerBound)
                    // Local column is optional
                    if let rLocal = line.range(of: "Local") {
                        colLocal = line.distance(from: line.startIndex, to: rLocal.lowerBound)
                    } else {
                        colLocal = colAuth
                    }
                    colAuth = line.distance(from: line.startIndex, to: rAuth.lowerBound)
                    colTags = line.distance(from: line.startIndex, to: rTags.lowerBound)
                    headerFound = true
                }
                continue
            }

            // Extract columns by position
            let len = line.count
            guard len > colInput else { continue }

            func substr(from: Int, to: Int) -> String {
                guard from < len else { return "" }
                let end = min(to, len)
                let start = line.index(line.startIndex, offsetBy: from)
                let finish = line.index(line.startIndex, offsetBy: end)
                return String(line[start..<finish]).trimmingCharacters(in: .whitespaces)
            }

            let modelId = substr(from: 0, to: colInput)
            let input = substr(from: colInput, to: colCtx)
            let ctx = substr(from: colCtx, to: colLocal)
            let local = substr(from: colLocal, to: colAuth)
            let auth = substr(from: colAuth, to: colTags)
            let tags = len > colTags ? String(line[line.index(line.startIndex, offsetBy: colTags)...]).trimmingCharacters(in: .whitespaces) : ""

            guard !modelId.isEmpty else { continue }

            let isDefault = tags.lowercased().contains("default")
            let supportsImage = input.lowercased().contains("image")

            results.append(ModelInfo(
                modelId: modelId,
                input: input,
                contextLength: ctx,
                local: local.lowercased() == "yes",
                authenticated: auth.lowercased() == "yes",
                isDefault: isDefault,
                supportsImage: supportsImage,
                tags: tags
            ))
        }

        return results
    }

    /// Set default model
    func setDefaultModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to set default model: \(output)")
        } else {
            showSuccessMessage("Default model set to \(model.modelId)")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Set image model
    func setImageModel(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models set-image '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to set image model: \(output)")
        } else {
            showSuccessMessage("Image model set to \(model.modelId)")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to fallback list
    func addFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add fallback: \(output)")
        } else {
            showSuccessMessage("\(model.modelId) added to fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from fallback list
    func removeFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove fallback: \(output)")
        } else {
            showSuccessMessage("\(modelId) removed from fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Add a model to image fallback list
    func addImageFallback(_ model: ModelInfo) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks add '\(model.modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to add image fallback: \(output)")
        } else {
            showSuccessMessage("\(model.modelId) added to image fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    /// Remove a model from image fallback list
    func removeImageFallback(_ modelId: String) async {
        isPerformingAction = true
        let output = await openclawService.runCommand(
            "openclaw models image-fallbacks remove '\(modelId)' 2>&1"
        )
        if let output = output, output.lowercased().contains("error") {
            showErrorMessage("Failed to remove image fallback: \(output)")
        } else {
            showSuccessMessage("\(modelId) removed from image fallbacks")
        }
        await loadModels()
        isPerformingAction = false
    }

    // MARK: - Agent Settings Panel

    /// Load full agent detail (SubAgentInfo) for the currently selected agent.
    func loadSelectedAgentDetail() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let baseDir = NSString("~/.openclaw").expandingTildeInPath

        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let agentsSection = json["agents"] as? [String: Any],
              let agentList = agentsSection["list"] as? [[String: Any]] else {
            NSLog("[AgentSettings] loadSelectedAgentDetail: failed to read config")
            return
        }

        guard let entry = agentList.first(where: { $0["id"] as? String == selectedAgentId }) else {
            NSLog("[AgentSettings] loadSelectedAgentDetail: agent %@ not found", selectedAgentId)
            return
        }

        let agentId = selectedAgentId

        // Determine workspace
        let workspace: String
        if let ws = entry["workspace"] as? String {
            workspace = (ws as NSString).expandingTildeInPath
        } else if agentId == "main" {
            workspace = (baseDir as NSString).appendingPathComponent("workspace")
        } else {
            workspace = (baseDir as NSString).appendingPathComponent("workspace-\(agentId)")
        }

        let agentDir = entry["agentDir"] as? String ?? ""
        let model = entry["model"] as? String ?? ""
        let isDefault = entry["isDefault"] as? Bool ?? false

        // Bindings
        var bindingDetails: [String] = []
        if let bindings = entry["bindings"] as? [[String: Any]] {
            for b in bindings {
                if let from = b["from"] as? String, let to = b["to"] as? String {
                    bindingDetails.append("\(from) → \(to)")
                }
            }
        } else if let bindings = entry["bindingDetails"] as? [String] {
            bindingDetails = bindings
        }

        // Read persona files
        let identityContent = readPersonaFile(workspace, "IDENTITY.md")
        let soulContent = readPersonaFile(workspace, "SOUL.md")
        let memoryContent = readPersonaFile(workspace, "MEMORY.md")
        let userContent = readPersonaFile(workspace, "USER.md")
        let agentsContent = readPersonaFile(workspace, "AGENTS.md")
        let bootstrapContent = readPersonaFile(workspace, "BOOTSTRAP.md")
        let heartbeatContent = readPersonaFile(workspace, "HEARTBEAT.md")
        let toolsContent = readPersonaFile(workspace, "TOOLS.md")

        let parsed = PersonaViewModel.parseIdentity(identityContent)
        let identity = entry["identity"] as? [String: Any]

        let name: String = {
            if !parsed.name.isEmpty { return parsed.name }
            if let n = identity?["name"] as? String, !n.isEmpty { return n }
            return entry["name"] as? String ?? agentId
        }()

        let emoji: String = {
            if !parsed.emoji.isEmpty { return parsed.emoji }
            return identity?["emoji"] as? String ?? "🤖"
        }()

        let identitySource = entry["identitySource"] as? String ?? ""

        var info = SubAgentInfo(
            id: agentId,
            name: name,
            emoji: emoji,
            creature: parsed.creature,
            model: model,
            isDefault: isDefault,
            bindingsCount: bindingDetails.count,
            bindingDetails: bindingDetails,
            identitySource: identitySource,
            workspace: workspace,
            agentDir: agentDir
        )
        info.identityContent = identityContent
        info.soulContent = soulContent
        info.memoryContent = memoryContent
        info.userContent = userContent
        info.agentsContent = agentsContent
        info.bootstrapContent = bootstrapContent
        info.heartbeatContent = heartbeatContent
        info.toolsContent = toolsContent
        info.identityOriginal = identityContent
        info.soulOriginal = soulContent
        info.memoryOriginal = memoryContent
        info.userOriginal = userContent
        info.agentsOriginal = agentsContent
        info.bootstrapOriginal = bootstrapContent
        info.heartbeatOriginal = heartbeatContent
        info.toolsOriginal = toolsContent

        selectedAgentDetail = info
    }

    /// Load available models for the settings panel.
    func loadModelsForSettings() async {
        let output = await openclawService.runCommand(
            "openclaw models list --json 2>&1",
            timeout: 30
        )
        let models = SubAgentsViewModel.parseModelList(output: output)
        availableModelsForSettings = models
    }

    /// Save a persona file for the selected agent.
    func saveAgentPersonaFile(file: PersonaViewModel.FileType) {
        guard var detail = selectedAgentDetail, !detail.workspace.isEmpty else { return }
        let workspace = detail.workspace

        switch file {
        case .identity:
            writePersonaFile(workspace, "IDENTITY.md", content: detail.identityContent)
            detail.identityOriginal = detail.identityContent
        case .soul:
            writePersonaFile(workspace, "SOUL.md", content: detail.soulContent)
            detail.soulOriginal = detail.soulContent
        case .memory:
            writePersonaFile(workspace, "MEMORY.md", content: detail.memoryContent)
            detail.memoryOriginal = detail.memoryContent
        case .user:
            break
        }
        selectedAgentDetail = detail
        loadAvailableAgents()
    }

    /// Update the model for the selected agent in openclaw.json.
    func updateAgentModel(model: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        SubAgentsViewModel.patchAgentModel(configPath: configPath, agentId: selectedAgentId, model: model)

        // Update local detail
        selectedAgentDetail?.model = model
        loadAvailableAgents()
    }

    /// Binding for editing a persona file in the settings panel.
    func settingsBinding(for file: PersonaViewModel.FileType) -> Binding<String> {
        Binding<String>(
            get: {
                guard let detail = self.selectedAgentDetail else { return "" }
                switch file {
                case .identity: return detail.identityContent
                case .soul: return detail.soulContent
                case .memory: return detail.memoryContent
                case .user: return ""
                }
            },
            set: { newValue in
                guard self.selectedAgentDetail != nil else { return }
                switch file {
                case .identity: self.selectedAgentDetail?.identityContent = newValue
                case .soul: self.selectedAgentDetail?.soulContent = newValue
                case .memory: self.selectedAgentDetail?.memoryContent = newValue
                case .user: break
                }
            }
        )
    }

    /// Binding for editing a persona file in the settings panel (by file name string).
    func settingsBindingByName(_ fileName: String) -> Binding<String> {
        Binding<String>(
            get: {
                guard let detail = self.selectedAgentDetail else { return "" }
                switch fileName {
                case "USER.md": return detail.userContent
                case "AGENTS.md": return detail.agentsContent
                case "BOOTSTRAP.md": return detail.bootstrapContent
                case "HEARTBEAT.md": return detail.heartbeatContent
                case "TOOLS.md": return detail.toolsContent
                default: return ""
                }
            },
            set: { newValue in
                guard self.selectedAgentDetail != nil else { return }
                switch fileName {
                case "USER.md": self.selectedAgentDetail?.userContent = newValue
                case "AGENTS.md": self.selectedAgentDetail?.agentsContent = newValue
                case "BOOTSTRAP.md": self.selectedAgentDetail?.bootstrapContent = newValue
                case "HEARTBEAT.md": self.selectedAgentDetail?.heartbeatContent = newValue
                case "TOOLS.md": self.selectedAgentDetail?.toolsContent = newValue
                default: break
                }
            }
        )
    }

    /// Save a persona file by file name string.
    func savePersonaFileByName(_ fileName: String) {
        guard var detail = selectedAgentDetail, !detail.workspace.isEmpty else { return }
        let workspace = detail.workspace

        switch fileName {
        case "USER.md":
            writePersonaFile(workspace, fileName, content: detail.userContent)
            detail.userOriginal = detail.userContent
        case "AGENTS.md":
            writePersonaFile(workspace, fileName, content: detail.agentsContent)
            detail.agentsOriginal = detail.agentsContent
        case "BOOTSTRAP.md":
            writePersonaFile(workspace, fileName, content: detail.bootstrapContent)
            detail.bootstrapOriginal = detail.bootstrapContent
        case "HEARTBEAT.md":
            writePersonaFile(workspace, fileName, content: detail.heartbeatContent)
            detail.heartbeatOriginal = detail.heartbeatContent
        case "TOOLS.md":
            writePersonaFile(workspace, fileName, content: detail.toolsContent)
            detail.toolsOriginal = detail.toolsContent
        default: return
        }
        selectedAgentDetail = detail
        loadAvailableAgents()
    }

    /// Check if a persona file is dirty by file name string.
    func isFileDirtyByName(_ fileName: String) -> Bool {
        guard let detail = selectedAgentDetail else { return false }
        switch fileName {
        case "USER.md": return detail.userDirty
        case "AGENTS.md": return detail.agentsDirty
        case "BOOTSTRAP.md": return detail.bootstrapDirty
        case "HEARTBEAT.md": return detail.heartbeatDirty
        case "TOOLS.md": return detail.toolsDirty
        default: return false
        }
    }

    /// Check if a persona file exists (content or original is non-empty) by file name string.
    func hasPersonaFile(_ fileName: String) -> Bool {
        guard let detail = selectedAgentDetail else { return false }
        switch fileName {
        case "USER.md": return !detail.userContent.isEmpty || !detail.userOriginal.isEmpty
        case "AGENTS.md": return !detail.agentsContent.isEmpty || !detail.agentsOriginal.isEmpty
        case "BOOTSTRAP.md": return !detail.bootstrapContent.isEmpty || !detail.bootstrapOriginal.isEmpty
        case "HEARTBEAT.md": return !detail.heartbeatContent.isEmpty || !detail.heartbeatOriginal.isEmpty
        case "TOOLS.md": return !detail.toolsContent.isEmpty || !detail.toolsOriginal.isEmpty
        default: return false
        }
    }

    private func readPersonaFile(_ dirPath: String, _ name: String) -> String {
        let path = (dirPath as NSString).appendingPathComponent(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writePersonaFile(_ dirPath: String, _ name: String, content: String) {
        let path = (dirPath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Plugin Origin

enum PluginOrigin: String {
    case bundled   // stock: prefix — built-in plugin
    case global    // global: prefix — user-installed (npm or local)
    case unknown
}

// MARK: - Plugin Info Model

struct PluginInfo: Identifiable {
    let id = UUID()
    let channel: String
    let pluginId: String
    var installed: Bool
    var enabled: Bool
    var source: String         // raw source string from CLI output
    var version: String        // version string from CLI output
    var origin: PluginOrigin   // derived from source prefix
}

// MARK: - Channel Info Model

struct ChannelInfo: Identifiable {
    let id = UUID()
    let name: String
    let account: String
    let enabled: Bool
    let configured: Bool
    let linked: Bool
    let error: String?
    let statusTags: [String]
}

// MARK: - Model Info

struct ModelOverview {
    var defaultModel: String = "-"
    var imageModel: String?
    var fallbacks: String = ""
    var imageFallbacks: String = ""
    var aliases: String = ""
}

struct ModelInfo: Identifiable {
    let id = UUID()
    let modelId: String
    let input: String
    let contextLength: String
    let local: Bool
    let authenticated: Bool
    var isDefault: Bool
    let supportsImage: Bool
    let tags: String
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let agentId: String?
    let agentEmoji: String?
    let attachments: [URL]
    let taskStatus: TaskStatus
    let scrollTargetId: UUID?  // For notification messages: ID of the message to scroll to

    init(role: ChatRole, content: String, agentId: String? = nil, agentEmoji: String? = nil, attachments: [URL] = [], taskStatus: TaskStatus = .completed, id: UUID = UUID(), scrollTargetId: UUID? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.agentId = agentId
        self.agentEmoji = agentEmoji
        self.attachments = attachments
        self.taskStatus = taskStatus
        self.scrollTargetId = scrollTargetId
    }

    enum ChatRole: String, Codable {
        case user
        case assistant
    }

    enum TaskStatus: String, Codable {
        case loading      // Foreground: waiting for result
        case background   // Moved to background, still running
        case completed    // Done
        case timedOut     // Timed out, process terminated
        case cancelled    // Cancelled by user
    }
}

// MARK: - Skill Info

enum SkillStatus: String {
    case ready = "ready"
    case missing = "missing"
}

struct SkillsSummary {
    var ready: Int = 0
    var total: Int = 0
}

struct SkillInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: SkillStatus
    let description: String
    let source: String
}

struct SkillDetailInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let isReady: Bool
    let description: String
    let source: String
    let path: String
    let requirements: [String]
}

// MARK: - Agent Option

struct AgentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let description: String
    let model: String
    let division: String
}

// MARK: - Cron Job Info

struct CronJobInfo: Identifiable {
    let id = UUID()
    let cronId: String
    let name: String
    let schedule: String
    let timezone: String
    let agentId: String
    let sessionTarget: String
    let message: String
    let enabled: Bool
    let nextRun: String
    let lastRun: String
    let status: String
    let model: String
}

// MARK: - Agent Session Info (Status Tab Monitoring)

struct AgentSessionInfo: Identifiable {
    let id = UUID()
    let agentId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let lastActiveAt: Date?
    let sessionCount: Int
}

struct SessionsSummary {
    let agents: [AgentSessionInfo]
    let totalInput: Int
    let totalOutput: Int
    let totalTokens: Int
    let totalSessions: Int
}
