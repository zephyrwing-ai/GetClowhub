import Foundation
import Combine
import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
                // Must equal `AppSettings.gatewayPort` default — a drift here lets the
                // WS connect a dead port while the UI still shows the service running.
                let defaultPort = 18789
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let configPath = "\(homeDir)/.openclaw/openclaw.json"
                guard let data = FileManager.default.contents(atPath: configPath),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let gateway = dict["gateway"] as? [String: Any] else {
                    return (port: defaultPort, authToken: "")
                }
                let port = gateway["port"] as? Int ?? defaultPort
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
        // 4. Mirror updates from the store back into the published sidebar
        //    list. The store's debounced writes (assistant streaming, lazy
        //    save of newly-created sessions) land asynchronously; without
        //    this sink the sidebar would lag behind disk until the next
        //    explicit rebuild.
        chatSessionStore.$index
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildSessionsMirror()
            }
            .store(in: &cancellables)
        // 5. Recompute `isSendingMessage` whenever the user switches agent
        //    or the foreground task set changes, AND lazy-load that agent's
        //    most-recent session messages if `restoreActiveSessionsFromStore`
        //    skipped it at startup (only the initially-visible agent gets
        //    eager-loaded — every other agent's messages are parsed the
        //    first time the user switches into it).
        //
        //    Switching session is handled inline in `switchSession` /
        //    `createNewSession` / `promoteNextSession` (since those mutate
        //    `selectedSessionIdByAgent` dict in-place — SwiftUI doesn't
        //    publish per-key dict mutations reliably).
        Publishers.CombineLatest($selectedAgentId, $foregroundTaskIds)
            .receive(on: RunLoop.main)
            .sink { [weak self] agentId, _ in
                guard let self = self else { return }
                self.ensureMessagesLoaded(forAgent: agentId)
                self.recomputeIsSendingMessage()
            }
            .store(in: &cancellables)
        // 6. Persist updates landing in inactive sessions (background
        //    streaming). Same debounce window as the active sink so
        //    streaming completions in a hidden session still hit disk —
        //    otherwise the user sees the old state until next switch.
        $chatMessagesByInactiveSession
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] dict in
                self?.persistInactiveSessions(from: dict)
            }
            .store(in: &cancellables)
        // 7. App Nap suppression — when ANY task is in flight, mark the
        //    process as doing user-initiated work so macOS doesn't
        //    coalesce our timers / throttle networking / defer
        //    callbacks. Without this, hiding the app while a long task
        //    streams causes:
        //      - ThinkingIndicator timer ticks merged to ~1 min intervals
        //      - timeoutTask poll skipped (10s → arbitrary)
        //      - stream callback delivery delayed when receiving deltas
        //    Energy cost is the trade-off — only held while tasks are
        //    actually running, released the moment all tasks finish.
        Publishers.CombineLatest($foregroundTaskIds, $backgroundTaskIds)
            .map { !$0.isEmpty || !$1.isEmpty }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] anyActive in
                self?.updateActivityAssertion(active: anyActive)
            }
            .store(in: &cancellables)
        // 8. macOS system sleep / wake observers. When the user closes
        //    the lid or the Mac sleeps, all timers and network callbacks
        //    are frozen — including our WS receive callback. On wake,
        //    the WS may have been silently closed by the gateway side
        //    (idle timeout) but the client doesn't immediately notice
        //    until the next send fails. We pre-empt this by forcing a
        //    reconnect on wake, so any in-flight task gets a fresh
        //    eventStream as fast as possible (and our recover-via-
        //    history logic can kick in if the run completed during
        //    sleep).
        let nc = NSWorkspace.shared.notificationCenter
        sleepObserver = nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWillSleep()
        }
        wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemDidWake()
        }

        // 9. Recover any in-flight chat runs left over from a previous
        //    launch (app crash / force-quit). Fires in the background
        //    once WS connects, walks the persisted run registry, and
        //    pulls completed replies via chat.history.
        recoverInFlightRunsOnLaunch()
    }

    /// Sleep/wake observer tokens — removed in deinit to avoid leaking
    /// the listener after the view model is gone. macOS keeps strong
    /// refs to the observer block so even without weak self this would
    /// hold the VM alive forever.
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private func handleSystemWillSleep() {
        chatLog.info("System will sleep — flushing in-flight task state")
        // Persist any in-memory updates so a worst-case "lid closed +
        // Mac unplugged" survives. The persist sinks are debounced
        // (500ms), so we explicitly walk the in-flight sessions and
        // flush them synchronously through ChatSessionStore's flush.
        for (agentId, _) in chatMessagesByAgent {
            flushActiveSession(forAgent: agentId)
        }
    }

    private func handleSystemDidWake() {
        chatLog.info("System did wake — forcing WS reconnect for in-flight tasks")
        // If any task was in flight when we slept, the WS receive
        // callback for it is almost certainly stuck on a dead socket
        // (gateway side closed during sleep). Forcing a teardown +
        // reconnect makes scheduleReconnect run immediately rather
        // than waiting for the OS to surface the I/O error, which
        // can take 30+ seconds in practice.
        if !foregroundTaskIds.isEmpty || !backgroundTaskIds.isEmpty {
            gatewayClient.disconnect()
            gatewayClient.connect()
        }
    }

    // MARK: - In-Flight Run Persistence

    /// Persisted record of an in-flight chat run, written on chat.send
    /// success and removed on terminal event (completed/cancelled/error/
    /// timeout) or stream cleanup. Survives app crash / force-quit so
    /// the next launch can attempt recovery via `chat.history`.
    ///
    /// Without this, killing the app mid-task leaves the placeholder
    /// stuck at `.loading` or `.background` on disk forever, with no
    /// way to reattach to the gateway-side run (the runId is gone from
    /// memory). The user sees a permanent "Thinking…" / "Running in
    /// background…" UI for a task that's actually long since finished.
    private struct PersistedInFlightRun: Codable {
        let runId: String
        let sessionKey: String
        let msgId: UUID
        let sessionId: UUID
        let agentId: String
        let agentEmoji: String?
        let startedAt: Date
    }

    private var inFlightRunsFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.cc.OpenClawInstaller"
        let dir = appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("chat-sessions")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("in-flight-runs.json")
    }

    private func readInFlightRuns() -> [PersistedInFlightRun] {
        guard let data = try? Data(contentsOf: inFlightRunsFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PersistedInFlightRun].self, from: data)) ?? []
    }

    private func writeInFlightRuns(_ runs: [PersistedInFlightRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(runs) {
            try? data.write(to: inFlightRunsFileURL, options: .atomic)
        }
    }

    /// Append a fresh in-flight record. Called from `sendChatMessage`
    /// right after `chat.send` returns a runId.
    private func registerInFlightRun(runId: String, sessionKey: String, msgId: UUID,
                                      sessionId: UUID, agentId: String, agentEmoji: String?) {
        var runs = readInFlightRuns()
        runs.append(PersistedInFlightRun(
            runId: runId, sessionKey: sessionKey, msgId: msgId,
            sessionId: sessionId, agentId: agentId, agentEmoji: agentEmoji,
            startedAt: Date()
        ))
        writeInFlightRuns(runs)
    }

    /// Remove an in-flight record after the task terminates (any reason
    /// — completed, cancelled, errored, timed out, or stream cleanup).
    private func unregisterInFlightRun(msgId: UUID) {
        var runs = readInFlightRuns()
        runs.removeAll { $0.msgId == msgId }
        writeInFlightRuns(runs)
    }

    /// On app launch, look at leftover entries in `in-flight-runs.json`
    /// — they represent tasks the user started but the app died before
    /// they finished. For each, ask the gateway for the session's last
    /// assistant message (via `chat.history`); if found, update the
    /// disk-side placeholder to `.completed` so the user sees the
    /// recovered reply when they next open the session. If history
    /// has nothing, mark `.timedOut` with an explanatory note.
    ///
    /// Runs as a background Task after WS connects (waits up to 30s).
    /// Doesn't block init or the chat UI.
    private func recoverInFlightRunsOnLaunch() {
        let allEntries = readInFlightRuns()
        guard !allEntries.isEmpty else { return }

        // Freshness guard: anything older than 1 hour is presumed to
        // be either truly lost (gateway no longer running it / no
        // longer in history) or worse — its sessionKey may have been
        // reused since by other channels (DingTalk / Weixin share the
        // same `agent:X:<sid>` namespace). Recovering against a stale
        // entry would attribute someone ELSE's reply to our crashed
        // task. Safer to just mark these timed out and let the user
        // re-send.
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)
        var fresh: [PersistedInFlightRun] = []
        var stale: [PersistedInFlightRun] = []
        for entry in allEntries {
            if entry.startedAt >= cutoff {
                fresh.append(entry)
            } else {
                stale.append(entry)
            }
        }

        // Multi-entry-per-session guard: if the user fired off N sends
        // in the same session before the crash, fetchLastAssistantMessage
        // returns ONE reply (the most recent one gateway completed) but
        // we'd otherwise attribute it to all N placeholders. Recover
        // only the LATEST entry per sessionId; mark earlier ones timed
        // out (their reply, if any, is no longer addressable from
        // history without per-runId metadata).
        var latestBySession: [UUID: PersistedInFlightRun] = [:]
        var supersededByLater: [PersistedInFlightRun] = []
        for entry in fresh {
            if let existing = latestBySession[entry.sessionId] {
                if entry.startedAt > existing.startedAt {
                    supersededByLater.append(existing)
                    latestBySession[entry.sessionId] = entry
                } else {
                    supersededByLater.append(entry)
                }
            } else {
                latestBySession[entry.sessionId] = entry
            }
        }
        let recoverable = Array(latestBySession.values)
        let unrecoverable = stale + supersededByLater

        chatLog.info("In-flight recovery: \(recoverable.count) recoverable, \(unrecoverable.count) marked timed-out (\(stale.count) stale + \(supersededByLater.count) superseded)")

        Task { [weak self] in
            guard let self = self else { return }

            // Stale + superseded: no recovery attempt, straight to timedOut.
            for entry in unrecoverable {
                await self.markEntryTimedOut(entry, reason: .stale)
            }

            // Wait for WS for the recoverable batch.
            let deadline = Date().addingTimeInterval(30)
            while !self.gatewayClient.isConnected && Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            for entry in recoverable {
                await self.recoverSingleInFlightRun(entry)
            }

            // Clear the file — recovered or not, we tried.
            await MainActor.run {
                self.writeInFlightRuns([])
            }
        }
    }

    private enum RecoveryFailReason {
        case stale            // > 1h old, didn't try history
        case superseded       // newer entry exists for same session
        case noHistory        // history fetch returned nothing useful
    }

    private func markEntryTimedOut(_ entry: PersistedInFlightRun, reason: RecoveryFailReason) async {
        await MainActor.run {
            guard var session = self.chatSessionStore.loadSession(id: entry.sessionId),
                  let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
                return
            }
            let msg = session.messages[idx]
            guard msg.taskStatus == .loading || msg.taskStatus == .background else { return }

            let noteText: String
            switch reason {
            case .stale:
                noteText = "Task started over an hour ago and result is no longer recoverable. Please re-send."
            case .superseded:
                noteText = "A more recent task in the same session was recovered instead. Please re-send if needed."
            case .noHistory:
                noteText = "Task was interrupted by app restart. Result could not be recovered."
            }
            let note = String(localized: String.LocalizationValue(noteText), bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty
                ? note
                : msg.content + "\n\n---\n> ⚠️ " + note

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: content,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: .timedOut,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }

    private func recoverSingleInFlightRun(_ entry: PersistedInFlightRun) async {
        guard var session = chatSessionStore.loadSession(id: entry.sessionId),
              let idx = session.messages.firstIndex(where: { $0.id == entry.msgId }) else {
            chatLog.warning("recovery: session \(entry.sessionId) or msg \(entry.msgId) not found, skipping")
            return
        }

        let msg = session.messages[idx]
        // Only touch placeholders that are still in non-terminal state.
        // If the user already saw it complete in a previous session
        // (somehow), don't overwrite.
        guard msg.taskStatus == .loading || msg.taskStatus == .background else {
            return
        }

        let recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: entry.sessionKey)

        await MainActor.run {
            let newStatus: ChatMessage.TaskStatus
            let newContent: String

            if let text = recovered, !text.isEmpty, text.count > msg.content.count {
                // History has more content than the disk placeholder —
                // the run completed gateway-side while we were dead.
                newStatus = .completed
                newContent = text
                chatLog.info("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) → restored \(text.count) chars")
            } else {
                // Nothing useful — mark timed out with note so the user
                // knows the previous run was lost and can resend.
                newStatus = .timedOut
                let note = String(localized: "Task was interrupted by app restart. Result could not be recovered.",
                                  bundle: LanguageManager.shared.localizedBundle)
                newContent = msg.content.isEmpty
                    ? note
                    : msg.content + "\n\n---\n> ⚠️ " + note
                chatLog.warning("recovery: session \(entry.sessionId.uuidString.prefix(8)) msg \(entry.msgId.uuidString.prefix(8)) — no usable history, marked timed out")
            }

            session.messages[idx] = ChatMessage(
                role: .assistant,
                content: newContent,
                agentId: msg.agentId,
                agentEmoji: msg.agentEmoji,
                taskStatus: newStatus,
                id: entry.msgId,
                timestamp: msg.timestamp
            )
            session.updatedAt = Date()
            self.chatSessionStore.saveSession(session)

            // Mirror into in-memory state if this session happens to be
            // currently loaded for an agent — otherwise the user would
            // see the stale state until they switched away and back.
            if self.selectedSessionIdByAgent[entry.agentId] == entry.sessionId,
               var messages = self.chatMessagesByAgent[entry.agentId],
               let memIdx = messages.firstIndex(where: { $0.id == entry.msgId }) {
                messages[memIdx] = session.messages[idx]
                self.chatMessagesByAgent[entry.agentId] = messages
            }
        }
    }

    /// Token returned by `ProcessInfo.beginActivity`. nil when no
    /// assertion is currently held. Released via `endActivity` when the
    /// last in-flight task settles.
    private var activityToken: NSObjectProtocol?

    // MARK: - Tunable chat thresholds (UserDefaults-backed)

    /// Seconds of zero WebSocket traffic before declaring a task timed
    /// out. Default 3600 (1 hour). Override with
    /// `defaults write com.cc.OpenClawInstaller chat.inactivityTimeoutSeconds <N>`
    /// (a settings UI can come later).
    var inactivityTimeoutSeconds: TimeInterval {
        let raw = UserDefaults.standard.integer(forKey: "chat.inactivityTimeoutSeconds")
        return raw > 0 ? TimeInterval(raw) : 3600
    }

    /// Seconds an in-flight foreground task spins before the
    /// ThinkingIndicator auto-flips it to background (unlocking the input).
    /// Auto-background is OFF by default in this build: the product is a
    /// synchronous human-in-the-loop flow (generate → review → send), so a
    /// task stays foreground until it finishes or is cancelled — no
    /// auto-background, fewer multi-task edge cases. A POSITIVE UserDefaults
    /// value under `chat.autoBackgroundAfterSeconds` opts back in; 0/negative
    /// (or unset) keeps it off.
    var autoBackgroundAfterSeconds: Int? {
        let key = "chat.autoBackgroundAfterSeconds"
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let val = UserDefaults.standard.integer(forKey: key)
        return val > 0 ? val : nil
    }

    /// Begin / end the App Nap suppression assertion based on whether
    /// any foreground or background task is in flight. Idempotent —
    /// repeated calls with the same `active` value are no-ops.
    private func updateActivityAssertion(active: Bool) {
        if active && activityToken == nil {
            // .userInitiated suppresses App Nap + timer coalescing for
            // our process without preventing system sleep (closing the
            // lid still puts the Mac to sleep — that's handled by the
            // willSleep / didWake observers separately).
            activityToken = ProcessInfo.processInfo.beginActivity(
                options: .userInitiated,
                reason: "Streaming chat response (in-flight task)"
            )
            chatLog.info("App Nap suppression engaged")
        } else if !active, let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
            chatLog.info("App Nap suppression released")
        }
    }

    /// Mirror updates from `chatMessagesByInactiveSession` to disk. Used
    /// when a streaming task completes for a session the user is not
    /// currently viewing — without this, the on-disk file stays at
    /// `.loading` (or whatever state it was in at the moment of switch)
    /// until the user navigates back.
    ///
    /// We deliberately do NOT evict entries from
    /// `chatMessagesByInactiveSession` here even when they have no more
    /// in-flight tasks. Eviction would race with `saveSessionDebounced`
    /// (it queues; the actual disk write happens later) — if the user
    /// flips back to a just-evicted session before the queued write
    /// flushes, `switchSession`'s disk-fallback path reads stale data
    /// and the assistant's reply appears to vanish. The cost of NOT
    /// evicting is one extra `[ChatMessage]` per session in memory,
    /// which is negligible; entries get reclaimed naturally when the
    /// user navigates back into the session (`switchSession`'s
    /// `removeValue(forKey:)`).
    private func persistInactiveSessions(from dict: [UUID: [ChatMessage]]) {
        for (sid, messages) in dict where !messages.isEmpty {
            // `loadSession` is now cache-backed; in the streaming-update
            // hot path it returns from memory (the cache was warmed when
            // the user opened this session originally), so this is no
            // longer a full disk parse on every debounce fire.
            guard var session = chatSessionStore.loadSession(id: sid) else { continue }
            let memMessages = Self.stripStaleLoadingPlaceholders(messages)
            // Cheap skip: if the trailing message's id+status+content-length
            // already matches what's on (cached) disk, don't queue a write.
            // Mirror of the same guard in `persistChangedSessions` — covers
            // the case where streaming has paused but the sink keeps firing
            // because of unrelated map mutations elsewhere.
            if session.messages.count == memMessages.count,
               session.messages.last?.id == memMessages.last?.id,
               session.messages.last?.taskStatus == memMessages.last?.taskStatus,
               session.messages.last?.content.count == memMessages.last?.content.count {
                continue
            }
            session.messages = memMessages
            session.updatedAt = Date()
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: memMessages)
            }
            chatSessionStore.saveSessionDebounced(session)
        }
    }

    deinit {
        // System sleep/wake observers — must remove explicitly,
        // NSWorkspace retains the observer block. Same for App Nap
        // assertion: leaking the token leaks the assertion (system
        // would think we still have work to do).
        let nc = NSWorkspace.shared.notificationCenter
        if let sleep = sleepObserver { nc.removeObserver(sleep) }
        if let wake = wakeObserver { nc.removeObserver(wake) }
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
        }
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

    /// Gateway `Main` lane concurrency cap — the number of agent runs the
    /// backend will execute in parallel before the rest start queueing.
    /// Read from `agents.defaults.maxConcurrent` in `~/.openclaw/openclaw.json`;
    /// falls back to the gateway's own default (4) when missing.
    ///
    /// Re-read whenever `loadAvailableAgents` runs so config edits flow
    /// through without an app restart.
    @Published var maxConcurrentTasks: Int = 4

    /// Number of foreground tasks currently in flight across all visible
    /// and inactive sessions. Mirrors `foregroundTaskIds.count` but
    /// exposed as a stable computed property so views can observe via
    /// `$foregroundTaskIds` without reading the underlying set directly.
    var concurrentForegroundCount: Int { foregroundTaskIds.count }

    /// Total tasks (foreground + background) currently in flight. Used by
    /// the chat header's concurrency badge — gateway's Main lane cap
    /// applies to both kinds (a `.background` task still occupies a slot
    /// on the LLM proxy), so the badge needs to count both to give the
    /// user an accurate "how close to the queueing cutoff am I" picture.
    var concurrentTaskCount: Int { foregroundTaskIds.count + backgroundTaskIds.count }
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
        case market = "Marketplace"     // skill / agent marketplace (was sidebarMode)
        case tasksLogs = "Tasks/Logs"   // combined Cron + Logs view
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
            case .market: return "storefront"
            case .tasksLogs: return "checklist"
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
        editedActiveServiceSource = settings.settings.activeServiceSource
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
                // Filter by membership allowed models if available. Case-insensitive
                // to absorb backend ↔ preset casing drift (e.g. `MiniMax-M2.7-highspeed`
                // vs `minimax-m2.7-highspeed`); see MembershipManager.applyKeyToConfig.
                let models: [PresetModel]
                if let allowedModels = membershipManager?.membership?.models, !allowedModels.isEmpty {
                    let allowedLowercased = Set(allowedModels.map { $0.lowercased() })
                    models = allPresetModels.filter { allowedLowercased.contains($0.id.lowercased()) }
                } else {
                    models = allPresetModels
                }
                #else
                let models = allPresetModels
                #endif
                AppSettingsManager.writeGetClawHubProvider(apiKey: editedGetClawHubApiKey, models: models, baseUrl: baseUrl, activate: true)
            }
            settings.loadFromFile()
            syncEditedFieldsFromSettings()
            loadAvailableAgents()
            await loadModels()
            await loadModelsForSettings()
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
    @Published var removingSkillName: String?

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

    static func canRemoveSkill(_ skill: SkillInfo) -> Bool {
        skill.source != "openclaw-bundled"
    }

    func removeSkill(_ skill: SkillInfo) async {
        guard Self.canRemoveSkill(skill) else {
            showErrorMessage("Bundled skills cannot be removed")
            return
        }

        removingSkillName = skill.name
        let scopeFlag = skill.source == "openclaw-workspace" ? "" : " -g"
        let command = "npx skills remove \(Self.shellQuote(skill.name))\(scopeFlag) -y"
        let output = await openclawService.runCommand(
            "(\(command) 2>&1 && echo __OPENCLAW_SKILL_REMOVE_OK__) | sed 's/\\x1b\\[[0-9;]*m//g'",
            timeout: 120
        )
        removingSkillName = nil

        if output?.contains("__OPENCLAW_SKILL_REMOVE_OK__") == true {
            await loadSkills()
            showSuccessMessage("Removed skill \(skill.name)")
        } else {
            let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
            showErrorMessage("Failed to remove \(skill.name): \(trimmed?.isEmpty == false ? trimmed! : "unknown error")")
        }
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

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

    /// Strip transient in-flight placeholders with no content. These are
    /// only meaningful while a chat reply is actively streaming — if one
    /// survives onto disk (e.g. the user force-quit the app, or the
    /// `cancel` path's status-flip got coalesced into a "no-op" persist
    /// by a stale equality check), reopening the session would otherwise
    /// resurrect the spinner ("Thinking…" for `.loading`, "Running in
    /// background…" for `.background`) and look like the assistant is
    /// working on a message that no longer exists.
    ///
    /// Covers both statuses; before, only `.loading + empty` was stripped,
    /// so a `.background + empty` placeholder (left behind when a
    /// session was deleted / switched away from with bg in flight, and
    /// the in-memory stash later got lost) would persist forever and
    /// render as "Running in background…" with no actual task behind it.
    private static func stripStaleLoadingPlaceholders(_ messages: [ChatMessage]) -> [ChatMessage] {
        return messages.filter {
            !(($0.taskStatus == .loading || $0.taskStatus == .background)
              && $0.content.isEmpty)
        }
    }

    /// Load `agentId`'s active session messages into `chatMessagesByAgent`
    /// if they haven't been parsed yet. Called from the `selectedAgentId`
    /// sink so switching to an agent that was deferred at startup parses
    /// its session on first access. Cache hit returns instantly; cache
    /// miss kicks off an async load (with `loadingSessionIds` flipped to
    /// flag the view) so the main thread isn't blocked on a big decode.
    private func ensureMessagesLoaded(forAgent agentId: String) {
        guard chatMessagesByAgent[agentId] == nil,
              let sid = selectedSessionIdByAgent[agentId] else {
            return
        }
        if let cached = chatSessionStore.cachedSession(id: sid) {
            chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(cached.messages)
            return
        }
        // Cold path — async decode.
        loadingSessionIds.insert(sid)
        Task { [weak self] in
            guard let self = self else { return }
            let target = await self.chatSessionStore.loadSessionAsync(id: sid)
            await MainActor.run {
                // Bail if the user has switched agent again in the
                // meantime — we don't want to clobber their current view.
                guard self.selectedAgentId == agentId,
                      self.selectedSessionIdByAgent[agentId] == sid else {
                    self.loadingSessionIds.remove(sid)
                    return
                }
                if let target = target {
                    self.chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(target.messages)
                }
                self.loadingSessionIds.remove(sid)
            }
        }
    }

    /// On launch, restore active sessions for each agent.
    ///
    /// Two-phase load:
    /// - **Eager** (synchronous, on main thread): load the currently-selected
    ///   agent's most-recent session. This is the one the user sees first
    ///   when the chat tab opens, so blocking the main thread for this one
    ///   parse is acceptable — anything else and the UI flashes empty.
    /// - **Lazy** (in a Task): note the session-id for every other agent so
    ///   the sidebar can show them and `selectedSessionIdByAgent` is
    ///   populated, but DON'T load their message bodies yet. Those parse
    ///   on demand when the user switches to that agent (cheap thanks to
    ///   the ChatSessionStore cache hitting once they've loaded once).
    ///
    /// Previously this iterated every agent synchronously and parsed each
    /// agent's full most-recent session, so users with several agents felt
    /// startup as 5+ blocking JSON decodes on the main thread before the
    /// chat view rendered anything.
    private func restoreActiveSessionsFromStore() {
        let currentAgent = selectedAgentId
        for (agentId, metas) in sessionsByAgent {
            guard let mostRecent = metas.first else { continue }
            selectedSessionIdByAgent[agentId] = mostRecent.id
            // Only synchronously parse messages for the visible agent.
            if agentId == currentAgent,
               let session = chatSessionStore.loadSession(id: mostRecent.id) {
                chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(session.messages)
            }
            // Non-visible agents: leave chatMessagesByAgent[agentId] unset.
            // It'll be populated lazily by switchSession the first time the
            // user clicks into that agent — at which point the parse cost
            // is paid once, then cached.
        }
    }

    /// Mirror every agent's in-memory messages back to its active session on
    /// disk. Called from a debounced sink, so token-by-token streaming
    /// produces one write per ~500ms idle window. Lazily creates a session
    /// the first time an agent gets a message.
    private func persistChangedSessions(from dict: [String: [ChatMessage]]) {
        for (agentId, messages) in dict where !messages.isEmpty {
            let sessionId = ensureActiveSessionId(forAgent: agentId, seedMessages: messages)
            // Start from the on-disk copy when one exists (preserves
            // pin/archive state) or mint a fresh in-memory shell otherwise.
            let loaded = chatSessionStore.loadSession(id: sessionId)
            var session = loaded ?? ChatSession(id: sessionId, agentId: agentId, messages: messages)

            // Strip stale .loading + empty placeholders before comparing
            // to disk. We never want to persist a placeholder — and the
            // disk side might already have one from a previous app launch
            // that crashed before the placeholder got updated.
            let memMessages = Self.stripStaleLoadingPlaceholders(messages)
            let diskMessages = loaded.map { Self.stripStaleLoadingPlaceholders($0.messages) } ?? []

            // Skip the write only when disk already holds the same trailing
            // state. The check is gated on `loaded != nil` because a
            // freshly-minted pending session (from createNewSession) loads
            // to nil — the fallback constructor pre-populates `messages`,
            // which would make the equality check trivially pass and the
            // first message would never persist.
            //
            // Compare task status + content length in addition to id, so
            // that an in-place status flip (.loading → .cancelled, or a
            // streaming delta appending text) is not coalesced into a
            // no-op write — that was the source of the "session always
            // looks like it's thinking" bug (the spinner placeholder got
            // saved at .loading, then the cancel update was skipped, and
            // disk kept the .loading state forever).
            if let loaded = loaded,
               diskMessages.count == memMessages.count,
               diskMessages.last?.id == memMessages.last?.id,
               diskMessages.last?.taskStatus == memMessages.last?.taskStatus,
               diskMessages.last?.content.count == memMessages.last?.content.count,
               !loaded.title.isEmpty {
                continue
            }

            session.messages = memMessages
            session.updatedAt = Date()
            // Auto-derive title once, only while still on the placeholder.
            if session.title == ChatSession.defaultTitle {
                session.title = ChatSession.deriveTitle(from: memMessages)
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
        let oldSid = selectedSessionIdByAgent[agentId]

        // If the session we're LEAVING has an in-flight task (foreground
        // OR background), we can't just overwrite `chatMessagesByAgent[agentId]`
        // — subsequent stream events would find no msgId to update and
        // silently discard output. Instead, stash the current messages
        // into the inactive map keyed by the old sessionId. Stream
        // handlers know to look there too. When the user returns to
        // that session, we unstash.
        //
        // `hasInflightTask` covers both kinds: a task moved to bg via
        // moveTaskToBackground is still running on the gateway and
        // still needs its placeholder preserved so stream events can
        // land. (Earlier this was `hasForegroundTask` only — bg tasks
        // got silently dropped on session switch.)
        if let oldSid = oldSid, hasInflightTask(inSession: oldSid) {
            chatMessagesByInactiveSession[oldSid] = chatMessagesByAgent[agentId]
        }

        flushActiveSession(forAgent: agentId)
        selectedSessionIdByAgent[agentId] = sessionId

        // Source-of-truth precedence on a session switch:
        //  1. In-memory inactive stash (most current — includes any
        //     streaming that completed while the user was away).
        //  2. ChatSessionStore's LRU cache (warm hit, instant decode).
        //  3. Disk (cold load — kicked off async so we don't freeze the
        //     main thread on a multi-hundred-KB JSON parse). We set a
        //     loading flag the view watches to show a spinner during
        //     this window.
        //
        // IMPORTANT: do NOT `stripStaleLoadingPlaceholders` an in-memory
        // unstash. The strip would remove a still-running .loading + ""
        // placeholder, but the task IS still alive (foregroundTaskIds /
        // taskSessionMap still have its msgId). Once stripped, the next
        // stream event has nowhere to land — findMessage returns nil and
        // the output is silently dropped. The disk path strips because
        // we can't tell a live placeholder from a dead one left over by
        // a previous crash.
        if let stashed = chatMessagesByInactiveSession.removeValue(forKey: sessionId) {
            chatMessagesByAgent[agentId] = stashed
            loadingSessionIds.remove(sessionId)
        } else if let target = chatSessionStore.cachedSession(id: sessionId) {
            chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(target.messages)
            loadingSessionIds.remove(sessionId)
        } else {
            // Cold load — render a loading placeholder while we decode
            // the JSON off the main thread.
            chatMessagesByAgent[agentId] = []
            loadingSessionIds.insert(sessionId)
            Task { [weak self] in
                guard let self = self else { return }
                let target = await self.chatSessionStore.loadSessionAsync(id: sessionId)
                await MainActor.run {
                    // If the user has navigated away again before the
                    // decode finished, drop the result rather than
                    // clobbering whatever they're looking at now.
                    guard self.selectedSessionIdByAgent[agentId] == sessionId else {
                        self.loadingSessionIds.remove(sessionId)
                        return
                    }
                    if let target = target {
                        self.chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(target.messages)
                    }
                    self.loadingSessionIds.remove(sessionId)
                }
            }
        }
        rebuildSessionsMirror()
        recomputeIsSendingMessage()
    }

    /// Update the title of a stored session. Empty / whitespace-only strings
    /// are ignored so we never end up with an unreadable row.
    /// Set when a rewind attempt fails, so the chat view can surface it.
    @Published var rewindError: String?

    /// One-shot channel to push text back into the composer. On a successful
    /// "rewind = edit & resend", we drop the clicked message (and everything
    /// after) and stash its text here; the chat view observes this, copies it
    /// into its `inputText` field, and clears it. Lets the view model drive the
    /// view-owned composer without holding a reference to it.
    @Published var composerPrefill: String?

    /// Rewind = "edit & resend": drop the clicked user message and everything
    /// after it, put its text back in the composer, and move the session's
    /// branch point so the next send REPLACES that turn.
    ///
    /// Implemented entirely CLIENT-SIDE — no gateway protocol method. The
    /// gateway runs locally and re-reads the transcript on each run
    /// (SessionManager.open → fresh file read; the leaf is the file's last
    /// entry), so truncating the local `.jsonl` to before the clicked message
    /// moves the branch point for free. Verified against the gateway's own
    /// SessionManager on real multi-turn transcripts. Rewind is gated to user
    /// bubbles (see ChatBubble); user turns are single transcript entries (no
    /// tool sub-entries), so we anchor by user-message ordinal — robust against
    /// the assistant/tool entry drift that indexing over mixed turns would hit.
    func rewindToMessage(_ message: ChatMessage) {
        let agentId = selectedAgentId
        guard let sessionId = selectedSessionIdByAgent[agentId] else {
            self.rewindError = "没有活动会话，无法回滚"
            return
        }
        let sessionKey = sessionKeyForAgent(agentId, sessionId: sessionId)
        let clientMessages = chatMessagesByAgent[agentId] ?? []
        guard clientMessages.contains(where: { $0.id == message.id }) else {
            self.rewindError = "找不到该消息，无法回滚"
            return
        }
        // Anchor by ordinal among USER messages (rewind only shows on user
        // bubbles). User turns are single transcript entries, so this lines up
        // 1:1 with the transcript's user entries — no drift from assistant/tool
        // sub-entries.
        let userMsgs = clientMessages.filter { $0.role == .user }
        guard let userIdx = userMsgs.firstIndex(where: { $0.id == message.id }) else {
            self.rewindError = "找不到该消息位置，无法回滚"
            return
        }

        Task { @MainActor in
            // 1. Tear down any in-flight run in THIS session (abort each by its
            //    runId + clear tracking) so we never truncate a transcript that's
            //    mid-write and never orphan `isSendingMessage`. Scoped to this
            //    session — other sessions/agents keep running untouched.
            self.cancelTasks(inSession: sessionId)
            _ = await gatewayClient.abortChat(sessionKey: sessionKey)
            // Let the abort + any final transcript write flush before we touch
            // the file.
            try? await Task.sleep(nanoseconds: 250_000_000)

            // 2. Client-side branch: truncate the local transcript to before the
            //    clicked user message (backs the file up first). No gateway call.
            if let err = self.truncateTranscriptForRewind(
                agentId: agentId,
                sessionKey: sessionKey,
                userOrdinal: userIdx,
                clickedText: message.content
            ) {
                self.rewindError = err
                return
            }

            // 3. Mirror locally: drop the clicked message and everything after,
            //    and push its text into the composer to edit/resend.
            if let msgs = self.chatMessagesByAgent[agentId],
               let curIdx = msgs.firstIndex(where: { $0.id == message.id }) {
                self.chatMessagesByAgent[agentId] = Array(msgs.prefix(curIdx))
            }
            self.composerPrefill = message.content
            self.rewindError = nil
        }
    }

    /// Truncate the local session transcript (`<sid>.jsonl`) so the user message
    /// at `userOrdinal` (and everything after) is dropped. Returns an error
    /// string on failure, nil on success. Backs the file up first
    /// (`.jsonl.rewind.<ts>`). This IS the rewind on the gateway side: the next
    /// run re-reads the file and the new last entry becomes the leaf — no
    /// gateway protocol method needed (the gateway is local).
    private func truncateTranscriptForRewind(
        agentId: String,
        sessionKey: String,
        userOrdinal: Int,
        clickedText: String
    ) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(home)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        // Map the UI sessionKey → the gateway transcript's session id.
        guard let data = FileManager.default.contents(atPath: sessionsJsonPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "无法读取 sessions.json"
        }
        // Case-insensitive key match: the client builds sessionKey with Swift's
        // UPPERCASE `UUID.uuidString`, but the gateway stores keys with a
        // LOWERCASE uuid (e.g. agent:main:c4b9d48d-…). An exact match misses.
        let targetKey = sessionKey.lowercased()
        guard let entryVal = root.first(where: { $0.key.lowercased() == targetKey })?.value,
              let entry = entryVal as? [String: Any],
              let gwSessionId = entry["sessionId"] as? String else {
            return "找不到会话转录（sessions.json 无对应条目）"
        }
        let jsonlPath = "\(sessionsDir)/\(gwSessionId).jsonl"
        guard let content = try? String(contentsOfFile: jsonlPath, encoding: .utf8) else {
            return "无法读取会话转录文件"
        }
        let rawLines = content.components(separatedBy: "\n")

        // Line indices of user-role message entries, in order.
        var userLines: [(line: Int, text: String)] = []
        for (i, line) in rawLines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let ld = t.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  (obj["type"] as? String) == "message",
                  let msg = obj["message"] as? [String: Any],
                  (msg["role"] as? String) == "user" else { continue }
            userLines.append((i, Self.jsonlMessageText(msg)))
        }

        // Resolve the cut line: prefer the ordinal (1:1 with user bubbles),
        // validate by content "contains" (the transcript can wrap user text in
        // an envelope), and fall back to nearest content match on any drift.
        let trimmed = clickedText.trimmingCharacters(in: .whitespacesAndNewlines)
        var cutLine: Int? = nil
        if userOrdinal < userLines.count,
           trimmed.isEmpty || userLines[userOrdinal].text.contains(trimmed) {
            cutLine = userLines[userOrdinal].line
        }
        if cutLine == nil, !trimmed.isEmpty {
            let matches = userLines.enumerated().filter { $0.element.text.contains(trimmed) }
            if let nearest = matches.min(by: { abs($0.offset - userOrdinal) < abs($1.offset - userOrdinal) }) {
                cutLine = nearest.element.line
            }
        }
        guard let cut = cutLine else {
            return "无法定位回滚锚点：本地用户消息#\(userOrdinal)/转录\(userLines.count)条"
        }

        // Back up, then keep everything BEFORE the cut line.
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? FileManager.default.copyItem(atPath: jsonlPath, toPath: "\(jsonlPath).rewind.\(ts)")
        let kept = rawLines.prefix(cut).joined(separator: "\n")
        let finalContent = kept.isEmpty ? "" : kept + "\n"
        do {
            try finalContent.write(toFile: jsonlPath, atomically: true, encoding: .utf8)
        } catch {
            return "写入截断后的转录失败：\(error.localizedDescription)"
        }
        return nil
    }

    /// Extract display text from a transcript message entry's `message` object
    /// (`text`, string `content`, or content-block array).
    private static func jsonlMessageText(_ msg: [String: Any]) -> String {
        if let t = msg["text"] as? String { return t }
        if let c = msg["content"] as? String { return c }
        if let blocks = msg["content"] as? [[String: Any]] {
            return blocks.compactMap { ($0["type"] as? String) == "text" ? ($0["text"] as? String) : nil }
                .joined(separator: "\n")
        }
        return ""
    }

    func renameSession(_ sessionId: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.title = trimmed
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
        rebuildSessionsMirror()
    }

    /// Permanently remove a session (file + index entry). If we're deleting
    /// the active session, automatically promote the next-newest session, or
    /// mint an empty one if none remain — never leave the chat view broken.
    func deleteSession(_ sessionId: UUID) {
        let agentId = selectedAgentId
        let wasActive = selectedSessionIdByAgent[agentId] == sessionId
        // Cancel any in-flight task tied to this session BEFORE we drop the
        // file — without this, the run keeps streaming on the gateway with
        // nowhere to land (foregroundTaskIds / taskSessionMap entries
        // become orphans, isSendingMessage stays true forever).
        cancelTasks(inSession: sessionId)
        chatSessionStore.deleteSession(id: sessionId)
        // Drop any stashed in-memory copy too. Otherwise the entry sits in
        // chatMessagesByInactiveSession forever (until app restart), and the
        // 500ms persistInactiveSessions sink keeps firing for it — each tick
        // calls loadSession, gets nil (file is gone), skips. Wasted CPU and
        // memory for a session the user explicitly removed.
        chatMessagesByInactiveSession.removeValue(forKey: sessionId)
        if wasActive {
            promoteNextSession(forAgent: agentId)
        }
        rebuildSessionsMirror()
        recomputeIsSendingMessage()
    }

    /// Toggle pinned state. Pinned sessions float to the top of the sidebar
    /// list regardless of recency.
    func togglePinSession(_ sessionId: UUID) {
        guard var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.isPinned.toggle()
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
        rebuildSessionsMirror()
    }

    /// Mark a session as archived. Archived sessions stay on disk but are
    /// hidden from the default sidebar list. Active session promotion is the
    /// same as delete — we don't want to leave the user staring at a row
    /// that was just hidden.
    func archiveSession(_ sessionId: UUID) {
        let agentId = selectedAgentId
        let wasActive = selectedSessionIdByAgent[agentId] == sessionId
        guard var session = chatSessionStore.loadSession(id: sessionId) else { return }
        session.isArchived = true
        session.updatedAt = Date()
        chatSessionStore.saveSession(session)
        if wasActive {
            promoteNextSession(forAgent: agentId)
        }
        rebuildSessionsMirror()
    }

    /// Export a session to Markdown via NSSavePanel. The file uses the
    /// session title as the default name.
    func exportSession(_ sessionId: UUID) {
        guard let session = chatSessionStore.loadSession(id: sessionId) else { return }
        let markdown = Self.sessionMarkdown(session)
        let panel = NSSavePanel()
        panel.title = "Export Chat Session"
        panel.nameFieldStringValue = "\(session.title.replacingOccurrences(of: "/", with: "_")).md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// After delete/archive of the active session, pick a successor from the
    /// remaining list, or mint a new empty session when nothing's left.
    private func promoteNextSession(forAgent agentId: String) {
        if let next = chatSessionStore.sessions(forAgent: agentId).first {
            selectedSessionIdByAgent[agentId] = next.id
            if let loaded = chatSessionStore.loadSession(id: next.id) {
                chatMessagesByAgent[agentId] = Self.stripStaleLoadingPlaceholders(loaded.messages)
            }
        } else {
            // No surviving sessions — mint a fresh empty session in memory
            // only. Match createNewSession() in deferring the disk write
            // until the user actually types, so an immediately-discarded
            // empty session leaves no trace in the sidebar.
            let new = ChatSession(agentId: agentId)
            selectedSessionIdByAgent[agentId] = new.id
            chatMessagesByAgent[agentId] = []
        }
        recomputeIsSendingMessage()
    }

    private static func sessionMarkdown(_ s: ChatSession) -> String {
        let df = ISO8601DateFormatter()
        var out = "# \(s.title)\n\n"
        out += "_Created: \(df.string(from: s.createdAt))_  \n"
        out += "_Updated: \(df.string(from: s.updatedAt))_\n\n"
        out += "---\n\n"
        for m in s.messages {
            let role = m.role == .user ? "**User**" : "**Assistant**"
            out += "\(role):\n\n\(m.content)\n\n---\n\n"
        }
        return out
    }

    /// Mint a fresh empty session for the current agent and switch to it.
    /// Used by the "+ New Session" sidebar button.
    ///
    /// The session is created in memory only — the disk write is deferred
    /// until the user actually adds a message (handled by
    /// `persistChangedSessions`). This way a "+ New Session" click followed
    /// by an immediate switch to another row leaves no orphan empty session
    /// in the sidebar.
    @discardableResult
    func createNewSession() -> UUID {
        let agentId = selectedAgentId
        let oldSid = selectedSessionIdByAgent[agentId]
        // Symmetric with switchSession: if a task is streaming in the old
        // session (foreground OR background), preserve its message list
        // in the inactive stash so stream events can still find their
        // target. We do NOT cancel.
        if let oldSid = oldSid, hasInflightTask(inSession: oldSid) {
            chatMessagesByInactiveSession[oldSid] = chatMessagesByAgent[agentId]
        }
        flushActiveSession(forAgent: agentId)
        let new = ChatSession(agentId: agentId)
        selectedSessionIdByAgent[agentId] = new.id
        chatMessagesByAgent[agentId] = []
        recomputeIsSendingMessage()
        return new.id
    }

    /// Cancel any pending debounced write for the agent's current session and
    /// commit its in-memory messages to disk synchronously. Safe to call
    /// when there is no active session — it's a no-op.
    ///
    /// Two short-circuits:
    /// - **Pending unsaved session with no content** (created by
    ///   `createNewSession` but never typed in): drop without persisting,
    ///   so the sidebar never sees an empty row.
    /// - **No actual change** vs what's on disk: cancel any pending
    ///   debounced write and bail, so a plain session switch doesn't bump
    ///   `updatedAt` and reorder the sidebar list.
    private func flushActiveSession(forAgent agentId: String) {
        guard let sid = selectedSessionIdByAgent[agentId] else { return }
        let messages = chatMessagesByAgent[agentId] ?? []
        let loaded = chatSessionStore.loadSession(id: sid)

        // Pending session that was minted in memory but never received any
        // input — discard.
        if loaded == nil && messages.isEmpty {
            return
        }

        // Strip .loading + empty placeholders — same rationale as in
        // persistChangedSessions: transient spinners must never hit disk.
        let memMessages = Self.stripStaleLoadingPlaceholders(messages)
        let diskMessages = loaded.map { Self.stripStaleLoadingPlaceholders($0.messages) } ?? []

        // Compare against the on-disk copy. If nothing changed, don't
        // rewrite the file (would bump updatedAt and reorder the list).
        // Include status + content length so an in-place message update
        // (.loading → .cancelled, streaming delta) is not coalesced into
        // a no-op. Was previously only count + last id, which let the
        // cancel-flip be silently dropped.
        let messagesChanged: Bool
        if loaded != nil {
            messagesChanged = diskMessages.count != memMessages.count
                || diskMessages.last?.id != memMessages.last?.id
                || diskMessages.last?.taskStatus != memMessages.last?.taskStatus
                || diskMessages.last?.content.count != memMessages.last?.content.count
        } else {
            messagesChanged = !memMessages.isEmpty
        }

        guard messagesChanged else {
            // Cancel any in-flight debounced write for this id but emit no
            // fresh write of our own.
            chatSessionStore.flush(id: sid, current: nil)
            return
        }

        var current = loaded ?? ChatSession(id: sid, agentId: agentId, messages: memMessages)
        current.messages = memMessages
        current.updatedAt = Date()
        if current.title == ChatSession.defaultTitle {
            current.title = ChatSession.deriveTitle(from: memMessages)
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
    /// True only when the *currently visible* (agent + active session) has
    /// a foreground task in flight. Recomputed via `recomputeIsSendingMessage()`
    /// every time a task is added/removed, or when the user switches agent/
    /// session. Was previously "true if ANY foreground task exists across
    /// agents/sessions", which locked the input in a session that didn't
    /// actually have a task running.
    @Published var isSendingMessage = false
    @Published var foregroundTaskIds: Set<UUID> = []  // message IDs of foreground (blocking) tasks
    @Published var backgroundTaskIds: Set<UUID> = []  // message IDs of background tasks
    var taskAgentMap: [UUID: String] = [:]  // msgId → agentId
    /// msgId → the sessionId the task was started under. Used to (a) route
    /// gateway sessionKey on cancel and (b) decide which UI session "owns"
    /// the spinner / cancel affordance. Both populated together with
    /// `taskAgentMap` in `sendChatMessage`; both cleaned together on any
    /// terminal event (completed / cancelled / timed-out / error).
    var taskSessionMap: [UUID: UUID] = [:]

    /// Messages for sessions the user has navigated AWAY from while a
    /// foreground task was still streaming. Keyed by sessionId. The
    /// session's stream events keep updating this map even though the
    /// session isn't visible — so when the user navigates back, the
    /// result (or in-progress streaming) is already there.
    ///
    /// Cleared on switch-back into the session (entry is moved to
    /// `chatMessagesByAgent[agentId]`) and on session delete.
    /// Persisted via a parallel debounced save sink so on-disk state
    /// catches up with completions that landed while the session was
    /// inactive.
    @Published var chatMessagesByInactiveSession: [UUID: [ChatMessage]] = [:]

    /// Sessions whose messages are being lazy-loaded from disk in the
    /// background. The chat view watches this set so it can render a
    /// "loading…" placeholder during the cold-load window instead of
    /// flashing an empty thread. Entries are added by `switchSession` /
    /// `ensureMessagesLoaded` when they take the async path (cache miss)
    /// and removed when the load resolves.
    @Published var loadingSessionIds: Set<UUID> = []

    /// Whether the currently selected agent has any foreground task running
    /// — across all its sessions. Used by the agent picker to badge agents
    /// that are working in the background.
    var isCurrentAgentSending: Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == selectedAgentId })
    }

    /// Check if a specific agent has a foreground task running (any session).
    func isAgentExecuting(_ agentId: String) -> Bool {
        foregroundTaskIds.contains(where: { taskAgentMap[$0] == agentId })
    }

    /// Check if a specific session has a foreground task running. Used by
    /// the input bar to decide whether to disable typing (background
    /// tasks INTENTIONALLY unlock the input — moving to bg is the user
    /// saying "don't block me on this").
    func hasForegroundTask(inSession sessionId: UUID) -> Bool {
        foregroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
    }

    /// Check if a specific session has ANY in-flight task — foreground OR
    /// background. Used wherever we care about "is the gateway still
    /// running work on behalf of this session" regardless of whether the
    /// spinner is locking the UI:
    ///   - sidebar activity dot (orange) — shows even for bg tasks so the
    ///     user remembers they have something cooking over there
    ///   - `switchSession` / `createNewSession` stash decision — bg
    ///     tasks need the same in-memory preservation as fg ones, or
    ///     their stream events have nowhere to land after navigation
    ///   - `deleteSession` cancel sweep — both kinds become orphans on
    ///     the gateway if we don't cancel them
    func hasInflightTask(inSession sessionId: UUID) -> Bool {
        foregroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
            || backgroundTaskIds.contains(where: { taskSessionMap[$0] == sessionId })
    }

    /// Recompute `isSendingMessage` based on whether the currently visible
    /// session has any foreground task in flight. Must be called whenever
    /// `foregroundTaskIds`, `selectedAgentId`, `selectedSessionIdByAgent[agentId]`,
    /// or `taskSessionMap` changes — otherwise the input lock won't track
    /// the visible session correctly.
    private func recomputeIsSendingMessage() {
        guard let sid = selectedSessionIdByAgent[selectedAgentId] else {
            isSendingMessage = false
            return
        }
        isSendingMessage = hasForegroundTask(inSession: sid)
    }

    /// Cancel every task (fg + bg) currently bound to `sessionId`. Only
    /// used by `deleteSession` — deleting a session while tasks are
    /// running on it makes no sense (the destination for the output is
    /// disappearing). For switchSession / createNewSession we instead
    /// stash the session's state into `chatMessagesByInactiveSession` so
    /// tasks can keep running and route output to the right place when
    /// the user comes back.
    ///
    /// Includes `.background` tasks: they're also bound to a sessionId
    /// via `taskSessionMap`, and if the session is deleted they'd become
    /// gateway-side orphans the same as foreground ones.
    private func cancelTasks(inSession sessionId: UUID) {
        let fg = foregroundTaskIds.filter { taskSessionMap[$0] == sessionId }
        let bg = backgroundTaskIds.filter { taskSessionMap[$0] == sessionId }
        for msgId in fg.union(bg) {
            cancelChat(msgId)
        }
    }

    /// Look up a message by id in whichever bucket currently holds it —
    /// the active per-agent map, or the inactive-sessions map for tasks
    /// whose owning session the user has navigated away from. Returns
    /// the message (read-only). Stream handlers use this for status
    /// checks ("don't overwrite a .cancelled message with a delta")
    /// without having to know where the message lives.
    private func findMessage(byId msgId: UUID) -> ChatMessage? {
        for messages in chatMessagesByAgent.values {
            if let msg = messages.first(where: { $0.id == msgId }) {
                return msg
            }
        }
        if let sessionId = taskSessionMap[msgId],
           let msg = chatMessagesByInactiveSession[sessionId]?.first(where: { $0.id == msgId }) {
            return msg
        }
        return nil
    }
    @Published var selectedAgentId: String = "main"
    @Published var availableAgents: [AgentOption] = [AgentOption(id: "main", name: "main", emoji: "🤖", description: "", model: "", division: "")]

    // Agent Settings Panel state
    @Published var agentSettingsOpen: Bool = false
    @Published var selectedAgentDetail: SubAgentInfo?
    @Published var availableModelsForSettings: [ModelOption] = []

    /// Internal agents managed by the app, hidden from user-facing lists.
    static let internalAgentIds: Set<String> = ["help-assistant"]

    /// Resolve an agent's on-disk workspace directory, faithfully replicating
    /// openclaw's `resolveAgentWorkspaceDir(cfg, agentId)`:
    ///   1. an explicit `agents.list[].workspace` always wins
    ///   2. otherwise the *default agent* — the first entry with `default: true`,
    ///      else the first entry in `agents.list`, else "main" — uses
    ///      `agents.defaults.workspace` (or the bare `~/.openclaw/workspace`)
    ///   3. every other agent uses `~/.openclaw/workspace-<id>`
    ///
    /// Why this exists: the old code hardcoded "main → ~/.openclaw/workspace",
    /// which is only correct when "main" happens to be the default agent. When
    /// another agent is listed first (e.g. `commander`), the runtime resolves
    /// main to `~/.openclaw/workspace-main`, but the UI kept pointing at the
    /// stale bare `workspace` dir — so the file browser, terminal, persona
    /// editor and IDENTITY.md parsing all looked at the wrong folder.
    static func resolveAgentWorkspace(_ agentId: String, config: [String: Any]) -> String {
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        let agentsSection = config["agents"] as? [String: Any]
        let list = agentsSection?["list"] as? [[String: Any]] ?? []

        // 1. explicit per-agent workspace
        if let entry = list.first(where: { ($0["id"] as? String) == agentId }),
           let ws = (entry["workspace"] as? String)?.trimmingCharacters(in: .whitespaces),
           !ws.isEmpty {
            return (ws as NSString).expandingTildeInPath
        }

        // 2. default agent id: first default:true, else first list entry, else "main"
        let defaultAgentId: String =
            (list.first(where: { ($0["default"] as? Bool) == true })?["id"] as? String)
            ?? (list.first?["id"] as? String)
            ?? "main"

        if agentId == defaultAgentId {
            if let defWs = ((agentsSection?["defaults"] as? [String: Any])?["workspace"] as? String)?
                .trimmingCharacters(in: .whitespaces), !defWs.isEmpty {
                return (defWs as NSString).expandingTildeInPath
            }
            return (baseDir as NSString).appendingPathComponent("workspace")
        }

        // 3. non-default agent
        return (baseDir as NSString).appendingPathComponent("workspace-\(agentId)")
    }

    /// Disk-reading convenience: parses `~/.openclaw/openclaw.json` then defers
    /// to `resolveAgentWorkspace(_:config:)`. Safe to call from view-layer
    /// computed properties (openclaw.json is tiny).
    static func resolveAgentWorkspace(_ agentId: String) -> String {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let config = FileManager.default.contents(atPath: configPath)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        return resolveAgentWorkspace(agentId, config: config)
    }

    func loadAvailableAgents() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let baseDir = NSString("~/.openclaw").expandingTildeInPath
        var agents: [AgentOption] = []

        let previousSelectedAgentId = selectedAgentId

        // Ensure commander exists in openclaw.json before loading
        Self.ensureCommanderInConfig(configPath: configPath, baseDir: baseDir)

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any] {
            // Pick up gateway concurrency cap from agents.defaults.maxConcurrent.
            // Used by the chat header's concurrent-task badge so the user can
            // see how close they are to gateway queuing kicking in.
            if let defaults = agentsSection["defaults"] as? [String: Any],
               let max = defaults["maxConcurrent"] as? Int, max > 0 {
                maxConcurrentTasks = max
            } else {
                maxConcurrentTasks = 4
            }
        }

        if let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let agentsSection = json["agents"] as? [String: Any],
           let agentList = agentsSection["list"] as? [[String: Any]] {
            for entry in agentList {
                guard let agentId = entry["id"] as? String else { continue }

                // Skip internal agents (commander, help-assistant) from user-facing lists
                if Self.internalAgentIds.contains(agentId) { continue }

                // Determine workspace path for this agent (faithful to openclaw's
                // resolveAgentWorkspaceDir — NOT a hardcoded "main → workspace").
                let workspace = Self.resolveAgentWorkspace(agentId, config: json)

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
            let mainWorkspace = Self.resolveAgentWorkspace("main")
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

    /// Compose the gateway sessionKey for a given (agent, sessionId) pair.
    ///
    /// Previously this was hardcoded `"agent:<id>:main"` for every session —
    /// so multiple UI "sessions" for the same agent all shared one server
    /// conversation context, leaking memory between them (you'd ask about
    /// X in session A, switch to session B, and the assistant would still
    /// "remember" X). Including the sessionId in the key isolates each UI
    /// session into its own gateway thread.
    private func sessionKeyForAgent(_ agentId: String, sessionId: UUID) -> String {
        return "agent:\(agentId):\(sessionId.uuidString)"
    }

    /// Extensions that the gateway accepts as image attachments (via base64 in `content` field).
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    /// True iff `url` is an existing directory. Cheap stat; called per-attachment.
    private static func urlIsDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Process attachments: images → base64 attachments array; other files → pass file path in message;
    /// directories → pass folder path with a "folder" hint so the agent picks list_dir over read_file.
    /// Returns (imageAttachments, textToAppend).
    private func processAttachments(_ urls: [URL]) -> (attachments: [[String: Any]], inlineText: String) {
        var imageAttachments: [[String: Any]] = []
        var textParts: [String] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent
            let isDir = Self.urlIsDirectory(url)

            // Directories → never read as image, never base64; just inline the path
            // with an explicit "folder" hint so the AI agent reaches for list_dir /
            // glob tools rather than read_file. Must run before the image branch
            // because the path might literally end in `.png` and still be a folder.
            if isDir {
                os_log(.info, "processAttachments: directory '%{public}@' → passing folder path", fileName)
                textParts.append("Attached folder: \(url.path)")
                continue
            }

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
        let newMsg = ChatMessage(
            role: .assistant, content: content,
            agentId: agentId, agentEmoji: agentEmoji,
            taskStatus: status, id: msgId
        )
        // Route to wherever this msgId currently lives. The task may have
        // started in the (then-visible) active session and migrated to
        // chatMessagesByInactiveSession when the user navigated away —
        // stream events still need to find it.
        if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByAgent[agentId] ?? []
            messages[idx] = newMsg
            chatMessagesByAgent[agentId] = messages
            logChat("UPDATE_MSG (active): agent=\(agentId), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            var messages = chatMessagesByInactiveSession[sessionId] ?? []
            messages[idx] = newMsg
            chatMessagesByInactiveSession[sessionId] = messages
            logChat("UPDATE_MSG (inactive): session=\(sessionId.uuidString.prefix(8)), contentLen=\(content.count), status=\(status), totalMsgs=\(messages.count)")
            return
        }
        logChat("UPDATE_FAILED: agent=\(agentId), msgId=\(msgId.uuidString.prefix(8)) NOT FOUND in active or inactive!")
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
        // Bind the run to the agent's currently-active session. `ensureActiveSessionId`
        // mints one lazily if the agent has never had a session before, so this is
        // always non-nil after the call.
        let currentSessionId = ensureActiveSessionId(forAgent: currentAgentId,
                                                     seedMessages: chatMessagesByAgent[currentAgentId] ?? [])
        let sessionKey = sessionKeyForAgent(currentAgentId, sessionId: currentSessionId)

        // Insert a placeholder assistant message for streaming updates
        let msgId = UUID()
        let placeholderMsg = ChatMessage(role: .assistant, content: "", agentId: currentAgentId, agentEmoji: currentAgentEmoji, taskStatus: .loading, id: msgId)
        chatMessagesByAgent[currentAgentId, default: []].append(placeholderMsg)
        logChat("PLACEHOLDER: agent=\(currentAgentId), msgId=\(msgId.uuidString.prefix(8)), totalMsgs=\(chatMessagesByAgent[currentAgentId]?.count ?? 0)")

        // Track as foreground task — bound to BOTH agent and session so we can
        // (a) route the cancel/abort to the right gateway sessionKey and
        // (b) decide which UI session owns this spinner.
        foregroundTaskIds.insert(msgId)
        taskAgentMap[msgId] = currentAgentId
        taskSessionMap[msgId] = currentSessionId
        recomputeIsSendingMessage()

        // Check gateway connection. Prefer the gateway's own rejection reason
        // (e.g. NOT_PAIRED / DEVICE_IDENTITY_REQUIRED, token mismatch) so the user
        // can act on it; only fall back to the generic message when we never got
        // a server response (TCP failed / handshake never reached the auth step).
        guard gatewayClient.isConnected else {
            let generic = String(localized: "Gateway is not connected. Please check the service status.", bundle: LanguageManager.shared.localizedBundle)
            let errorMsg: String
            if let lastErr = gatewayClient.lastConnectError {
                let detail = lastErr.detailCode.map { " (\($0))" } ?? ""
                errorMsg = "\(generic)\n[\(lastErr.code)\(detail)] \(lastErr.message)"
            } else {
                errorMsg = generic
            }
            updateMessage(msgId: msgId, content: errorMsg, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
            foregroundTaskIds.remove(msgId)
            taskAgentMap.removeValue(forKey: msgId)
            taskSessionMap.removeValue(forKey: msgId)
            recomputeIsSendingMessage()
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
            taskSessionMap.removeValue(forKey: msgId)
            recomputeIsSendingMessage()
            return
        }

        activeChatRuns[msgId] = runId
        chatLog.info("chat.send ok: runId=\(runId), subscriberId=\(subscriberId), bgTasks=\(self.backgroundTaskIds.count)")

        // Persist the run so we can recover via chat.history if the
        // app dies before the stream completes (force-quit, crash, OOM).
        // Removed in the defer block below on normal stream exit, so
        // typical runs never leave a stale entry.
        registerInFlightRun(
            runId: runId,
            sessionKey: sessionKey,
            msgId: msgId,
            sessionId: currentSessionId,
            agentId: currentAgentId,
            agentEmoji: currentAgentEmoji
        )

        // Abandonment safety net: only triggers when NO inbound traffic at all for the
        // entire `inactivityLimit` window. Modeled after Claude's API/SSE behavior — we
        // never want to declare a task failed purely because deltas came infrequently
        // (deep-thinking + long tools can be naturally silent for many minutes). The
        // 30s client heartbeat already proves WS liveness independently; this timer is
        // pure defense-in-depth for genuinely abandoned runs.
        //
        // Claude-style "prefer resume over fail": before marking `.timedOut`, attempt
        // a `chat.history` fetch first. If the gateway has more content than our
        // placeholder, the run actually completed gateway-side and we just missed the
        // final event (possible after long lid-closed sleep, dropped reconnect race,
        // etc.). Recover cleanly to `.completed` instead of falsely marking failed.
        let inactivityLimit: TimeInterval = inactivityTimeoutSeconds  // user-tunable, default 60 min
        let timeoutTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // check every 10s
                guard let self = self, !Task.isCancelled else { return }
                // Use the gateway-level timestamp: any inbound message resets it; nothing for
                // `inactivityLimit` means we're not getting anything (including ack/delta) from gateway.
                let elapsed = Date().timeIntervalSince(self.gatewayClient.lastMessageReceivedAt)
                if elapsed >= inactivityLimit {
                    if self.activeChatRuns[msgId] != nil {
                        // Step 1: try history recovery before declaring failure.
                        // 10s budget (matches GatewayClient.fetchLastAssistantMessage's own timeout).
                        let recovered = await self.gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                        self.gatewayClient.unsubscribe(subscriberId: subscriberId)

                        await MainActor.run {
                            // Snapshot current placeholder length so we only adopt history
                            // if it strictly extends what we already have. Otherwise (history
                            // empty / shorter / unchanged) fall to the timedOut path.
                            let currentLen = self.findMessage(byId: msgId)?.content.count ?? 0
                            if let text = recovered, text.count > currentLen, !text.isEmpty {
                                chatLog.info("inactivity recovery succeeded: \(text.count) chars from history (placeholder had \(currentLen))")
                                self.updateMessage(msgId: msgId, content: text, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                            } else {
                                chatLog.warning("inactivity timeout: no usable history, marking timedOut (elapsed=\(Int(elapsed))s)")
                                let timeoutMsg = String(localized: "The task timed out and has been terminated. You can try again or switch to another agent.", bundle: LanguageManager.shared.localizedBundle)
                                if let msg = self.findMessage(byId: msgId) {
                                    let content = msg.content.isEmpty
                                        ? timeoutMsg
                                        : msg.content + "\n\n---\n> ⚠️ " + timeoutMsg
                                    self.updateMessage(msgId: msgId, content: content, status: .timedOut, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                                }
                            }
                            self.activeChatRuns.removeValue(forKey: msgId)
                            self.foregroundTaskIds.remove(msgId)
                            self.backgroundTaskIds.remove(msgId)
                            self.taskAgentMap.removeValue(forKey: msgId)
                            self.taskSessionMap.removeValue(forKey: msgId)
                            self.recomputeIsSendingMessage()
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
                self.taskSessionMap.removeValue(forKey: msgId)
                self.unregisterInFlightRun(msgId: msgId)
                self.recomputeIsSendingMessage()
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
                    // Only update if not already in a terminal state. The
                    // placeholder may live in chatMessagesByAgent[agentId]
                    // (session still visible) or in chatMessagesByInactiveSession
                    // (user navigated to a different session mid-stream) —
                    // findMessage handles both.
                    if let current = findMessage(byId: msgId),
                       current.taskStatus != .cancelled {
                        updateMessage(msgId: msgId, content: accumulatedText, status: current.taskStatus, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
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
                    // Only emit the "background task completed" inline card when the
                    // user is still looking at the SAME session the task ran in.
                    // Otherwise we'd append it into whatever session is currently
                    // active for this agent — and `persistChangedSessions` would
                    // later save that orphan line into the wrong session's JSON
                    // (the v1.1.49 / v1.1.50 cross-session "answer in another
                    // conversation" bug). The real reply was already routed to
                    // the right place via `updateMessage` above, so navigating
                    // back to the original session shows the completed turn
                    // naturally — no notification needed there either.
                    if selectedSessionIdByAgent[currentAgentId] == taskSessionMap[msgId] {
                        appendBackgroundNotification(agentId: currentAgentId, agentEmoji: currentAgentEmoji, completed: true, msgId: msgId)
                    }
                }
                break streamLoop

            case .aborted(let eventRunId, _):
                guard eventRunId == runId else { continue }
                receivedTerminalEvent = true
                if let current = findMessage(byId: msgId),
                   current.taskStatus != .cancelled {
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

        // Stream ended without a terminal event — typically WebSocket dropped
        // (sleep / network blip / gateway restart) and `scheduleReconnect()`
        // finished our event continuations. Don't immediately declare the
        // task dead: in many cases the run actually COMPLETED on the gateway
        // during the disconnect window (LLM provider doesn't know about our
        // client disconnect), and we can recover the final reply via
        // `chat.history`.
        //
        // Strategy:
        //   1. Give WS up to 15s to reconnect (usual reconnect window is
        //      1-3s, longer on system wake from sleep)
        //   2. Once back online, ask gateway for the last assistant
        //      message in this session via `chat.history`
        //   3. If history has more content than we streamed → use it,
        //      mark `.completed` cleanly with no "interrupted" notice
        //   4. If history has nothing or is shorter → fall through to
        //      the legacy "Connection was interrupted" path
        if !receivedTerminalEvent {
            chatLog.warning("chat stream ended WITHOUT terminal event: runId=\(runId), accumulatedLen=\(accumulatedText.count) — attempting chat.history recovery")

            // Wait briefly for the WS to come back. Poll every 0.5s
            // rather than blocking on a single 30s sleep so we recover
            // as soon as the gateway is reachable.
            //
            // 30s window: must strictly exceed our reconnect backoff
            // ceiling (1+2+4+8 = 15s for the 4th attempt) plus the
            // connect.challenge round-trip + auth (~1-3s). 15s exactly
            // matched the backoff tail and lost the race on the 4th
            // retry; 30s gives the handshake comfortable headroom and
            // matches Anthropic SSE's typical reconnect tolerance.
            var recovered: String? = nil
            let recoveryDeadline = Date().addingTimeInterval(30)
            while Date() < recoveryDeadline {
                if gatewayClient.isConnected {
                    recovered = await gatewayClient.fetchLastAssistantMessage(sessionKey: sessionKey)
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            if let current = findMessage(byId: msgId),
               current.taskStatus != .completed && current.taskStatus != .cancelled && current.taskStatus != .timedOut {
                // Prefer history if it returned strictly more content than
                // what we managed to capture via streaming. The history
                // endpoint returns the FULL final assistant turn if the
                // run completed gateway-side, so this transparently
                // covers the "system slept while LLM finished" case.
                if let recoveredText = recovered, recoveredText.count > accumulatedText.count {
                    chatLog.info("chat.history recovered \(recoveredText.count) chars (streamed only \(accumulatedText.count))")
                    updateMessage(msgId: msgId, content: recoveredText, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                } else {
                    chatLog.warning("chat.history recovery failed or shorter than stream — marking interrupted")
                    let disconnectNote = String(localized: "Connection was interrupted. The response may be incomplete.", bundle: LanguageManager.shared.localizedBundle)
                    let content = accumulatedText.isEmpty
                        ? disconnectNote
                        : accumulatedText + "\n\n---\n> ⚠️ " + disconnectNote
                    updateMessage(msgId: msgId, content: content, status: .completed, agentId: currentAgentId, agentEmoji: currentAgentEmoji)
                }
            }
        }
    }

    /// Move a foreground task to background, unlocking the input
    func moveTaskToBackground(_ msgId: UUID) {
        guard foregroundTaskIds.contains(msgId) else { return }
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.insert(msgId)
        recomputeIsSendingMessage()

        let bgLabel = String(localized: "⏳ Task running in background...", bundle: LanguageManager.shared.localizedBundle)

        // First look in the active per-agent map (the common case — auto-bg
        // fires from ThinkingIndicator which only renders for visible
        // placeholders).
        for agentId in chatMessagesByAgent.keys {
            if let idx = chatMessagesByAgent[agentId]?.firstIndex(where: { $0.id == msgId }) {
                let msg = chatMessagesByAgent[agentId]![idx]
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

        // Fall back to the inactive stash. Reachable when the auto-bg
        // timer fires within the ~1s window between the user switching
        // sessions and `.onDisappear` cancelling the timer — without
        // this branch the placeholder keeps showing "Thinking…" forever
        // when the user navigates back, even though the task is
        // already tracked as background internally.
        if let sessionId = taskSessionMap[msgId],
           let idx = chatMessagesByInactiveSession[sessionId]?.firstIndex(where: { $0.id == msgId }) {
            let msg = chatMessagesByInactiveSession[sessionId]![idx]
            let content = msg.content.isEmpty ? bgLabel : msg.content
            var messages = chatMessagesByInactiveSession[sessionId]!
            messages[idx] = ChatMessage(
                role: .assistant, content: content,
                agentId: msg.agentId, agentEmoji: msg.agentEmoji,
                taskStatus: .background, id: msgId
            )
            chatMessagesByInactiveSession[sessionId] = messages
        }
    }

    /// Cancel an in-progress chat task.
    /// Sends chat.abort via WebSocket and terminates the event stream.
    func cancelChat(_ msgId: UUID) {
        // 1. Look up runId and send abort via gateway WebSocket.
        //    Build sessionKey from the TASK's bound (agent, session), not
        //    the currently-active one — callers like cancelTasks(inSession:)
        //    pass msgIds from sessions that may no longer be selected.
        let runId = activeChatRuns[msgId]
        let taskAgent = taskAgentMap[msgId] ?? selectedAgentId
        let taskSid = taskSessionMap[msgId] ?? selectedSessionIdByAgent[taskAgent]
        if let taskSid = taskSid {
            let sessionKey = sessionKeyForAgent(taskAgent, sessionId: taskSid)
            Task {
                _ = await gatewayClient.abortChat(sessionKey: sessionKey, runId: runId)
            }
        } else {
            chatLog.warning("cancelChat: no session bound to msgId \(msgId.uuidString.prefix(8)) — abort skipped")
        }

        // 2. Terminate the event stream for this message
        gatewayClient.unsubscribe(subscriberId: msgId.uuidString)
        activeChatRuns.removeValue(forKey: msgId)

        // 3. Update message status to cancelled — message may live in
        // chatMessagesByAgent (visible session) or chatMessagesByInactiveSession
        // (background-streaming session). updateMessage handles both.
        if let msg = findMessage(byId: msgId) {
            let cancelledLabel = String(localized: "Task cancelled by user.", bundle: LanguageManager.shared.localizedBundle)
            let content = msg.content.isEmpty
                ? cancelledLabel
                : msg.content + "\n\n---\n> " + cancelledLabel
            updateMessage(msgId: msgId, content: content,
                          status: .cancelled,
                          agentId: msg.agentId ?? taskAgentMap[msgId] ?? selectedAgentId,
                          agentEmoji: msg.agentEmoji)
        }

        // 4. Cleanup tracking
        foregroundTaskIds.remove(msgId)
        backgroundTaskIds.remove(msgId)
        taskAgentMap.removeValue(forKey: msgId)
        taskSessionMap.removeValue(forKey: msgId)
        recomputeIsSendingMessage()
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
        // Reset the backend session for the current (agent, session) so the
        // next message starts with a clean gateway context. Falls back to
        // doing nothing if we somehow don't have an active session — better
        // than wiping the wrong session.
        guard let sid = selectedSessionIdByAgent[selectedAgentId] else { return }
        resetAgentSession(agentId: selectedAgentId, sessionId: sid)
    }

    /// Reset the backend session files for a specific (agent, session) so
    /// the next message starts fresh — without nuking other UI sessions
    /// the user has for the same agent.
    private func resetAgentSession(agentId: String, sessionId: UUID) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let sessionsDir = "\(homeDir)/.openclaw/agents/\(agentId)/sessions"
        let sessionsJsonPath = "\(sessionsDir)/sessions.json"
        let fm = FileManager.default

        // Look up the gateway session-id mapped to *this* UI session's
        // sessionKey, not the legacy "agent:X:main" catch-all. Match the key
        // CASE-INSENSITIVELY: the client builds sessionKey with Swift's
        // UPPERCASE `UUID.uuidString`, but the gateway stores it LOWERCASE — an
        // exact match silently missed, so this reset was a no-op on the gateway
        // side (it only cleared the local mirror, never the gateway context).
        let sessionKey = sessionKeyForAgent(agentId, sessionId: sessionId).lowercased()
        guard let data = fm.contents(atPath: sessionsJsonPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actualKey = root.keys.first(where: { $0.lowercased() == sessionKey }),
              let entry = root[actualKey] as? [String: Any],
              let gwSessionId = entry["sessionId"] as? String else {
            NSLog("[Chat] resetAgentSession: no active session found for %@", agentId)
            return
        }

        // Rename the .jsonl file to .jsonl.reset.<timestamp>
        let jsonlPath = "\(sessionsDir)/\(gwSessionId).jsonl"
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupPath = "\(jsonlPath).reset.\(timestamp)"
        if fm.fileExists(atPath: jsonlPath) {
            try? fm.moveItem(atPath: jsonlPath, toPath: backupPath)
            NSLog("[Chat] resetAgentSession: renamed %@ -> %@", jsonlPath, backupPath)
        }

        // Remove the session entry from sessions.json so backend creates a new one
        root.removeValue(forKey: actualKey)
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? updatedData.write(to: URL(fileURLWithPath: sessionsJsonPath))
            NSLog("[Chat] resetAgentSession: removed session key %@ from sessions.json", actualKey)
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
            // openclaw CLI 实际接受的是 `--session <target>` (target ∈ main|isolated|current|session:<id>),
            // 不是 `--session-target` — 后者从 v1.1.15 起就拼错了,但定时任务功能用户少,40+ 版本一直没人撞到。
            // 2026.3.2 / 2026.5.10 都不认 --session-target,本地脚手架就是 --session。
            cmd += " --session '\(sessionTarget)'"
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

        let agentList: [[String: Any]] = {
            guard let data = FileManager.default.contents(atPath: configPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agents = json["agents"] as? [String: Any],
                  let list = agents["list"] as? [[String: Any]] else { return [] }
            return list
        }()

        let agentId = selectedAgentId
        // Sub-agents must exist in agents.list. The "main" agent is special:
        // openclaw doesn't always register it there (the workspace alone
        // defines it), so we treat a missing entry as an empty dict and let
        // the workspace files supply name/emoji/persona content.
        let entry: [String: Any] = agentList.first { $0["id"] as? String == agentId } ?? [:]
        guard !entry.isEmpty || agentId == "main" else {
            NSLog("[AgentSettings] loadSelectedAgentDetail: agent %@ not found in agents.list", agentId)
            return
        }

        // Determine workspace (faithful to openclaw's resolveAgentWorkspaceDir).
        let workspace = Self.resolveAgentWorkspace(agentId)

        let agentDir = entry["agentDir"] as? String ?? ""
        let model = entry["model"] as? String ?? ""
        let isDefault = entry["isDefault"] as? Bool ?? (agentId == "main")

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
    /// When the message was created. Optional so sessions persisted before
    /// this field existed still decode cleanly — pre-existing messages
    /// show no timestamp instead of an inaccurate "now".
    let timestamp: Date?

    init(role: ChatRole, content: String, agentId: String? = nil, agentEmoji: String? = nil, attachments: [URL] = [], taskStatus: TaskStatus = .completed, id: UUID = UUID(), scrollTargetId: UUID? = nil, timestamp: Date? = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.agentId = agentId
        self.agentEmoji = agentEmoji
        self.attachments = attachments
        self.taskStatus = taskStatus
        self.scrollTargetId = scrollTargetId
        self.timestamp = timestamp
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
