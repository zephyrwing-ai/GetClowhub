import Foundation
import Combine

// MARK: - Decompose Stage Status

enum DecomposeStageStatus {
    case pending
    case inProgress
    case completed
}

struct DecomposeStage: Identifiable {
    let id: Int
    let text: String
    var status: DecomposeStageStatus
}

// MARK: - Clarify Entry

struct ClarifyEntry: Identifiable, Codable {
    let id: Int
    let role: String
    let content: String
}

// MARK: - Recruit Status

enum RecruitStatus {
    case pending
    case recruiting
    case recruited
    case ready      // already installed, no recruitment needed
    case failed
}

struct RecruitEntry: Identifiable {
    let id: String  // agentId
    var status: RecruitStatus
}

// MARK: - Subtask Result (P1-1: Structured task result)

enum SubtaskResultStatus: String {
    case completed       // output.md exists OR artifacts produced
    case incomplete      // Agent produced stdout but no output.md
    case failed          // No output at all
}

struct SubtaskResult: Sendable {
    let taskId: Int
    let status: SubtaskResultStatus
    let output: String?          // Filtered agent stdout or output.md content
    let artifactFiles: [String]  // Files found in artifacts/
    let elapsed: TimeInterval
    let hasOutputMd: Bool        // Whether output.md was written by agent

    var statusMessage: String {
        switch status {
        case .completed:
            return artifactFiles.isEmpty ? "Completed" : "Completed (files: \(artifactFiles.joined(separator: ", ")))"
        case .incomplete:
            return "Output exists but not confirmed (no output.md)"
        case .failed:
            return output == nil ? "Agent not responding" : "Agent returned empty content"
        }
    }
}

// MARK: - Task Progress Info

struct TaskProgressInfo {
    var agentProgress: String?    // From progress.md (agent-authored)
    var outputLineCount: Int = 0  // stdout accumulated line count
    var lastOutputTime: Date?     // Last time stdout produced new output
    var startTime: Date = Date()  // When the task started
    var isProcessAlive: Bool = true  // OS process still running
    var discoveredFiles: [String] = []  // Files found in task directory (real-time artifact tracking)
    var lastFileChangeTime: Date?       // Last time a new file was discovered
    var lastUIRefreshTime: Date?  // Last time objectWillChange was sent for this task

    /// Whether the agent appears stalled (no activity for 5 minutes AND process alive)
    var isStale: Bool {
        guard isProcessAlive else { return false }
        // Use the most recent activity signal: stdout OR file change
        let lastActivity = [lastOutputTime, lastFileChangeTime].compactMap { $0 }.max()
        guard let t = lastActivity else {
            return Date().timeIntervalSince(startTime) > 300
        }
        return Date().timeIntervalSince(t) > 300
    }

    /// Elapsed time since task started
    var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Best available display text for the progress section
    var displayText: String? {
        if let ap = agentProgress, !ap.isEmpty {
            return ap
        }
        if isProcessAlive {
            let elapsedStr = String(format: "%.0fs", elapsed)
            if !discoveredFiles.isEmpty {
                let staleWarning = isStale ? " · ⚠️ No activity for 5 min" : ""
                return "Produced \(discoveredFiles.count) files · \(elapsedStr)\(staleWarning)"
            }
            if outputLineCount > 0 {
                let staleWarning = isStale ? " · ⚠️ No activity for 5 min" : ""
                return "Running · \(outputLineCount) lines · \(elapsedStr)\(staleWarning)"
            }
            if elapsed > 5 {
                return "Waiting for output... · \(elapsedStr)"
            }
        }
        return nil
    }
}

@MainActor
class CollabViewModel: ObservableObject {
    @Published var session: CollabSession? {
        didSet { persistSession() }
    }
    @Published var isRunning = false
    @Published var phase: CollabPhase = .clarifying {
        didSet {
            // Keep session.phase in sync for persistence
            session?.phase = phase
        }
    }
    @Published var decomposingOutput = ""
    @Published var researchOutput = ""
    @Published var researchStages: [DecomposeStage] = []
    @Published var chatInput = ""
    @Published var clarifyHistory: [ClarifyEntry] = [] {
        didSet {
            // Sync to session for persistence
            session?.clarifyDialogue = clarifyHistory.map {
                ClarifyDialogueEntry(id: $0.id, role: $0.role, content: $0.content)
            }
        }
    }
    private var clarifyHistoryNextId = 0
    @Published var taskProgress: [Int: TaskProgressInfo] = [:]  // taskId → progress info
    @Published var decomposeStages: [DecomposeStage] = []
    @Published var recruitEntries: [RecruitEntry] = []
    @Published var sessionHistory: [CollabSession] = []  // loaded from disk
    @Published var config: CommanderConfig = CommanderConfig.load()

    private weak var dashboardViewModel: DashboardViewModel?
    private var commanderPersona: String = ""
    private var isCancelled = false
    private var stagedMessageTask: Task<Void, Never>?
    private var prefetchedClarifyOutput: String?  // Captured when checkIntent receives clarify JSON

    init(dashboardViewModel: DashboardViewModel) {
        self.dashboardViewModel = dashboardViewModel
        loadCommanderPersona()
        // Sync SOUL.md immediately so Commander always has the latest persona
        syncCommanderPersona()
        // Load history from disk
        loadSessionHistory()
    }

    // MARK: - Collab Directory

    static func collabDirPath(sessionId: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.openclaw/workspace-commander/\(sessionId)"
    }

    private static var commanderWorkspacePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.openclaw/workspace-commander"
    }

    // MARK: - Session Persistence

    /// Save current session to session.json in the collab directory
    private func persistSession() {
        guard let session = session else { return }
        let dir = Self.collabDirPath(sessionId: session.id)
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/session.json"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(session) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Load all collab sessions from disk (scans workspace-commander/collab-* directories)
    func loadSessionHistory() {
        let basePath = Self.commanderWorkspacePath
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else {
            sessionHistory = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var sessions: [CollabSession] = []
        for entry in entries where entry.hasPrefix("collab-") {
            let sessionPath = "\(basePath)/\(entry)/session.json"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
                  let loaded = try? decoder.decode(CollabSession.self, from: data) else {
                continue
            }
            // Skip the currently active session
            if loaded.id == session?.id { continue }
            sessions.append(loaded)
        }

        // Sort by createdAt descending (newest first)
        sessions.sort { $0.createdAt > $1.createdAt }
        sessionHistory = sessions
    }

    /// Switch to a historical session (read-only view)
    func switchToSession(_ historicalSession: CollabSession) {
        session = historicalSession
        phase = historicalSession.phase
        isRunning = false
        // Restore clarify dialogue from persisted data
        clarifyHistory = historicalSession.clarifyDialogue.map {
            ClarifyEntry(id: $0.id, role: $0.role, content: $0.content)
        }
        clarifyHistoryNextId = (clarifyHistory.map { $0.id }.max() ?? -1) + 1
        taskProgress = [:]
        decomposeStages = []
        recruitEntries = []
        // Reload history to update the list
        loadSessionHistory()
    }

    /// Sanitize a string for use as a directory name (remove path separators, limit length)
    private static func sanitizeDirName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(20))
    }

    /// Build a human-readable task directory name like "task-1-核心游戏系统-game-designer"
    static func taskDirName(task: CollabSubTask) -> String {
        let titlePart = sanitizeDirName(task.title)
        let agentPart = task.agentId ?? task.role ?? "main"
        return "task-\(task.id)-\(titlePart)-\(agentPart)"
    }

    /// Resolve task directory path by task ID (looks up the session for the full task info)
    private func taskDirPath(taskId: Int) -> String? {
        guard let s = session else { return nil }
        guard let task = s.subtasks.first(where: { $0.id == taskId }) else { return nil }
        let collabDir = Self.collabDirPath(sessionId: s.id)
        return "\(collabDir)/\(Self.taskDirName(task: task))"
    }

    // MARK: - Commander Persona

    private func loadCommanderPersona() {
        if let url = Bundle.main.url(forResource: "commander-persona", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            commanderPersona = content
        }
    }

    /// Write Commander's SOUL.md, IDENTITY.md, AGENTS.md on init so they're always up-to-date.
    /// Does NOT modify openclaw.json — that's handled by ensureCommanderAgent() on first collab.
    private func syncCommanderPersona() {
        guard !commanderPersona.isEmpty else { return }

        let workspaceDir = NSString("~/.openclaw/workspace-commander").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        let soulPath = (workspaceDir as NSString).appendingPathComponent("SOUL.md")
        try? commanderPersona.write(toFile: soulPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Ensure Commander Agent

    /// Check if commander agent exists in openclaw.json; create if not.
    /// Also ensures IDENTITY.md and SOUL.md are written to the workspace.
    func ensureCommanderAgent() async {
        guard let vm = dashboardViewModel else { return }

        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var agentList = agentsSection["list"] as? [[String: Any]] ?? []

        let agentDir = NSString("~/.openclaw/agents/commander/agent").expandingTildeInPath
        let workspaceDir = NSString("~/.openclaw/workspace-commander").expandingTildeInPath

        // Always ensure SOUL.md is up-to-date in the workspace
        // (openclaw reads SOUL.md from workspace, not persona.md from agentDir)
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        let soulPath = (workspaceDir as NSString).appendingPathComponent("SOUL.md")
        if !commanderPersona.isEmpty {
            try? commanderPersona.write(toFile: soulPath, atomically: true, encoding: .utf8)
        }

        let identityContent = """
        # IDENTITY.md - Who Am I?

        - **Name:** Commander
        - **Creature:** AI Task Orchestrator
        - **Vibe:** Precise, structured, efficient
        """
        let identityPath = (workspaceDir as NSString).appendingPathComponent("IDENTITY.md")
        try? identityContent.write(toFile: identityPath, atomically: true, encoding: .utf8)

        // Write AGENTS.md with real-world use cases for team composition reference
        let agentsContent = """
        # Commander AGENTS.md

        ## Real-World Team Composition Examples

        Use these scenarios as reference when decomposing tasks and selecting agents.

        ### Scenario 1: Building a Startup MVP
        **Team**: Frontend Developer (React app) + Backend Architect (API/DB) + Growth Hacker (user acquisition) + Rapid Prototyper (fast iteration) + Reality Checker (quality)
        **Result**: Ship faster with specialized expertise at every stage.

        ### Scenario 2: Marketing Campaign Launch
        **Team**: Content Creator (campaign content) + Twitter Engager (Twitter strategy) + Instagram Curator (visual content) + Reddit Community Builder (community engagement) + Analytics Reporter (tracking)
        **Result**: Multi-channel coordinated campaign with platform-specific expertise.

        ### Scenario 3: Enterprise Feature Development
        **Team**: Senior Project Manager (scope/tasks) + Senior Developer (implementation) + UI Designer (design system) + Experiment Tracker (A/B testing) + Evidence Collector (QA) + Reality Checker (production readiness)
        **Result**: Enterprise-grade delivery with quality gates and documentation.

        ### Scenario 4: Paid Media Account Takeover
        **Team**: Paid Media Auditor (assessment) + Tracking Specialist (conversion tracking) + PPC Campaign Strategist (account architecture) + Search Query Analyst (waste elimination) + Ad Creative Strategist (copy refresh) + Analytics Reporter (dashboards)
        **Result**: Systematic account takeover within 30 days.

        ### Scenario 5: Full Agency Product Discovery
        **Team**: All divisions working in parallel — Product Trend Researcher + Backend Architect + Brand Guardian + Growth Hacker + Support Responder + UX Researcher + Project Shepherd + XR Interface Architect
        **Result**: Comprehensive cross-functional product blueprint in a single session.

        ## Three-Tier Agent Matching

        1. **Installed Agents** (Available Agents): Already recruited, use directly
        2. **Marketplace Agents** (needs_recruit=true): System auto-recruits before execution
        3. **Generic Fallback** (agent=null + role): Main agent with role injection
        """
        let agentsMdPath = (workspaceDir as NSString).appendingPathComponent("AGENTS.md")
        try? agentsContent.write(toFile: agentsMdPath, atomically: true, encoding: .utf8)

        // Check if commander already exists in config
        if agentList.contains(where: { ($0["id"] as? String) == "commander" }) {
            return
        }

        // Create agent directory
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)

        // Create commander agent entry
        let commanderEntry: [String: Any] = [
            "id": "commander",
            "name": "commander",
            "default": false,
            "identity": [
                "name": "Commander"
            ],
            "agentDir": agentDir,
            "workspace": workspaceDir
        ]
        agentList.append(commanderEntry)
        agentsSection["list"] = agentList
        json["agents"] = agentsSection

        // Write back
        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }

        // Reload agents so commander appears in the list
        vm.loadAvailableAgents()
    }

    // MARK: - Intent Check

    /// Ask Commander whether the message needs multi-agent collab or can be answered directly.
    /// Returns the direct reply string if Commander decides to answer directly, nil if collab is needed.
    ///
    /// Two-step approach:
    /// 1. Classification: ask Commander to reply DIRECT or COLLAB (one word only)
    /// 2. If DIRECT: send the original message to Commander for a natural reply
    /// Fallback: if classification output is ambiguous, use text heuristics
    func checkIntent(_ text: String) async -> String? {
        guard let vm = dashboardViewModel else { return nil }

        await ensureCommanderAgent()

        // Step 1: Classification — expect only "DIRECT" or "COLLAB"
        let classifyPrompt = "[Check Intent]\n\(text)"

        let classifyOutput = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-intent-\(UUID().uuidString.prefix(8))",
            message: classifyPrompt,
            vm: vm
        )

        let filtered = (DashboardViewModel.filterAgentOutput(classifyOutput) ?? classifyOutput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = filtered.uppercased()

        // Parse classification result
        let isDirectReply: Bool
        if upper.contains("DIRECT") && !upper.contains("COLLAB") {
            isDirectReply = true
        } else if upper.contains("COLLAB") {
            isDirectReply = false
        } else {
            // Fallback: detect if Commander accidentally output clarification JSON
            // (e.g. {"ready":false,"questions":"..."}) instead of just "COLLAB"
            let looksLikeClarifyJSON = filtered.contains("\"ready\"") || filtered.contains("\"questions\"") || filtered.contains("\"tasks\"") || filtered.contains("\"summary\"")
            if looksLikeClarifyJSON {
                isDirectReply = false
                prefetchedClarifyOutput = filtered  // Save for startCollab to reuse
            } else {
                // Short non-empty output without collab signals → treat as direct reply
                isDirectReply = !filtered.isEmpty && filtered.count > 2
            }
        }

        if !isDirectReply {
            return nil  // triggers collab workflow
        }

        // Step 2: Get direct reply from Commander (plain message, no special tag)
        let replyOutput = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-chat-\(UUID().uuidString.prefix(8))",
            message: text,
            vm: vm
        )

        let reply = (DashboardViewModel.filterAgentOutput(replyOutput) ?? replyOutput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Safety check: if step 2 returns clarify JSON instead of a natural reply,
        // redirect to collab flow (Commander sometimes ignores the plain-message intent)
        let replyLooksLikeCollabJSON = reply.contains("\"ready\"") || reply.contains("\"tasks\"") || reply.contains("\"questions\"")
        if replyLooksLikeCollabJSON {
            prefetchedClarifyOutput = reply
            return nil  // triggers collab workflow
        }

        return reply.isEmpty ? nil : reply
    }

    // MARK: - Start Collab

    func startCollab(_ taskDescription: String) async {
        guard let vm = dashboardViewModel else { return }

        isCancelled = false
        isRunning = true
        phase = .clarifying
        decomposingOutput = ""
        clarifyHistory = []
        clarifyHistoryNextId = 0
        taskProgress = [:]
        decomposeStages = []
        recruitEntries = []

        // Ensure commander agent exists
        await ensureCommanderAgent()

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let taskId = "collab-\(dateFormatter.string(from: Date()))"

        // Create an initial session
        session = CollabSession(
            id: taskId,
            taskDescription: taskDescription,
            summary: "Gathering requirements...",
            subtasks: [],
            createdAt: Date()
        )

        // Build available agents list
        let agentDescriptions = buildAgentDescriptions(vm: vm)

        // Check if checkIntent already captured Commander's clarification output
        let commanderOutput: String?
        if let prefetched = prefetchedClarifyOutput {
            prefetchedClarifyOutput = nil
            commanderOutput = prefetched
        } else {
            // First clarify prompt — always brainstorm with user
            let clarifyPrompt = """
            [Clarify Task]
            \(agentDescriptions)

            [User Task]
            \(taskDescription)

            你必须先与用户进行 brainstorm，通过提问充分了解需求细节后再拆解任务。
            第一轮必须输出 ready:false 并提出关键问题（技术栈、功能范围、交互方式、视觉风格等）。
            只输出 JSON。
            """

            // Start staged status messages while Commander is thinking
            startStagedMessages(messages: clarifyStageMessages)

            commanderOutput = await runAgentCommand(
                agentId: "commander",
                sessionId: "getclawhub-collab-\(taskId)-commander",
                message: clarifyPrompt,
                vm: vm,
                channel: taskId
            )

            // Stop staged messages once Commander responds
            stopStagedMessages()
        }

        guard !isCancelled else {
            isRunning = false
            return
        }

        await handleClarifyResult(commanderOutput)
    }

    // MARK: - Handle Clarify Result

    private func handleClarifyResult(_ output: String?) async {
        let filtered = DashboardViewModel.filterAgentOutput(output) ?? output
        let userHasResponded = clarifyHistory.contains(where: { $0.role == "user" })
        let userRoundCount = clarifyHistory.filter { $0.role == "user" }.count
        let maxClarifyRounds = 3

        // If user has answered enough rounds, force proceed regardless of Commander's response
        if userRoundCount >= maxClarifyRounds {
            let context = session?.taskContext.isEmpty == false ? session!.taskContext : (session?.taskDescription ?? "")
            session?.taskContext = context
            clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: "✅ Enough info collected, starting decomposition"))
            clarifyHistoryNextId += 1
            if let vm = dashboardViewModel {
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant, content: "Enough requirements gathered, starting task decomposition.", agentId: "commander"
                ))
            }
            await runResearchThenDecompose()
            return
        }

        guard let jsonStr = extractJSON(from: filtered),
              let jsonData = jsonStr.data(using: .utf8),
              let response = try? JSONDecoder().decode(CommanderClarifyResponse.self, from: jsonData) else {
            // JSON parse failed — force brainstorm if user hasn't confirmed yet
            if !userHasResponded {
                let fallbackQ = "请描述一下你对这个任务的具体期望，比如：\n1. 希望使用什么技术栈？\n2. 核心功能有哪些？\n3. 有什么特殊要求？"
                clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: fallbackQ))
                clarifyHistoryNextId += 1
                phase = .clarifying
                isRunning = false
                if let vm = dashboardViewModel {
                    vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                        role: .assistant, content: fallbackQ, agentId: "commander"
                    ))
                }
                return
            }
            session?.taskContext = session?.taskDescription ?? ""
            await runResearchThenDecompose()
            return
        }

        if response.ready, let context = response.context {
            if !userHasResponded {
                // Commander says ready but user hasn't confirmed — force brainstorm
                let forceQ = response.context ?? "在开始之前，我需要和你确认几个关键问题来确保任务拆解更准确。请告诉我你对这个任务的具体想法和要求。"
                clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: forceQ))
                clarifyHistoryNextId += 1
                phase = .clarifying
                isRunning = false
                if let vm = dashboardViewModel {
                    vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                        role: .assistant, content: forceQ, agentId: "commander"
                    ))
                }
            } else {
                // User has confirmed at least once — proceed
                session?.taskContext = context
                clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: "✅ Requirements confirmed"))
                clarifyHistoryNextId += 1
                await runResearchThenDecompose()
            }
        } else if let questions = response.questions {
            // Commander needs more info — display questions to user
            clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: questions))
            clarifyHistoryNextId += 1
            phase = .clarifying
            isRunning = false
            // Notify the chat — questions will be shown via DashboardView routing
            if let vm = dashboardViewModel {
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: questions,
                    agentId: "commander"
                ))
            }
        } else {
            // Unexpected format — force brainstorm if user hasn't confirmed
            if !userHasResponded {
                let fallbackQ = "请描述一下你对这个任务的具体期望，比如：\n1. 希望使用什么技术栈？\n2. 核心功能有哪些？\n3. 有什么特殊要求？"
                clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "commander", content: fallbackQ))
                clarifyHistoryNextId += 1
                phase = .clarifying
                isRunning = false
                if let vm = dashboardViewModel {
                    vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                        role: .assistant, content: fallbackQ, agentId: "commander"
                    ))
                }
                return
            }
            session?.taskContext = session?.taskDescription ?? ""
            await runResearchThenDecompose()
        }
    }

    // MARK: - Handle Clarify Response (User Reply)

    func handleClarifyResponse(_ userReply: String) async {
        guard let vm = dashboardViewModel, let currentSession = session else { return }

        isRunning = true
        clarifyHistory.append(ClarifyEntry(id: clarifyHistoryNextId, role: "user", content: userReply))
        clarifyHistoryNextId += 1

        // Build conversation history
        let agentDescriptions = buildAgentDescriptions(vm: vm)
        var conversationLines: [String] = []
        for entry in clarifyHistory.dropLast() { // exclude the just-appended user reply
            let prefix = entry.role == "commander" ? "Commander" : "User"
            conversationLines.append("\(prefix): \(entry.content)")
        }

        let clarifyPrompt = """
        [Clarify Task]
        \(agentDescriptions)

        [Original Task]
        \(currentSession.taskDescription)

        [Conversation History]
        \(conversationLines.joined(separator: "\n"))

        [User's Latest Reply]
        \(userReply)

        请判断是否有足够信息来拆分此任务。只输出 JSON。
        """

        // Start staged status messages while Commander is thinking
        startStagedMessages(messages: clarifyStageMessages)

        let commanderOutput = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-commander",
            message: clarifyPrompt,
            vm: vm,
            channel: currentSession.id
        )

        // Stop staged messages once Commander responds
        stopStagedMessages()

        guard !isCancelled else {
            isRunning = false
            return
        }

        await handleClarifyResult(commanderOutput)
    }

    // MARK: - Research Phase (P1-2)

    /// Optional research phase: dispatches 1-2 agents to explore the codebase/architecture
    /// before Commander decomposes the task. Enriches taskContext with research findings.
    private func runResearchThenDecompose() async {
        guard let vm = dashboardViewModel, let currentSession = session else { return }

        // Determine if this task warrants research (involves code modifications, architecture, existing codebase)
        let taskText = (currentSession.taskContext + " " + currentSession.taskDescription).lowercased()
        let codeKeywords = ["代码", "code", "修改", "重构", "refactor", "实现", "implement", "fix", "bug",
                            "架构", "architecture", "模块", "module", "接口", "api", "数据库", "database",
                            "添加功能", "feature", "优化", "optimize", "迁移", "migrate"]
        let needsResearch = codeKeywords.contains(where: { taskText.contains($0) })

        guard needsResearch else {
            // Simple task — skip research, go directly to decompose
            await decompose()
            return
        }

        phase = .researching
        researchOutput = ""

        vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
            role: .assistant,
            content: "🔬 正在调研项目结构和代码库，以便更准确地拆分任务...",
            agentId: "commander"
        ))

        // Start staged progress messages for the research phase
        startStagedMessages(messages: researchStageMessages, updateResearchStages: true)

        let researchPrompt = """
        [Your Role]
        你是 Commander 的调研助手。你的职责是为后续的任务拆解提供代码库和架构信息。

        [Original Task]
        \(currentSession.taskDescription)

        [Task Context]
        \(currentSession.taskContext)

        [调研要求]
        1. 分析当前工作目录的项目结构（关键目录和文件）
        2. 识别与任务相关的核心文件和模块
        3. 理解现有架构模式（如 MVC/MVVM、依赖关系等）
        4. 发现可能的技术约束或注意事项

        [输出格式]
        用简洁的结构化文本输出调研结果，包含：
        - 项目结构概述
        - 与任务相关的关键文件列表（含路径和简短说明）
        - 架构要点
        - 实现建议和注意事项

        不要编写任何代码，只做调研和分析。
        """

        let researchTimeout = 180  // Research phase: fixed 3-minute timeout
        let researchRawOutput = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-research",
            message: researchPrompt,
            vm: vm,
            timeoutOverride: researchTimeout
        )

        // Stop staged messages and mark all stages complete
        stopStagedMessages()
        completeAllResearchStages()

        guard !isCancelled else {
            isRunning = false
            return
        }

        // Enrich taskContext with research findings (skip gracefully if research returned nothing)
        if let filtered = DashboardViewModel.filterAgentOutput(researchRawOutput),
           !filtered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let truncated = filtered.count > 3000 ? String(filtered.prefix(3000)) + "\n..." : filtered
            session?.taskContext = (session?.taskContext ?? "") + "\n\n[调研结果]\n" + truncated

            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "🔬 调研完成，已获取项目架构信息。开始拆分任务...",
                agentId: "commander"
            ))
        } else {
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "调研阶段未获取到有效信息，直接开始拆分任务...",
                agentId: "commander"
            ))
        }

        await decompose()
    }

    // MARK: - Decompose

    func decompose() async {
        guard let vm = dashboardViewModel, var currentSession = session else { return }

        phase = .decomposing
        isRunning = true
        decomposingOutput = ""
        session?.summary = "Decomposing tasks..."

        let agentDescriptions = buildAgentDescriptions(vm: vm)
        let collabDir = Self.collabDirPath(sessionId: currentSession.id)

        let decomposePrompt = """
        [Your Role]
        你是 Commander（协调者），你的职责是将任务拆解并分配给合适的 Agent 执行。
        你绝不能把任务分配给自己（commander），也不能自己执行任何子任务。
        每个子任务都必须分配给一个具体的 Agent。

        \(agentDescriptions)

        [Task Context]
        \(currentSession.taskContext)

        [Collab Directory]
        \(collabDir)

        请将此任务拆解为子任务并分配给合适的 agent。
        对于来自 Marketplace 的 agent，设 needs_recruit: true。
        每个子任务的 prompt 必须包含协同目录协议的文件读写指令。

        [文件集标注 - 并发安全]
        每个子任务必须包含 affected_files 字段（字符串数组），列出该子任务预计会修改的文件或目录路径。
        - 如果是修改现有代码，列出具体文件路径（如 ["src/models/user.swift", "src/views/login.swift"]）
        - 如果是创建新项目/模块，列出顶层目录（如 ["artifacts/frontend", "artifacts/backend"]）
        - 如果是纯调研/文档任务不修改代码文件，设为空数组 []
        系统会根据 affected_files 的交集自动控制并发：修改相同文件的子任务会自动串行执行，避免覆盖冲突。

        [编码规范约束]
        如果任务涉及代码开发，每个开发类子任务的 prompt 中必须包含以下要求：
        - "严格遵循 context.md 中的编码规范，特别是 API 字段命名使用 snake_case"
        - "严格遵循架构设计文档中定义的接口字段名和数据结构，不得自行更改"
        - 如果存在架构设计子任务，后续开发子任务的 prompt 中必须明确引用架构产出文档路径

        [部署打包建议]
        如果任务涉及代码开发（前端、后端、全栈等），请考虑在最后安排一个"部署与打包"子任务，负责：
        - 编写启动/关停脚本（start.sh, stop.sh 等）
        - 整合各模块的依赖安装和构建步骤
        - 编写部署说明文档
        该子任务必须依赖所有开发类子任务和测试验证类子任务全部完成后再执行，确保打包的是经过验证的代码。
        如果任务纯粹是文档、设计或调研类，则不需要此子任务。

        只输出 JSON，不要有任何其他文字。
        """

        // Notify chat that decomposing has started
        dashboardViewModel?.chatMessagesByAgent["commander", default: []].append(ChatMessage(
            role: .assistant,
            content: "Starting task decomposition...",
            agentId: "commander"
        ))

        // Start staged status messages for the decompose phase
        startStagedMessages(messages: decomposeStageMessages, updateDecomposeStages: true)

        let commanderOutput = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-commander",
            message: decomposePrompt,
            vm: vm,
            channel: currentSession.id
        )

        // Stop staged messages once Commander responds
        stopStagedMessages()
        completeAllDecomposeStages()

        guard !isCancelled else {
            isRunning = false
            return
        }

        // Filter agent output to remove config warnings and system logs
        let cleanedOutput = DashboardViewModel.filterAgentOutput(commanderOutput) ?? commanderOutput

        // Parse JSON response
        guard let jsonStr = extractJSON(from: cleanedOutput),
              let jsonData = jsonStr.data(using: .utf8) else {
            session?.summary = "Failed to decompose task"
            session?.finalResult = commanderOutput
            phase = .completed
            isRunning = false
            return
        }

        let response: CommanderDecomposeResponse
        if let decoded = try? JSONDecoder().decode(CommanderDecomposeResponse.self, from: jsonData) {
            response = decoded
        } else if let fallback = normalizeDecomposeJSON(jsonStr) {
            response = fallback
        } else {
            session?.summary = "Failed to decompose task"
            session?.finalResult = commanderOutput
            phase = .completed
            isRunning = false
            return
        }

        // Create subtasks
        let subtasks = response.tasks.map { task in
            CollabSubTask(
                id: task.id,
                title: task.title,
                agentId: task.agent,
                role: task.role,
                prompt: task.prompt,
                dependsOn: task.depends_on,
                needsRecruit: task.needs_recruit ?? false,
                affectedFiles: task.affected_files ?? []
            )
        }

        session?.summary = response.summary
        session?.subtasks = subtasks
        phase = .awaitingApproval
        isRunning = false

        // Notify chat about the decomposition result
        if let vm = dashboardViewModel {
            let recruitCount = subtasks.filter { $0.needsRecruit }.count
            let planLines = subtasks.map { task -> String in
                let badge = task.needsRecruit ? " [Recruit]" : (task.agentId != nil ? "" : " [Generic]")
                return "#\(task.id) \(task.title)\(badge)"
            }.joined(separator: "\n")
            var planMsg = "Task decomposed into \(subtasks.count) subtasks"
            if recruitCount > 0 {
                planMsg += " (\(recruitCount) require expert recruitment)"
            }
            planMsg += "：\n\(planLines)\n\nPlease confirm (type 'ok' or 'go') or continue discussing to adjust."
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: planMsg,
                agentId: "commander"
            ))
        }
    }

    // MARK: - Confirm and Execute

    func confirmAndExecute() async {
        guard let vm = dashboardViewModel else { return }
        phase = .executing
        isRunning = true

        // Build team roster: all unique agents participating in this session
        if let currentSession = session {
            // Collect all unique agent IDs from subtasks
            var allAgentIds: [String] = []
            var seen = Set<String>()
            for task in currentSession.subtasks {
                let agentId = task.agentId ?? task.role ?? "main"
                if seen.insert(agentId).inserted {
                    allAgentIds.append(agentId)
                }
            }

            // Determine which are already installed vs need recruitment
            let needsRecruitIds = Set(currentSession.subtasks.filter { $0.needsRecruit }.compactMap { $0.agentId })
            recruitEntries = allAgentIds.map { agentId in
                if needsRecruitIds.contains(agentId) {
                    return RecruitEntry(id: agentId, status: .pending)
                } else {
                    return RecruitEntry(id: agentId, status: .ready)
                }
            }

            // Recruit marketplace agents
            let recruitAgentIds = allAgentIds.filter { needsRecruitIds.contains($0) }
            if !recruitAgentIds.isEmpty {
                NSLog("[Collab] Auto-recruiting %d marketplace agents: %@",
                      recruitAgentIds.count, recruitAgentIds.joined(separator: ", "))

                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: "Recruiting \(recruitAgentIds.count) expert agents from market...",
                    agentId: "commander"
                ))

                for agentId in recruitAgentIds {
                    guard let entryIdx = recruitEntries.firstIndex(where: { $0.id == agentId }) else { continue }
                    recruitEntries[entryIdx].status = .recruiting

                    let success = await Self.recruitMarketplaceAgent(
                        agentId: agentId,
                        openclawService: vm.openclawService,
                        taskContext: [currentSession.taskDescription, currentSession.taskContext].joined(separator: "\n\n")
                    )
                    if success {
                        NSLog("[Collab] Successfully recruited: %@", agentId)
                        recruitEntries[entryIdx].status = .recruited
                    } else {
                        NSLog("[Collab] Failed to recruit: %@, will fallback to main", agentId)
                        recruitEntries[entryIdx].status = .failed
                        if var s = session {
                            for idx in s.subtasks.indices where s.subtasks[idx].agentId == agentId {
                                s.subtasks[idx].needsRecruit = false
                            }
                            session = s
                        }
                    }
                }

                vm.loadAvailableAgents()

                let successCount = recruitEntries.filter { $0.status == .recruited }.count
                let failedCount = recruitEntries.filter { $0.status == .failed }.count
                let readyCount = recruitEntries.filter { $0.status == .ready }.count
                var summaryText = "Team ready: \(readyCount) existing agents"
                if successCount > 0 { summaryText += ", \(successCount) newly recruited" }
                if failedCount > 0 { summaryText += ", \(failedCount) recruitment failed (using generic agent)" }
                summaryText += ", starting task execution..."
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: summaryText,
                    agentId: "commander"
                ))
            }
        }

        // Create shared collab directory for file-based context and progress
        if let currentSession = session {
            let collabDir = Self.collabDirPath(sessionId: currentSession.id)
            let fm = FileManager.default
            try? fm.createDirectory(atPath: collabDir, withIntermediateDirectories: true)

            // Write context.md — shared task background for all agents (includes clarify dialogue)
            let contextPath = (collabDir as NSString).appendingPathComponent("context.md")
            var contextLines: [String] = ["# Task Context"]

            // Append clarify dialogue if available
            if !clarifyHistory.isEmpty {
                contextLines.append("")
                contextLines.append("## 需求对话")
                contextLines.append("")
                for entry in clarifyHistory {
                    let prefix = entry.role == "commander" ? "🎯 Commander" : "👤 User"
                    contextLines.append("**\(prefix)**: \(entry.content)")
                    contextLines.append("")
                }
            }

            contextLines.append("## 需求总结")
            contextLines.append("")
            contextLines.append(currentSession.taskContext)
            contextLines.append("")
            contextLines.append("## Original Task")
            contextLines.append("")
            contextLines.append(currentSession.taskDescription)
            contextLines.append("")

            // Append coding conventions for code projects
            contextLines.append("## 编码规范（所有 Agent 必须遵守）")
            contextLines.append("")
            contextLines.append("""
            ### 命名规范
            - API 参数 / JSON 字段 / 数据库字段：统一 **snake_case**（如 `category_id`, `created_at`）
            - 前端组件文件名：**PascalCase**（如 `ArticleList.vue`, `FileUpload.tsx`）
            - 工具/配置文件名：**kebab-case**（如 `error-handler.js`, `vite.config.js`）
            - 环境变量：**UPPER_SNAKE_CASE**（如 `DATABASE_PATH`, `API_PORT`）
            - 所有 Agent 必须严格遵循架构设计文档中定义的字段名，不得自行更改命名风格

            ### API 响应格式
            - 统一使用：`{ "success": true/false, "data": {}, "message": "" }`
            - 错误响应：`{ "success": false, "message": "错误描述", "code": "ERROR_CODE" }`
            - 禁止各自发明不同的响应包装格式

            ### 分页
            - 请求参数：`page`（从 1 开始）+ `page_size`
            - 响应中包含：`total`, `page`, `page_size`, `total_pages`

            ### 日期时间
            - 统一使用 ISO 8601 格式：`YYYY-MM-DDTHH:mm:ssZ`
            - 数据库存储和 API 传输均使用此格式

            ### 端口约定
            - 后端服务默认端口：3000
            - 前端开发服务默认端口：5173
            - 前端通过代理（proxy）访问后端 API，代理路径 `/api` → `http://localhost:3000`

            ### 环境配置
            - 端口、数据库路径、密钥等通过 `.env` 文件配置，不得硬编码
            - 提供 `.env.example` 示例文件

            ### 认证（如适用）
            - 统一使用 Header：`Authorization: Bearer <token>`
            """)
            contextLines.append("")

            let contextContent = contextLines.joined(separator: "\n")
            try? contextContent.write(toFile: contextPath, atomically: true, encoding: .utf8)

            // Write plan.json — structured decomposition result
            var planTasks: [[String: Any]] = []
            for task in currentSession.subtasks {
                var dict: [String: Any] = [
                    "id": task.id,
                    "title": task.title,
                    "prompt": task.prompt,
                    "depends_on": task.dependsOn
                ]
                if let a = task.agentId { dict["agent"] = a }
                if let r = task.role { dict["role"] = r }
                planTasks.append(dict)
            }
            let planDict: [String: Any] = ["summary": currentSession.summary, "tasks": planTasks]
            if let planData = try? JSONSerialization.data(withJSONObject: planDict, options: .prettyPrinted) {
                let planPath = (collabDir as NSString).appendingPathComponent("plan.json")
                try? planData.write(to: URL(fileURLWithPath: planPath))
            }

            // Pre-create task subdirectories
            for task in currentSession.subtasks {
                let taskDir = (collabDir as NSString).appendingPathComponent(Self.taskDirName(task: task))
                try? fm.createDirectory(atPath: taskDir, withIntermediateDirectories: true)
                let artifactsDir = (taskDir as NSString).appendingPathComponent("artifacts")
                try? fm.createDirectory(atPath: artifactsDir, withIntermediateDirectories: true)
            }

            taskProgress = [:]

            // Report task-to-agent assignment before execution
            let assignmentLines = currentSession.subtasks.map { task -> String in
                let agentLabel: String
                if let aid = task.agentId, vm.availableAgents.contains(where: { $0.id == aid }) {
                    agentLabel = aid
                } else if let role = task.role {
                    agentLabel = "main (\(role))"
                } else {
                    agentLabel = "main"
                }
                let depDesc = task.dependsOn.isEmpty ? "" : " ← depends on #\(task.dependsOn.map { String($0) }.joined(separator: ", #"))"
                return "#\(task.id) \(task.title) → \(agentLabel)\(depDesc)"
            }.joined(separator: "\n")
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "Task assignments:\n\(assignmentLines)\n\nStarting execution...",
                agentId: "commander"
            ))
        }

        await executeSubtasks()

        guard !isCancelled else {
            isRunning = false
            return
        }

        // P1-3: Verify phase — auto-verify completed tasks
        await runVerifyPhase()

        guard !isCancelled else {
            isRunning = false
            return
        }

        phase = .summarizing
        await finalizeSummaryAndDeliver()
        isRunning = false
    }

    /// Shared finalization: summarize results, collect deliverables, generate README, post final summary to chat, mark completed.
    private func finalizeSummaryAndDeliver() async {
        await summarizeResults()

        // Collect all artifacts into deliverables/ directory, organized by subtask
        if let currentSession = session, let vm = dashboardViewModel {
            let collabDir = Self.collabDirPath(sessionId: currentSession.id)
            let deliverablesDir = "\(collabDir)/deliverables"
            let fm = FileManager.default
            try? fm.createDirectory(atPath: deliverablesDir, withIntermediateDirectories: true)

            var deliveredEntries: [(taskTitle: String, subDir: String, files: [String])] = []

            for task in currentSession.subtasks where task.status == .completed {
                let artifactsDir = "\(collabDir)/\(Self.taskDirName(task: task))/artifacts"
                guard let files = try? fm.contentsOfDirectory(atPath: artifactsDir),
                      !files.filter({ !$0.hasPrefix(".") }).isEmpty else { continue }

                let subDirName = "task-\(task.id)-\(Self.sanitizeDirName(task.title))"
                let taskDeliverDir = "\(deliverablesDir)/\(subDirName)"
                try? fm.createDirectory(atPath: taskDeliverDir, withIntermediateDirectories: true)

                var copiedFiles: [String] = []
                for file in files where !file.hasPrefix(".") {
                    let src = "\(artifactsDir)/\(file)"
                    let dst = "\(taskDeliverDir)/\(file)"
                    try? fm.removeItem(atPath: dst)
                    try? fm.copyItem(atPath: src, toPath: dst)
                    copiedFiles.append(file)
                }
                if !copiedFiles.isEmpty {
                    deliveredEntries.append((taskTitle: task.title, subDir: subDirName, files: copiedFiles))
                }
            }

            // Generate README.md for the deliverables directory
            if !deliveredEntries.isEmpty {
                await generateDeliverablesReadme(
                    deliverablesDir: deliverablesDir,
                    entries: deliveredEntries,
                    vm: vm
                )
            }

            // Report deliverables to user
            if deliveredEntries.isEmpty {
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: "项目未产出交付文件。",
                    agentId: "commander"
                ))
            } else {
                var lines: [String] = []
                for entry in deliveredEntries {
                    lines.append("📁 \(entry.subDir)/")
                    for file in entry.files {
                        lines.append("   - \(file)")
                    }
                }
                let fileTree = lines.joined(separator: "\n")
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: "交付文件已汇总至：\n\(deliverablesDir)\n\n\(fileTree)",
                    agentId: "commander"
                ))
            }
        }

        // Append final summary to chat so user sees the result
        if let finalResult = session?.finalResult, let vm = dashboardViewModel {
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: finalResult,
                agentId: "commander"
            ))
        }

        phase = .completed
    }

    /// Generate a README.md in the deliverables directory summarizing the project and how to use it.
    private func generateDeliverablesReadme(
        deliverablesDir: String,
        entries: [(taskTitle: String, subDir: String, files: [String])],
        vm: DashboardViewModel
    ) async {
        guard let currentSession = session else { return }

        // Build directory tree description
        var treeLines: [String] = ["deliverables/"]
        for entry in entries {
            treeLines.append("├── \(entry.subDir)/")
            for (i, file) in entry.files.enumerated() {
                let prefix = (i == entry.files.count - 1) ? "│   └── " : "│   ├── "
                treeLines.append(prefix + file)
            }
        }
        treeLines.append("└── README.md")

        // Collect output.md summaries for context
        let collabDir = Self.collabDirPath(sessionId: currentSession.id)
        var taskSummaries: [String] = []
        for task in currentSession.subtasks where task.status == .completed {
            let outputPath = "\(collabDir)/\(Self.taskDirName(task: task))/output.md"
            let summary: String
            if let content = try? String(contentsOfFile: outputPath, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let truncated = content.count > 1000 ? String(content.prefix(1000)) + "..." : content
                summary = truncated
            } else if let result = task.result {
                let truncated = result.count > 500 ? String(result.prefix(500)) + "..." : result
                summary = truncated
            } else {
                summary = "(no summary)"
            }
            taskSummaries.append("### #\(task.id) \(task.title)\n\(summary)")
        }

        let readmePrompt = """
        [Your Role]
        你是 Commander（协调者），请根据以下信息为交付目录生成一份 README.md 文档。

        [Original Task]
        \(currentSession.taskDescription)

        [Task Context]
        \(currentSession.taskContext.prefix(1000))

        [Directory Structure]
        \(treeLines.joined(separator: "\n"))

        [Subtask Summaries]
        \(taskSummaries.joined(separator: "\n\n"))

        请生成 README.md，包含：
        1. 项目简介（一句话描述）
        2. 目录结构说明（每个子目录包含什么）
        3. 快速开始（如果是代码项目，给出安装依赖和启动命令；如果是文档项目，说明阅读顺序）
        4. 启动和关停脚本示例（如果适用）

        只输出 Markdown 内容，不要有任何额外说明。
        """

        let output = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-commander",
            message: readmePrompt,
            vm: vm,
            channel: currentSession.id
        )

        if let rawOutput = output {
            let filtered = DashboardViewModel.filterAgentOutput(rawOutput)
            if let content = filtered,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let readmePath = "\(deliverablesDir)/README.md"
                try? content.write(toFile: readmePath, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Recruit Marketplace Agent

    /// Install a marketplace agent by its sanitized ID. Returns true on success.
    static func recruitMarketplaceAgent(agentId: String, openclawService: OpenClawService, taskContext: String? = nil) async -> Bool {
        let catalog = MarketplaceCatalog.shared

        // Find matching marketplace agent
        guard let agent = catalog.agents.first(where: { marketplaceAgent in
            let sanitizedId = marketplaceAgent.id
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            return sanitizedId == agentId
        }) else {
            NSLog("[Collab] recruitMarketplaceAgent: agent %@ not found in catalog", agentId)
            return false
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // Step 0: Check if already installed
        let agentDir = "\(homeDir)/.openclaw/agents/\(agentId)/agent"
        if FileManager.default.fileExists(atPath: agentDir) {
            NSLog("[Collab] Agent %@ already installed", agentId)
            return true
        }

        // Step 1: Auto-pick model
        let modelsOutput = await openclawService.runCommand(
            "openclaw models list --json 2>&1",
            timeout: 30
        )
        let availableModels = SubAgentsViewModel.parseModelList(output: modelsOutput)
        let bestModel = availableModels.first(where: { $0.tags.contains("default") })
            ?? availableModels.first

        // Step 2: Create agent via CLI
        var cmd = "openclaw agents add '\(agentId)'"
        cmd += " --workspace '\(homeDir)/.openclaw/workspace-\(agentId)/'"
        cmd += " --agent-dir '\(homeDir)/.openclaw/agents/\(agentId)/agent/'"
        if let model = bestModel {
            cmd += " --model '\(model.id)'"
        }
        cmd += " --non-interactive --json 2>&1"

        NSLog("[Collab] Recruiting agent: %@, cmd: %@", agentId, cmd)
        let _ = await openclawService.runCommand(cmd, timeout: 30)

        // Step 3: Patch identity + model in openclaw.json
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        SubAgentsViewModel.patchAgentIdentity(
            configPath: configPath,
            agentId: agentId,
            name: agent.name
        )
        if let model = bestModel {
            SubAgentsViewModel.patchAgentModel(
                configPath: configPath,
                agentId: agentId,
                model: model.id
            )
        }

        // Step 4: Write persona files
        let workspace = "\(homeDir)/.openclaw/workspace-\(agentId)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: workspace, withIntermediateDirectories: true)

        let localeID = await MainActor.run {
            LanguageManager.shared.currentLocale.identifier
        }
        let identityContent = MarketplaceContentConverter.identityMarkdown(for: agent, localeID: localeID)
        let soulContent = MarketplaceContentConverter.soulMarkdown(for: agent, localeID: localeID)
        let agentsContent = MarketplaceContentConverter.agentsMarkdown(for: agent, localeID: localeID)
        let memoryContent = MarketplaceContentConverter.memoryMarkdown()

        try? identityContent.write(toFile: (workspace as NSString).appendingPathComponent("IDENTITY.md"),
                                    atomically: true, encoding: .utf8)
        try? soulContent.write(toFile: (workspace as NSString).appendingPathComponent("SOUL.md"),
                                atomically: true, encoding: .utf8)
        try? agentsContent.write(toFile: (workspace as NSString).appendingPathComponent("AGENTS.md"),
                                  atomically: true, encoding: .utf8)
        try? memoryContent.write(toFile: (workspace as NSString).appendingPathComponent("MEMORY.md"),
                                  atomically: true, encoding: .utf8)

        // Step 5: For awesome-design-system agent, prepare selected design-system references.
        if agentId == "awesome-design-system" {
            _ = await MainActor.run {
                DesignSystemManager.shared.prepareWorkspace(at: workspace, taskContext: taskContext)
            }
        }

        NSLog("[Collab] Agent %@ recruited successfully", agentId)
        return true
    }

    // MARK: - Build Agent Descriptions

    private func buildAgentDescriptions(vm: DashboardViewModel) -> String {
        // Section 1: Installed agents (detailed)
        let installedSection = vm.availableAgents
            .filter { $0.id != "commander" }
            .map { agent -> String in
                if agent.description.isEmpty {
                    return "- \(agent.id): \(agent.name)"
                } else {
                    return "- \(agent.id): \(agent.name) — \(agent.description)"
                }
            }
            .joined(separator: "\n")

        // Section 2: Marketplace agents not yet installed (condensed)
        let installedIds = Set(vm.availableAgents.map { $0.id })
        let catalog = MarketplaceCatalog.shared
        let marketplaceLines = catalog.agents
            .filter { agent in
                let sanitizedId = agent.id
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                return !installedIds.contains(sanitizedId)
            }
            .map { agent -> String in
                let sanitizedId = agent.id
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                var desc = "- \(sanitizedId): \(agent.name)"
                if let specialty = agent.specialty, !specialty.isEmpty {
                    desc += " | \(specialty)"
                }
                if let whenToUse = agent.whenToUse, !whenToUse.isEmpty {
                    desc += " | \(whenToUse)"
                }
                return desc
            }
            .joined(separator: "\n")

        var result = "[Available Agents]\n\(installedSection)"
        if !marketplaceLines.isEmpty {
            result += "\n\n[Marketplace Agents (需招募)]\n\(marketplaceLines)"
        }
        return result
    }

    // MARK: - DAG Execution Engine

    private func executeSubtasks() async {
        guard let vm = dashboardViewModel, var currentSession = session else { return }

        // Start a single timer to poll progress.md + scan files for all in-progress tasks
        let sessionId = currentSession.id
        let progressPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard !Task.isCancelled, let self = self, let s = self.session else { continue }
                let collabDir = Self.collabDirPath(sessionId: sessionId)
                let fm = FileManager.default
                for task in s.subtasks where task.status == .inProgress {
                    let taskDir = "\(collabDir)/\(Self.taskDirName(task: task))"

                    // 1. Check progress.md
                    let progressPath = "\(taskDir)/progress.md"
                    if let content = try? String(contentsOfFile: progressPath, encoding: .utf8),
                       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let lines = content
                            .components(separatedBy: "\n")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            .suffix(6)
                            .joined(separator: "\n")
                        self.taskProgress[task.id, default: TaskProgressInfo()].agentProgress = lines
                    }

                    // 2. Scan task directory for newly created files (artifacts + any workspace files)
                    var allFiles: [String] = []
                    // Scan artifacts/
                    if let artifactFiles = try? fm.contentsOfDirectory(atPath: "\(taskDir)/artifacts") {
                        allFiles.append(contentsOf: artifactFiles.filter { !$0.hasPrefix(".") }.map { "artifacts/\($0)" })
                    }
                    // Scan top-level task dir for agent-created files (exclude system files)
                    let systemFiles: Set<String> = ["progress.md", "progress-history.md", "output.md", "artifacts"]
                    if let topFiles = try? fm.contentsOfDirectory(atPath: taskDir) {
                        allFiles.append(contentsOf: topFiles.filter { !$0.hasPrefix(".") && !systemFiles.contains($0) })
                    }

                    let previousFiles = self.taskProgress[task.id]?.discoveredFiles ?? []
                    if allFiles != previousFiles {
                        self.taskProgress[task.id, default: TaskProgressInfo()].discoveredFiles = allFiles
                        if allFiles.count > previousFiles.count {
                            self.taskProgress[task.id]?.lastFileChangeTime = Date()
                        }
                    } else {
                        // Only trigger UI refresh every 30 seconds for elapsed time / stale detection
                        // This avoids excessive objectWillChange emissions that cause CPU spike
                        if self.taskProgress[task.id] != nil {
                            let lastRefresh = self.taskProgress[task.id]?.lastUIRefreshTime ?? .distantPast
                            if Date().timeIntervalSince(lastRefresh) > 30 {
                                self.taskProgress[task.id]?.lastUIRefreshTime = Date()
                                self.objectWillChange.send()
                            }
                        }
                    }
                }
            }
        }

        defer { progressPollTask.cancel() }

        while true {
            if isCancelled { break }

            // Refresh currentSession in case it was updated asynchronously
            guard let latestSession = session else { break }
            currentSession = latestSession

            // Build status lookup dictionary — O(N) once, then O(1) per lookup
            let statusMap = Dictionary(uniqueKeysWithValues: currentSession.subtasks.map { ($0.id, $0.status) })

            // Find tasks that are ready to execute (all dependencies completed or skipped)
            let readyIndices = currentSession.subtasks.indices.filter { idx in
                let task = currentSession.subtasks[idx]
                guard task.status == .pending else { return false }
                return task.dependsOn.allSatisfy { depId in
                    statusMap[depId] == .completed || statusMap[depId] == .skipped
                }
            }

            if readyIndices.isEmpty {
                // No more tasks ready — either all done or stuck on dependencies
                // Add a small delay to prevent CPU spinning while waiting for current tasks
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                break
            }

            // Apply concurrency limit (0 = unlimited)
            var effectiveIndices: [Array<CollabSubTask>.Index]
            if config.maxConcurrency > 0 {
                effectiveIndices = Array(readyIndices.prefix(config.maxConcurrency))
            } else {
                effectiveIndices = readyIndices
            }

            // P2-4: File-set concurrency control — within the batch of ready tasks,
            // prevent tasks with overlapping affected_files from running in parallel.
            // Tasks that conflict with an already-selected task are deferred to the next iteration.
            effectiveIndices = {
                var selected: [Array<CollabSubTask>.Index] = []
                var claimedFiles = Set<String>()
                for idx in effectiveIndices {
                    let taskFiles = currentSession.subtasks[idx].affectedFiles
                    // Empty affectedFiles = unknown scope, allow parallel (optimistic)
                    guard !taskFiles.isEmpty else {
                        selected.append(idx)
                        continue
                    }
                    // Check if any of this task's files conflict with already-claimed files
                    let hasConflict = taskFiles.contains { candidate in
                        claimedFiles.contains { claimed in
                            candidate == claimed
                            || candidate.hasPrefix(claimed + "/")
                            || claimed.hasPrefix(candidate + "/")
                        }
                    }
                    if !hasConflict {
                        selected.append(idx)
                        for f in taskFiles { claimedFiles.insert(f) }
                    }
                }
                return selected
            }()

            // Mark ready tasks as in-progress
            for idx in effectiveIndices {
                currentSession.subtasks[idx].status = .inProgress
            }
            session = currentSession

            // Execute ready tasks in parallel
            await withTaskGroup(of: SubtaskResult.self) { group in
                for idx in effectiveIndices {
                    let task = currentSession.subtasks[idx]
                    group.addTask { [weak self] in
                        guard let self = self else {
                            return SubtaskResult(taskId: task.id, status: .failed, output: nil, artifactFiles: [], elapsed: 0, hasOutputMd: false)
                        }
                        return await self.executeOneSubtask(task)
                    }
                }

                let indexMap = Dictionary(uniqueKeysWithValues: currentSession.subtasks.enumerated().map { ($1.id, $0) })
                for await result in group {
                    if let idx = indexMap[result.taskId] {
                        let task = currentSession.subtasks[idx]
                        let agentLabel = task.agentId ?? task.role ?? "main"

                        switch result.status {
                        case .completed:
                            currentSession.subtasks[idx].status = .completed
                            currentSession.subtasks[idx].result = result.output
                            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                                role: .assistant,
                                content: "✅ #\(task.id) \(task.title) (\(agentLabel)) \(result.statusMessage), \(Int(result.elapsed))s",
                                agentId: "commander"
                            ))
                        case .incomplete:
                            currentSession.subtasks[idx].status = .failed(result.statusMessage)
                            currentSession.subtasks[idx].result = result.output  // preserve partial output for force_complete
                            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                                role: .assistant,
                                content: "⚠️ #\(task.id) \(task.title) (\(agentLabel)) \(result.statusMessage), \(Int(result.elapsed))s. Click ✓ to mark as completed",
                                agentId: "commander"
                            ))
                        case .failed:
                            currentSession.subtasks[idx].status = .failed(result.statusMessage)
                            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                                role: .assistant,
                                content: "❌ #\(task.id) \(task.title) (\(agentLabel)) failed: \(result.statusMessage)",
                                agentId: "commander"
                            ))
                        }
                        currentSession.subtasks[idx].elapsedTime = result.elapsed
                        session = currentSession
                    }
                }
            }

            // Small delay to prevent busy-waiting when waiting for task results
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }

    // MARK: - Execute Single Subtask

    private func executeOneSubtask(_ task: CollabSubTask) async -> SubtaskResult {
        let startTime = Date()

        guard let vm = dashboardViewModel, let currentSession = session else {
            return SubtaskResult(taskId: task.id, status: .failed, output: nil, artifactFiles: [], elapsed: 0, hasOutputMd: false)
        }
        let sessionTaskId = currentSession.id
        let collabDir = Self.collabDirPath(sessionId: sessionTaskId)
        let taskDir = "\(collabDir)/\(Self.taskDirName(task: task))"

        // B: Pre-create task directory and artifacts/ to ensure agent can write files
        try? FileManager.default.createDirectory(atPath: "\(taskDir)/artifacts", withIntermediateDirectories: true)

        // A: Put task prompt first, then append file protocol at the END for better LLM compliance
        var fullPrompt = """
        \(task.prompt)

        [完成协议 - 必须严格遵守]
        你的工作目录是：\(taskDir)

        ⚠️ 重要：所有产出文件必须放在 \(taskDir)/artifacts/ 目录下！
        不要在工作目录下创建新的子文件夹来放代码（如 my-project/），直接放到 artifacts/ 即可。
        如果是项目类任务，在 artifacts/ 下组织目录结构（如 artifacts/src/, artifacts/public/ 等）。

        执行顺序（严格按此顺序，不可跳过）：

        第一步（开始前）：将你的执行计划写入 \(taskDir)/progress.md
        - 必须在开始编码或任何实际工作之前完成
        - 列出你计划的步骤和预期产出

        第二步（执行中）：每完成一个阶段，更新 \(taskDir)/progress.md
        - 记录当前完成了什么、下一步做什么

        第三步（执行中）：将产出文件（代码、文档等）保存到 \(taskDir)/artifacts/
        - 再次强调：必须是 artifacts/ 目录，不要创建其他目录

        第四步（全部完成后）：将完成摘要写入 \(taskDir)/output.md
        - 内容包括：完成了什么、产出了哪些文件、关键实现说明
        - output.md 是系统判定任务完成的唯一依据，不写则任务视为未完成！
        """

        // Resume context — if progress-history.md exists, append prior attempts to prompt
        let progressHistoryPath = "\(taskDir)/progress-history.md"
        if let histContent = try? String(contentsOfFile: progressHistoryPath, encoding: .utf8),
           !histContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Limit to last N chars to cover recent attempts without bloating prompt
            let limit = config.progressHistoryLimit
            let trimmed = histContent.count > limit ? String(histContent.suffix(limit)) : histContent
            fullPrompt += """

            [断点续跑 - 重要]
            你之前已经执行过此任务但未完成。以下是历次尝试的进度记录：
            ---
            \(trimmed)
            ---
            工作目录 \(taskDir)/artifacts/ 中可能已有部分产出文件。
            请基于已有进度继续完成，不要重复已完成的工作。
            重点关注之前失败的原因，避免重蹈覆辙。
            """
        }

        // Determine agent and session
        let agentId: String
        var sessionId: String

        if let specificAgent = task.agentId,
           vm.availableAgents.contains(where: { $0.id == specificAgent }) {
            agentId = specificAgent
            sessionId = "getclawhub-collab-\(sessionTaskId)-\(specificAgent)-\(task.id)"
        } else {
            // Fallback to main with role injection
            agentId = "main"
            if let role = task.role {
                fullPrompt = "[Role: \(role)] \(fullPrompt)"
            }
            sessionId = "getclawhub-collab-\(sessionTaskId)-main-\(task.id)"
        }

        // Session merging: reuse predecessor's session for same-agent serial chains
        let subtaskMap = Dictionary(uniqueKeysWithValues: currentSession.subtasks.map { ($0.id, $0) })
        if task.dependsOn.count == 1,
           let depId = task.dependsOn.first,
           let depTask = subtaskMap[depId] {
            let depAgentId: String
            if let depSpecificAgent = depTask.agentId,
               vm.availableAgents.contains(where: { $0.id == depSpecificAgent }) {
                depAgentId = depSpecificAgent
            } else {
                depAgentId = "main"
            }
            if depAgentId == agentId {
                sessionId = "getclawhub-collab-\(sessionTaskId)-\(agentId)-\(depTask.id)"
            }
        }

        // P0-2: Initialize system-level progress tracking for this task
        let taskId = task.id
        taskProgress[taskId] = TaskProgressInfo(startTime: Date())

        // Run agent without streaming — avoid config warnings in real-time callbacks
        // Set workingDirectory to taskDir so agent's CWD is the task directory
        let output = await runAgentCommand(
            agentId: agentId,
            sessionId: sessionId,
            message: fullPrompt,
            vm: vm,
            workingDirectory: taskDir,
            channel: sessionTaskId
        )

        // Process has exited — mark it
        taskProgress[taskId]?.isProcessAlive = false

        let elapsed = Date().timeIntervalSince(startTime)
        let filteredOutput = DashboardViewModel.filterAgentOutput(output)
        let outputMdPath = "\(taskDir)/output.md"
        let artifactsPath = "\(taskDir)/artifacts"
        let fm = FileManager.default

        // Rescue misplaced files: if agent created directories/files outside artifacts/, move them in
        let systemEntries: Set<String> = ["progress.md", "progress-history.md", "output.md", "artifacts"]
        if let topEntries = try? fm.contentsOfDirectory(atPath: taskDir) {
            let misplaced = topEntries.filter { !$0.hasPrefix(".") && !systemEntries.contains($0) }
            if !misplaced.isEmpty {
                for entry in misplaced {
                    let src = "\(taskDir)/\(entry)"
                    let dst = "\(artifactsPath)/\(entry)"
                    try? fm.removeItem(atPath: dst)
                    try? fm.moveItem(atPath: src, toPath: dst)
                }
            }
        }

        let artifactFiles = (try? fm.contentsOfDirectory(atPath: artifactsPath))?.filter { !$0.hasPrefix(".") } ?? []

        // Determine result status and output content
        let hasOutputMd: Bool
        let resultOutput: String?
        let resultStatus: SubtaskResultStatus

        // Priority 1: output.md already written by agent
        if let fileContent = try? String(contentsOfFile: outputMdPath, encoding: .utf8),
           !fileContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasOutputMd = true
            resultOutput = fileContent
            resultStatus = .completed
        }
        // Priority 2: No output.md but artifacts exist — auto-generate output.md, treat as completed
        else if !artifactFiles.isEmpty {
            hasOutputMd = false
            let autoSummary = """
            # 任务完成（系统自动生成）

            ## 产出文件
            \(artifactFiles.map { "- \($0)" }.joined(separator: "\n"))

            ## Agent 输出摘要
            \(filteredOutput?.prefix(2000) ?? "(no output)")
            """
            try? autoSummary.write(toFile: outputMdPath, atomically: true, encoding: .utf8)
            resultOutput = autoSummary
            resultStatus = .completed
        }
        // Priority 3: Has stdout but no output.md and no artifacts — incomplete
        else if let fo = filteredOutput, !fo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasOutputMd = false
            resultOutput = fo
            resultStatus = .incomplete
        }
        // Priority 4: No output at all — failed
        else {
            hasOutputMd = false
            resultOutput = filteredOutput
            resultStatus = .failed
        }

        return SubtaskResult(
            taskId: taskId,
            status: resultStatus,
            output: resultOutput,
            artifactFiles: artifactFiles,
            elapsed: elapsed,
            hasOutputMd: hasOutputMd
        )
    }

    // MARK: - Verify Phase (P1-3)

    /// Run a verification agent to check the completed subtasks' output quality.
    /// Only runs if there are completed tasks with artifacts. Skipped if all tasks failed.
    private func runVerifyPhase() async {
        guard let vm = dashboardViewModel, let currentSession = session else { return }

        let completedTasks = currentSession.subtasks.filter { $0.status == .completed }
        guard !completedTasks.isEmpty else { return }

        // Collect all artifact info for verification
        let collabDir = Self.collabDirPath(sessionId: currentSession.id)
        var verifyItems: [String] = []
        var hasAnyArtifacts = false

        for task in completedTasks {
            let taskDir = "\(collabDir)/\(Self.taskDirName(task: task))"
            let artifactsPath = "\(taskDir)/artifacts"
            let artifactFiles = (try? FileManager.default.contentsOfDirectory(atPath: artifactsPath))?.filter { !$0.hasPrefix(".") } ?? []
            if !artifactFiles.isEmpty { hasAnyArtifacts = true }

            let outputContent: String
            if let content = try? String(contentsOfFile: "\(taskDir)/output.md", encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let truncated = content.count > 800 ? String(content.prefix(800)) + "..." : content
                outputContent = truncated
            } else {
                outputContent = "（无 output.md）"
            }

            let artifactList = artifactFiles.isEmpty ? "无" : artifactFiles.joined(separator: ", ")
            verifyItems.append("""
            #\(task.id) \(task.title)
            产出文件：\(artifactList)
            产出目录：\(artifactsPath)
            完成摘要：\(outputContent)
            """)
        }

        // Skip verification if no artifacts to check (pure text output tasks)
        guard hasAnyArtifacts else { return }

        phase = .verifying

        vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
            role: .assistant,
            content: "🔍 Starting auto-verification...",
            agentId: "commander"
        ))

        let verifyPrompt = """
        [Your Role]
        你是 Commander 的验证员。你的职责是检查以下已完成任务的产出质量。

        [Completed Tasks]
        \(verifyItems.joined(separator: "\n\n---\n\n"))

        [Original Task]
        \(currentSession.taskDescription)

        [验证要求]
        1. 检查每个任务的产出文件是否存在且内容不为空
        2. 检查产出内容是否与任务要求一致
        3. 如果产出包含代码文件，检查基本的语法完整性（文件是否截断、括号是否匹配等）
        4. 不要自己修改或补充任何文件内容

        [输出格式]
        对每个任务给出验证结果：
        - ✅ 通过：产出符合要求
        - ⚠️ 有问题：说明具体问题（如文件为空、内容与任务不符等）
        - ❌ 不合格：说明严重问题

        最后给出整体验证结论。
        """

        let output = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-verify",
            message: verifyPrompt,
            vm: vm
        )

        let filtered = DashboardViewModel.filterAgentOutput(output)
        if let verifyResult = filtered, !verifyResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "🔍 验证结果：\n\(verifyResult)",
                agentId: "commander"
            ))
        }
    }

    // MARK: - Summarize Results

    private func summarizeResults() async {
        guard let vm = dashboardViewModel, let currentSession = session else { return }

        var resultLines: [String] = []
        for task in currentSession.subtasks {
            let statusEmoji: String
            switch task.status {
            case .completed: statusEmoji = "✅"
            case .failed: statusEmoji = "❌"
            case .skipped: statusEmoji = "⏭️"
            default: statusEmoji = "⏳"
            }

            var line = "\(statusEmoji) #\(task.id) \(task.title)"
            if let result = task.result {
                let truncated = result.count > 500 ? String(result.prefix(500)) + "..." : result
                line += "\n结果：\(truncated)"
            }
            if case .failed(let err) = task.status {
                line += "\n错误：\(err)"
            }
            resultLines.append(line)
        }

        let summaryPrompt = """
        [Your Role]
        你是 Commander（协调者），你的职责是管理和协调 Agent 执行任务，而不是自己动手完成任务。
        你绝不能自己编写代码、生成内容或执行任何子任务的实际工作。

        [Task Results]
        \(resultLines.joined(separator: "\n\n"))

        [Original Task]
        \(currentSession.taskDescription)

        请根据以上所有子任务的执行结果，给出最终汇总报告。
        汇总报告只需要：
        1. 总结每个子任务的完成状态和产出
        2. 对失败的任务说明失败原因，并建议用户可以点击"重试"让 Agent 重新执行
        3. 整体完成度评估

        禁止事项：
        - 不要自己补写任何代码或内容来"补全"失败的任务
        - 不要在汇总中包含代码实现
        - 不要说"我来完成剩余部分"之类的话
        """

        let output = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-commander",
            message: summaryPrompt,
            vm: vm,
            channel: currentSession.id
        )

        let filtered = DashboardViewModel.filterAgentOutput(output)
        session?.finalResult = filtered
    }

    // MARK: - User Interventions

    /// Archive current progress.md into progress-history.md, then clean up progress.md and output.md.
    private func archiveAndCleanTaskProgress(taskId: Int) {
        taskProgress.removeValue(forKey: taskId)
        guard let taskDir = taskDirPath(taskId: taskId) else { return }

        let progressPath = "\(taskDir)/progress.md"
        let historyPath = "\(taskDir)/progress-history.md"
        let fm = FileManager.default

        // Append progress.md content to progress-history.md before removing
        if let progressContent = try? String(contentsOfFile: progressPath, encoding: .utf8),
           !progressContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            let attemptCount = (try? String(contentsOfFile: historyPath, encoding: .utf8))?
                .components(separatedBy: "--- Attempt #").count ?? 0
            let header = "\n\n--- Attempt #\(attemptCount + 1) @ \(timestamp) ---\n\n"
            if fm.fileExists(atPath: historyPath) {
                let handle = FileHandle(forWritingAtPath: historyPath)
                handle?.seekToEndOfFile()
                handle?.write(header.data(using: .utf8)!)
                handle?.write(progressContent.data(using: .utf8)!)
                handle?.closeFile()
            } else {
                try? (header + progressContent).write(toFile: historyPath, atomically: true, encoding: .utf8)
            }
        }

        try? fm.removeItem(atPath: progressPath)
        try? fm.removeItem(atPath: "\(taskDir)/output.md")
    }

    func skipTask(_ taskId: Int) async {
        guard var currentSession = session,
              let idx = currentSession.subtasks.firstIndex(where: { $0.id == taskId }) else { return }
        currentSession.subtasks[idx].status = .skipped
        session = currentSession

        // Re-trigger execution so downstream tasks that depend on this one can proceed
        await resumeExecutionIfNeeded()
    }

    /// Mark a failed task as completed (e.g. when the agent actually produced output but timed out)
    /// and re-trigger execution so downstream tasks can proceed.
    func forceCompleteTask(_ taskId: Int) async {
        guard var currentSession = session,
              let idx = currentSession.subtasks.firstIndex(where: { $0.id == taskId }) else { return }
        currentSession.subtasks[idx].status = .completed
        if currentSession.subtasks[idx].result == nil {
            // Try to read output.md as the result
            if let taskDir = taskDirPath(taskId: taskId) {
                let outputPath = "\(taskDir)/output.md"
                if let content = try? String(contentsOfFile: outputPath, encoding: .utf8),
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    currentSession.subtasks[idx].result = content
                }
            }
        }
        session = currentSession

        // Re-trigger execution so downstream tasks can proceed
        await resumeExecutionIfNeeded()
    }

    /// Recursively reset all downstream tasks that depend (directly or transitively) on the given taskId.
    private func resetDownstreamTasks(of taskId: Int, in currentSession: inout CollabSession) {
        for i in currentSession.subtasks.indices {
            guard currentSession.subtasks[i].dependsOn.contains(taskId) else { continue }
            // Skip if already pending (avoid infinite recursion on circular deps)
            guard currentSession.subtasks[i].status != .pending else { continue }

            let dep = currentSession.subtasks[i]
            currentSession.subtasks[i] = CollabSubTask(
                id: dep.id,
                title: dep.title,
                agentId: dep.agentId,
                role: dep.role,
                prompt: dep.prompt,
                dependsOn: dep.dependsOn,
                affectedFiles: dep.affectedFiles,
                status: .pending,
                result: nil,
                elapsedTime: nil
            )
            taskProgress.removeValue(forKey: dep.id)
            if let depTaskDir = taskDirPath(taskId: dep.id) {
                try? FileManager.default.removeItem(atPath: "\(depTaskDir)/progress.md")
                try? FileManager.default.removeItem(atPath: "\(depTaskDir)/output.md")
            }

            // Recurse: reset tasks that depend on this downstream task
            resetDownstreamTasks(of: dep.id, in: &currentSession)
        }
    }

    /// Resume the execution loop if there are still pending tasks with satisfied dependencies.
    private func resumeExecutionIfNeeded() async {
        guard let currentSession = session else { return }

        let hasPending = currentSession.subtasks.contains { $0.status == .pending }
        guard hasPending else {
            // All tasks done — check if we need to re-summarize
            let allDone = currentSession.subtasks.allSatisfy { task in
                switch task.status {
                case .completed, .skipped, .failed: return true
                default: return false
                }
            }
            if allDone {
                phase = .summarizing
                await finalizeSummaryAndDeliver()
            }
            return
        }

        isRunning = true
        await executeSubtasks()

        let allDone = session?.subtasks.allSatisfy { task in
            switch task.status {
            case .completed, .skipped, .failed: return true
            default: return false
            }
        } ?? false
        if allDone {
            phase = .summarizing
            await finalizeSummaryAndDeliver()
        }
        isRunning = false
    }

    func retryTask(_ taskId: Int) async {
        guard var currentSession = session,
              let idx = currentSession.subtasks.firstIndex(where: { $0.id == taskId }) else { return }

        currentSession.subtasks[idx].status = .pending
        currentSession.subtasks[idx].result = nil
        currentSession.subtasks[idx].elapsedTime = nil

        // Archive progress history and clean up
        archiveAndCleanTaskProgress(taskId: taskId)

        // Recursively reset all downstream tasks in the dependency chain
        resetDownstreamTasks(of: taskId, in: &currentSession)

        session = currentSession
        await resumeExecutionIfNeeded()
    }

    func cancelAll() {
        isCancelled = true
        isRunning = false
        taskProgress = [:]
        decomposeStages = []
        recruitEntries = []
        stopStagedMessages()

        guard var currentSession = session else { return }
        for idx in currentSession.subtasks.indices {
            if currentSession.subtasks[idx].status == .pending || currentSession.subtasks[idx].status == .inProgress {
                currentSession.subtasks[idx].status = .skipped
            }
        }
        session = currentSession
    }

    func modifyTask(_ taskId: Int, newPrompt: String) async {
        guard var currentSession = session,
              let idx = currentSession.subtasks.firstIndex(where: { $0.id == taskId }) else { return }

        // Create a modified subtask
        let old = currentSession.subtasks[idx]
        currentSession.subtasks[idx] = CollabSubTask(
            id: old.id,
            title: old.title,
            agentId: old.agentId,
            role: old.role,
            prompt: newPrompt,
            dependsOn: old.dependsOn,
            affectedFiles: old.affectedFiles,
            status: .pending,
            result: nil,
            elapsedTime: nil
        )

        // Archive progress history and clean up
        archiveAndCleanTaskProgress(taskId: taskId)

        // Recursively reset all downstream tasks in the dependency chain
        resetDownstreamTasks(of: taskId, in: &currentSession)

        session = currentSession

        await resumeExecutionIfNeeded()
    }

    /// Reassign a task to a different agent, optionally recruiting from marketplace if needed.
    func reassignTask(_ taskId: Int, to newAgentId: String) async {
        guard let vm = dashboardViewModel,
              var currentSession = session,
              let idx = currentSession.subtasks.firstIndex(where: { $0.id == taskId }) else { return }

        let old = currentSession.subtasks[idx]

        // Check if the new agent is already installed
        let isInstalled = vm.availableAgents.contains(where: { $0.id == newAgentId })

        if !isInstalled {
            // Try recruiting from marketplace
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "🔄 正在从市场招募 \(newAgentId)...",
                agentId: "commander"
            ))
            let success = await Self.recruitMarketplaceAgent(agentId: newAgentId, openclawService: vm.openclawService)
            if !success {
                vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: "❌ 招募 \(newAgentId) 失败，无法重新分配任务 #\(taskId)",
                    agentId: "commander"
                ))
                return
            }
            // Refresh agent list
            vm.loadAvailableAgents()
            vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                role: .assistant,
                content: "✅ \(newAgentId) 已招募成功",
                agentId: "commander"
            ))
        }

        // Reassign: update agentId, reset status
        currentSession.subtasks[idx] = CollabSubTask(
            id: old.id,
            title: old.title,
            agentId: newAgentId,
            role: old.role,
            prompt: old.prompt,
            dependsOn: old.dependsOn,
            affectedFiles: old.affectedFiles,
            status: .pending,
            result: nil,
            elapsedTime: nil
        )

        // Archive progress history and clean up
        archiveAndCleanTaskProgress(taskId: taskId)

        // Recursively reset downstream tasks
        resetDownstreamTasks(of: taskId, in: &currentSession)

        session = currentSession

        vm.chatMessagesByAgent["commander", default: []].append(ChatMessage(
            role: .assistant,
            content: "🔄 任务 #\(taskId) \(old.title) 已重新分配给 \(newAgentId)，开始执行",
            agentId: "commander"
        ))

        await resumeExecutionIfNeeded()
    }

    /// Route a user message to commander during collab, returns commander's reply
    func handleUserMessage(_ text: String) async -> String? {
        guard let vm = dashboardViewModel, let currentSession = session else { return nil }

        let statusContext = buildStatusContext()

        let chatPrompt = """
        [Your Role]
        你是 Commander（协调者），你的职责是管理和协调 Agent 执行任务，而不是自己动手完成任务。
        你绝不能自己编写代码、生成内容或执行任何子任务的实际工作。
        当任务失败或遇到问题时，你应该建议"重试（retry）"或"修改提示词（modify）"让 Agent 重新执行，
        而不是自己去完成这些任务。

        [Task Status]
        \(statusContext)

        [User Question]
        \(text)

        请根据当前任务状态回答用户的问题。
        可用的操作有：
        - retry（重试某个任务）
        - skip（跳过某个任务，下游任务继续执行）
        - force_complete（将失败的任务标记为已完成，适用于任务实际已有产出但因超时等原因被标记为失败的情况，下游任务会继续执行）
        - modify（修改任务提示词后重试）
        - reassign（将任务重新分配给其他 agent 执行，需提供 newAgentId，如果是市场上的 agent 会自动招募）
        - cancel_all（取消所有任务）

        当任务失败但实际已有产出时，优先使用 force_complete 让调度继续推进。
        当用户要求更换执行 agent 时，使用 reassign 并指定 newAgentId。
        JSON 格式示例：{"type":"action","action":"reassign","taskId":2,"newAgentId":"game-designer","message":"已将任务重新分配给 game-designer"}
        只输出 JSON，不要有任何其他文字。
        """

        let output = await runAgentCommand(
            agentId: "commander",
            sessionId: "getclawhub-collab-\(currentSession.id)-commander",
            message: chatPrompt,
            vm: vm,
            channel: currentSession.id
        )

        let filtered = DashboardViewModel.filterAgentOutput(output) ?? output

        // Try to parse as action response
        if let jsonStr = extractJSON(from: filtered),
           let jsonData = jsonStr.data(using: .utf8),
           let response = try? JSONDecoder().decode(CommanderActionResponse.self, from: jsonData) {

            // Handle action
            if response.type == "action", let action = response.action {
                switch action {
                case "skip":
                    if let taskId = response.taskId {
                        Task {
                            await skipTask(taskId)
                        }
                    }
                case "retry":
                    if let taskId = response.taskId {
                        Task {
                            await retryTask(taskId)
                        }
                    }
                case "force_complete":
                    if let taskId = response.taskId {
                        Task {
                            await forceCompleteTask(taskId)
                        }
                    }
                case "cancel_all":
                    cancelAll()
                case "modify":
                    if let taskId = response.taskId, let newPrompt = response.newPrompt {
                        Task {
                            await modifyTask(taskId, newPrompt: newPrompt)
                        }
                    }
                case "reassign":
                    if let taskId = response.taskId, let newAgentId = response.newAgentId {
                        Task {
                            await reassignTask(taskId, to: newAgentId)
                        }
                    }
                default:
                    break
                }
            }

            return response.message
        }

        // Fallback: return raw filtered output
        return filtered
    }

    // MARK: - Build Status Context

    func buildStatusContext() -> String {
        guard let currentSession = session else { return "No active collab session." }

        var lines: [String] = []
        lines.append("Task: \(currentSession.taskDescription)")
        lines.append("Summary: \(currentSession.summary)")
        lines.append("")

        for task in currentSession.subtasks {
            let statusStr: String
            switch task.status {
            case .pending:
                statusStr = "⏳ Pending"
            case .inProgress:
                statusStr = "🔄 In Progress"
            case .completed:
                let timeStr = task.elapsedTime.map { String(format: " (%.0fs)", $0) } ?? ""
                statusStr = "✅ Completed\(timeStr)"
            case .failed(let err):
                statusStr = "❌ Failed (\(err))"
            case .skipped:
                statusStr = "⏭️ Skipped"
            }

            let agentStr = task.agentId ?? (task.role.map { "main/\($0)" } ?? "main")
            lines.append("#\(task.id) \(task.title) — \(statusStr) [\(agentStr)]")

            // Append progress details for in-progress tasks
            if task.status == .inProgress {
                if let progress = getTaskProgress(taskId: task.id) {
                    let progressLines = progress.components(separatedBy: "\n").suffix(8)
                    for line in progressLines {
                        lines.append("   \(line)")
                    }
                }
            }
        }

        if let finalResult = currentSession.finalResult {
            lines.append("")
            lines.append("Final Result: \(finalResult)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Get Task Progress

    /// Returns the best available progress info for a task.
    /// Priority: progress.md file (structured) > system-level tracking (stdout).
    private func getTaskProgress(taskId: Int) -> String? {
        // Priority 1: progress.md file written by agent
        if let taskDir = taskDirPath(taskId: taskId) {
            let progressPath = "\(taskDir)/progress.md"
            if let content = try? String(contentsOfFile: progressPath, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
        }

        // Priority 2: system-level progress display text
        if let info = taskProgress[taskId], let display = info.displayText {
            return display
        }

        return nil
    }

    // MARK: - Run Agent Command

    private func runAgentCommand(agentId: String, sessionId: String, message: String, vm: DashboardViewModel, workingDirectory: String? = nil, channel: String? = nil, timeoutOverride: Int? = nil) async -> String? {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("getclawhub_collab_\(UUID().uuidString).txt")

        do {
            try message.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempFile) }

        let escapedPath = tempFile.path.replacingOccurrences(of: "'", with: "'\\''")
        let agentTimeoutSec = timeoutOverride ?? config.agentTimeout
        var command = "openclaw agent --agent \(agentId) --session-id \(sessionId) --timeout \(agentTimeoutSec)"
        if let channel = channel {
            command += " --channel \(channel)"
        }
        command += " -m \"$(cat '\(escapedPath)')\" 2>&1"

        // cd into workingDirectory so the agent process starts there
        if let cwd = workingDirectory {
            let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
            command = "cd '\(escapedCwd)' && \(command)"
        }

        let processTimeout = TimeInterval(agentTimeoutSec + 30)
        return await vm.openclawService.runCommand(command, timeout: processTimeout)
    }

    /// Streaming version of runAgentCommand — calls onOutput with accumulated output periodically.
    private func runAgentCommandStreaming(
        agentId: String,
        sessionId: String,
        message: String,
        vm: DashboardViewModel,
        workingDirectory: String? = nil,
        channel: String? = nil,
        timeoutOverride: Int? = nil,
        onOutput: @escaping @Sendable (String) -> Void
    ) async -> String? {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("getclawhub_collab_\(UUID().uuidString).txt")

        do {
            try message.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempFile) }

        let escapedPath = tempFile.path.replacingOccurrences(of: "'", with: "'\\''")
        let agentTimeoutSec = timeoutOverride ?? config.agentTimeout
        var command = "openclaw agent --agent \(agentId) --session-id \(sessionId) --timeout \(agentTimeoutSec)"
        if let channel = channel {
            command += " --channel \(channel)"
        }
        command += " -m \"$(cat '\(escapedPath)')\" 2>&1"

        // cd into workingDirectory so the agent process starts there
        if let cwd = workingDirectory {
            let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
            command = "cd '\(escapedCwd)' && \(command)"
        }

        let processTimeout = TimeInterval(agentTimeoutSec + 30)
        let result = await vm.openclawService.runCommandStreaming(command, timeout: processTimeout) { rawOutput in
            let filtered = DashboardViewModel.filterAgentOutput(rawOutput) ?? rawOutput
            onOutput(filtered)
        }

        switch result {
        case .completed(let output):
            return output
        case .timedOut(let partial):
            return partial
        }
    }

    // MARK: - Normalize Decompose JSON (Fallback)

    /// Fallback parser that maps alternative key names to the expected schema.
    /// Handles cases where the LLM returns keys like "task"→"summary", "subtasks"→"tasks",
    /// "name"→"title", "description"→"prompt", "assignedTo"→"agent", etc.
    private func normalizeDecomposeJSON(_ jsonStr: String) -> CommanderDecomposeResponse? {
        guard let data = jsonStr.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Normalize summary field
        let summary = (raw["summary"] as? String)
            ?? (raw["task"] as? String)
            ?? (raw["plan"] as? String)
            ?? (raw["overview"] as? String)
            ?? (raw["description"] as? String)
            ?? "任务拆解"

        // Normalize tasks array
        guard let rawTasks = (raw["tasks"] as? [[String: Any]])
            ?? (raw["subtasks"] as? [[String: Any]])
            ?? (raw["sub_tasks"] as? [[String: Any]])
            ?? (raw["steps"] as? [[String: Any]]) else {
            return nil
        }

        var tasks: [CommanderTask] = []
        for (index, rawTask) in rawTasks.enumerated() {
            let id = (rawTask["id"] as? Int) ?? (index + 1)

            let title = (rawTask["title"] as? String)
                ?? (rawTask["name"] as? String)
                ?? (rawTask["task"] as? String)
                ?? "子任务 \(id)"

            let agent = (rawTask["agent"] as? String)
                ?? (rawTask["assignedTo"] as? String)
                ?? (rawTask["assigned_to"] as? String)
                ?? (rawTask["agentId"] as? String)
                ?? (rawTask["agent_id"] as? String)

            let role = (rawTask["role"] as? String)

            let prompt = (rawTask["prompt"] as? String)
                ?? (rawTask["description"] as? String)
                ?? (rawTask["detail"] as? String)
                ?? (rawTask["instructions"] as? String)
                ?? title

            let dependsOn = (rawTask["depends_on"] as? [Int])
                ?? (rawTask["dependsOn"] as? [Int])
                ?? (rawTask["dependencies"] as? [Int])
                ?? []

            let needsRecruit = (rawTask["needs_recruit"] as? Bool)
                ?? (rawTask["needsRecruit"] as? Bool)
                ?? false

            let affectedFiles = (rawTask["affected_files"] as? [String])
                ?? (rawTask["affectedFiles"] as? [String])
                ?? (rawTask["target_files"] as? [String])
                ?? []

            tasks.append(CommanderTask(
                id: id,
                title: title,
                agent: agent,
                role: role,
                prompt: prompt,
                depends_on: dependsOn,
                needs_recruit: needsRecruit,
                affected_files: affectedFiles
            ))
        }

        guard !tasks.isEmpty else { return nil }
        return CommanderDecomposeResponse(summary: summary, tasks: tasks)
    }

    // MARK: - Extract JSON

    /// Extract JSON object from LLM output that may contain markdown fences or extra text
    func extractJSON(from output: String?) -> String? {
        guard let output = output else { return nil }

        // Strip ANSI codes
        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        // Try to find JSON within markdown code fences
        if let fenceStart = cleaned.range(of: "```json"),
           let fenceEnd = cleaned.range(of: "```", range: fenceStart.upperBound..<cleaned.endIndex) {
            let jsonContent = String(cleaned[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return jsonContent
        }

        // Try to find JSON in generic code fences
        if let fenceStart = cleaned.range(of: "```"),
           let fenceEnd = cleaned.range(of: "```", range: fenceStart.upperBound..<cleaned.endIndex) {
            let jsonContent = String(cleaned[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if jsonContent.hasPrefix("{") || jsonContent.hasPrefix("[") {
                return jsonContent
            }
        }

        // Try to find a JSON object directly
        if let braceStart = cleaned.firstIndex(of: "{"),
           let braceEnd = cleaned.lastIndex(of: "}") {
            let candidate = String(cleaned[braceStart...braceEnd])
            if let data = candidate.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return candidate
            }
        }

        return nil
    }

    // MARK: - Staged Status Messages

    /// All decompose stage labels (used to build checklist)
    private let decomposeStageLabels = [
        "Starting task decomposition...",
        "正在匹配合适的 Agent...",
        "分析任务依赖关系...",
        "制定执行计划..."
    ]

    /// Start appending timed staged messages to chat during long-running phases.
    /// For decompose phase, also updates `decomposeStages` checklist.
    /// For research phase, updates `researchStages` checklist.
    private func startStagedMessages(messages: [(delay: TimeInterval, text: String)], updateDecomposeStages: Bool = false, updateResearchStages: Bool = false) {
        stopStagedMessages()

        if updateDecomposeStages {
            // Initialize all stages as pending, first one as inProgress
            decomposeStages = decomposeStageLabels.enumerated().map { idx, label in
                DecomposeStage(id: idx, text: label, status: idx == 0 ? .inProgress : .pending)
            }
        }

        if updateResearchStages {
            researchStages = researchStageLabels.enumerated().map { idx, label in
                DecomposeStage(id: idx, text: label, status: idx == 0 ? .inProgress : .pending)
            }
        }

        stagedMessageTask = Task { [weak self] in
            for (msgIndex, entry) in messages.enumerated() {
                try? await Task.sleep(nanoseconds: UInt64(entry.delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.dashboardViewModel?.chatMessagesByAgent["commander", default: []].append(ChatMessage(
                    role: .assistant,
                    content: entry.text,
                    agentId: "commander"
                ))

                if updateDecomposeStages, let self = self {
                    // Mark current stage completed, next one inProgress
                    // msgIndex maps to decomposeStageLabels[msgIndex + 1] since first label is set at init
                    let stageIdx = msgIndex + 1  // +1 because first stage was set at init
                    if stageIdx < self.decomposeStages.count {
                        // Complete previous stage
                        if stageIdx > 0 {
                            self.decomposeStages[stageIdx - 1].status = .completed
                        }
                        self.decomposeStages[stageIdx].status = .inProgress
                    }
                }

                if updateResearchStages, let self = self {
                    let stageIdx = msgIndex + 1
                    if stageIdx < self.researchStages.count {
                        if stageIdx > 0 {
                            self.researchStages[stageIdx - 1].status = .completed
                        }
                        self.researchStages[stageIdx].status = .inProgress
                    }
                }
            }
        }
    }

    /// Mark all decompose stages as completed
    private func completeAllDecomposeStages() {
        for i in decomposeStages.indices {
            decomposeStages[i].status = .completed
        }
    }

    /// Mark all research stages as completed
    private func completeAllResearchStages() {
        for i in researchStages.indices {
            researchStages[i].status = .completed
        }
    }

    private func stopStagedMessages() {
        stagedMessageTask?.cancel()
        stagedMessageTask = nil
    }

    /// Staged messages for the clarify phase
    private var clarifyStageMessages: [(delay: TimeInterval, text: String)] {
        [
            (delay: 8,  text: "正在评估任务复杂度..."),
            (delay: 10, text: "确认是否需要更多信息...")
        ]
    }

    /// Staged messages for the decompose phase (delays between each)
    private var decomposeStageMessages: [(delay: TimeInterval, text: String)] {
        [
            (delay: 10, text: "正在匹配合适的 Agent..."),
            (delay: 10, text: "分析任务依赖关系..."),
            (delay: 15, text: "制定执行计划...")
        ]
    }

    /// All research stage labels (used to build checklist)
    private let researchStageLabels = [
        "扫描项目文件结构...",
        "识别相关代码模块...",
        "分析架构模式...",
        "整理调研结果..."
    ]

    /// Staged messages for the research phase
    private var researchStageMessages: [(delay: TimeInterval, text: String)] {
        [
            (delay: 10, text: "正在识别相关代码模块..."),
            (delay: 15, text: "分析架构模式和依赖关系..."),
            (delay: 20, text: "整理调研结果...")
        ]
    }

    // MARK: - Computed Properties

    var isDecomposing: Bool {
        phase == .decomposing
    }

    var isResearching: Bool {
        phase == .researching
    }

    var isClarifying: Bool {
        phase == .clarifying
    }

    var completedCount: Int {
        session?.subtasks.filter { $0.status == .completed }.count ?? 0
    }

    var totalCount: Int {
        session?.subtasks.count ?? 0
    }

    var progressText: String {
        "\(completedCount)/\(totalCount)"
    }
}
