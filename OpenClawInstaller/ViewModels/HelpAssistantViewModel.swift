import Foundation
import Combine

// MARK: - Help Message Model

struct HelpMessage: Identifiable {
    let id = UUID()
    let role: HelpRole
    let content: String

    enum HelpRole {
        case user
        case assistant
    }
}

// MARK: - Help Assistant ViewModel

@MainActor
class HelpAssistantViewModel: ObservableObject {
    @Published var messages: [HelpMessage] = []
    @Published var isLoading = false
    @Published var inputText = ""

    private weak var dashboardViewModel: DashboardViewModel?
    private let faqMatcher = HelpFAQMatcher.shared
    private var userGuideContent: String = ""

    var isServiceRunning: Bool {
        dashboardViewModel?.openclawService.status == .running
    }

    var currentTab: DashboardViewModel.DashboardTab? {
        dashboardViewModel?.selectedTab
    }

    init(dashboardViewModel: DashboardViewModel) {
        self.dashboardViewModel = dashboardViewModel
        loadUserGuide()
    }

    // MARK: - User Guide Loading

    private func loadUserGuide() {
        if let url = Bundle.main.url(forResource: "用户指南", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            userGuideContent = content
        }
    }

    // MARK: - Ensure Help Agent

    /// Create a dedicated help-assistant agent in openclaw.json if it doesn't exist.
    /// Also ensures IDENTITY.md and SOUL.md are written to the workspace directory
    /// (openclaw reads persona from workspace, not agentDir).
    private func ensureHelpAgent() {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var agentsSection = json["agents"] as? [String: Any] ?? [:]
        var agentList = agentsSection["list"] as? [[String: Any]] ?? []

        let agentDir = NSString("~/.openclaw/agents/help-assistant/agent").expandingTildeInPath
        let workspaceDir = NSString("~/.openclaw/workspace-help-assistant").expandingTildeInPath

        // Always ensure SOUL.md and IDENTITY.md are up-to-date in the workspace
        try? FileManager.default.createDirectory(atPath: workspaceDir, withIntermediateDirectories: true)

        let soulContent = buildSoulContent()
        let soulPath = (workspaceDir as NSString).appendingPathComponent("SOUL.md")
        try? soulContent.write(toFile: soulPath, atomically: true, encoding: .utf8)

        let identityContent = """
        # IDENTITY.md - Who Am I?

        - **Name:** Help Assistant
        - **Creature:** GetClawHub Customer Support Bot
        - **Vibe:** Concise, practical, helpful
        - **Emoji:** ❓
        """
        let identityPath = (workspaceDir as NSString).appendingPathComponent("IDENTITY.md")
        try? identityContent.write(toFile: identityPath, atomically: true, encoding: .utf8)

        // Check if agent already exists in config
        if agentList.contains(where: { ($0["id"] as? String) == "help-assistant" }) {
            return
        }

        // Create agent directory
        try? FileManager.default.createDirectory(atPath: agentDir, withIntermediateDirectories: true)

        let entry: [String: Any] = [
            "id": "help-assistant",
            "name": "help-assistant",
            "default": false,
            "identity": [
                "name": "Help Assistant",
                "emoji": "❓"
            ],
            "agentDir": agentDir,
            "workspace": workspaceDir
        ]
        agentList.append(entry)
        agentsSection["list"] = agentList
        json["agents"] = agentsSection

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Build SOUL.md Content

    /// Build the SOUL.md persona content for the Help Assistant agent.
    /// This is written to the workspace so openclaw loads it as the agent's system prompt.
    private func buildSoulContent() -> String {
        var parts: [String] = []

        parts.append("""
        # SOUL.md - GetClawHub Help Assistant

        ## You Are

        You are the GetClawHub Help Assistant, a customer support bot exclusively for the GetClawHub macOS application.

        ## Rules

        1. ONLY answer questions related to GetClawHub usage, features, configuration, and troubleshooting.
        2. If the user asks anything unrelated to GetClawHub (coding help, general knowledge, casual chat, etc.), politely decline and say: "This question is beyond my scope. Please use the Chat page to ask your AI assistant." (Use the user's language for this response.)
        3. ALWAYS reply in the same language the user uses. If the user writes in Chinese, reply in Chinese. If in English, reply in English. Match the user's language exactly.
        4. Keep answers concise, practical, and step-by-step.
        5. When referencing app pages, use their exact names: Chat, Status, Persona, Multi-Agent, Configuration, Skills, Models, Channels, Plugins, Cron, Logs, Doctor.
        """)

        if !userGuideContent.isEmpty {
            parts.append("""
            ## User Guide

            Below is the complete GetClawHub User Guide. Base all your answers on this document:

            ---
            \(userGuideContent)
            ---
            """)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Send Question

    func sendQuestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(HelpMessage(role: .user, content: trimmed))
        inputText = ""

        if isServiceRunning {
            sendToAI(trimmed)
        } else {
            answerFromFAQ(trimmed)
        }
    }

    // MARK: - AI Mode

    private func sendToAI(_ question: String) {
        guard let vm = dashboardViewModel else { return }

        isLoading = true

        // Ensure the dedicated help-assistant agent exists with up-to-date SOUL.md
        ensureHelpAgent()

        // Only inject dynamic context (app state) — static persona is in SOUL.md
        let contextInfo = buildContextInfo()
        let fullMessage: String
        if contextInfo.isEmpty {
            fullMessage = question
        } else {
            fullMessage = """
            [Current App Context]
            \(contextInfo)

            [User Question]
            \(question)
            """
        }

        // Write to temp file to avoid shell escaping issues with large content (12KB+ user guide)
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("getclawhub_help_\(UUID().uuidString).txt")

        Task {
            defer { try? FileManager.default.removeItem(at: tempFile) }

            do {
                try fullMessage.write(to: tempFile, atomically: true, encoding: .utf8)
            } catch {
                messages.append(HelpMessage(role: .assistant, content: "Sorry, I could not get a response. Please try again."))
                isLoading = false
                return
            }

            let escapedPath = tempFile.path.replacingOccurrences(of: "'", with: "'\\''")
            // Use dedicated help-assistant agent to avoid polluting the main chat session.
            let command = "openclaw agent --agent help-assistant -m \"$(cat '\(escapedPath)')\" 2>&1"
            let output = await vm.openclawService.runCommand(command, timeout: 120)
            let reply = Self.filterOutput(output)

            messages.append(HelpMessage(role: .assistant, content: reply ?? "Sorry, I could not get a response. Please try again."))
            isLoading = false
        }
    }

    // MARK: - FAQ Mode

    private func answerFromFAQ(_ question: String) {
        if let item = faqMatcher.match(question) {
            let answer = faqMatcher.answer(for: item, input: question)
            messages.append(HelpMessage(role: .assistant, content: answer))
        } else {
            let fallback = faqMatcher.fallbackAnswer(for: question)
            messages.append(HelpMessage(role: .assistant, content: fallback))
        }
    }

    // MARK: - Context Info Builder

    /// Build dynamic context about current app state to inject into messages.
    /// Static persona and user guide are in SOUL.md (loaded by openclaw automatically).
    private func buildContextInfo() -> String {
        guard let vm = dashboardViewModel else { return "" }

        let tabName = vm.selectedTab.rawValue
        let serviceStatus = vm.openclawService.status.rawValue
        let version = vm.openclawService.version.isEmpty ? "Unknown" : vm.openclawService.version
        let port = vm.openclawService.port
        let provider = vm.editedSelectedProviderKey.isEmpty ? "Not configured" : vm.editedSelectedProviderKey

        return """
        - Active page: \(tabName)
        - Service status: \(serviceStatus)
        - OpenClaw version: \(version)
        - Configured provider: \(provider)
        - Port: \(port)
        """
    }

    // MARK: - Output Filtering

    /// Filter raw CLI output, removing ANSI codes and noise lines.
    /// Aligned with DashboardViewModel.filterAgentOutput.
    private static func filterOutput(_ output: String?) -> String? {
        guard let raw = output, !raw.isEmpty else { return nil }

        let ansiPattern = "\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = raw.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        let lines = cleaned.components(separatedBy: "\n")
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return true }
            if trimmed.hasPrefix("[agent-scope]") { return false }
            if trimmed.hasPrefix("[plugins]") { return false }
            if trimmed.hasPrefix("[cli]") { return false }
            if trimmed.hasPrefix("Config warnings:") { return false }
            if trimmed.hasPrefix("Config overwrite:") { return false }
            if trimmed.hasPrefix("- plugins.") { return false }
            if trimmed.hasPrefix("- ") && trimmed.contains("plugin") && trimmed.contains("detected") { return false }
            if trimmed.contains("plugins.allow is empty") { return false }
            if trimmed.contains("Multiple agents marked default") { return false }
            if ["◻", "◼", "━"].contains(where: { trimmed.hasPrefix($0) }) { return false }
            return true
        }

        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Quick Questions

    func quickQuestions(for tab: DashboardViewModel.DashboardTab) -> [(String, String)] {
        switch tab {
        case .status:
            return [
                ("服务启动不了怎么办？", "What if the service won't start?"),
                ("如何重启服务？", "How to restart the service?"),
                ("如何查看系统信息？", "How to view system info?"),
            ]
        case .config:
            return [
                ("如何配置模型？", "How to configure models?"),
                ("如何修改端口？", "How to change the port?"),
                ("Provider 怎么切换？", "How to switch providers?"),
            ]
        case .chat:
            return [
                ("如何使用斜杠命令？", "How to use slash commands?"),
                ("如何切换 AI 助手？", "How to switch AI assistant?"),
                ("历史消息怎么查看？", "How to view message history?"),
            ]
        case .cron:
            return [
                ("如何创建定时任务？", "How to create a cron job?"),
                ("Cron 表达式怎么写？", "How to write cron expressions?"),
                ("如何暂停任务？", "How to pause a task?"),
            ]
        case .persona:
            return [
                ("如何编辑 AI 性格？", "How to edit AI personality?"),
                ("四个文件分别是什么？", "What are the four files?"),
                ("如何预览效果？", "How to preview changes?"),
            ]
        case .subAgents:
            return [
                ("如何创建子代理？", "How to create a sub-agent?"),
                ("如何在 Chat 中切换 AI？", "How to switch AI in Chat?"),
                ("如何删除子代理？", "How to delete a sub-agent?"),
            ]
        case .skills:
            return [
                ("如何安装新技能？", "How to install a skill?"),
                ("技能状态含义？", "What do skill statuses mean?"),
                ("去哪找更多技能？", "Where to find more skills?"),
            ]
        case .models:
            return [
                ("如何设置默认模型？", "How to set the default model?"),
                ("什么是 Fallback？", "What is Fallback?"),
                ("如何添加图像模型？", "How to add an image model?"),
            ]
        case .channels:
            return [
                ("如何连接 Telegram？", "How to connect Telegram?"),
                ("渠道状态灯含义？", "What do channel status lights mean?"),
                ("如何删除渠道？", "How to remove a channel?"),
            ]
        case .plugins:
            return [
                ("如何启用插件？", "How to enable a plugin?"),
                ("有哪些可用插件？", "What plugins are available?"),
                ("插件状态含义？", "What do plugin statuses mean?"),
            ]
        case .logs:
            return [
                ("如何搜索日志？", "How to search logs?"),
                ("日志颜色含义？", "What do log colors mean?"),
                ("如何导出日志？", "How to export logs?"),
            ]
        case .budget:
            return [
                ("如何设置预算？", "How to set a budget?"),
                ("预算告警怎么用？", "How do budget alerts work?"),
                ("如何查看费用？", "How to view costs?"),
            ]
        case .billing:
            return [
                ("如何查看账单？", "How to view billing?"),
                ("Key 的消费额度是多少？", "What is the spend limit for a key?"),
                ("账单多久重置？", "How often does the budget reset?"),
            ]
        case .market:
            return [
                ("如何安装智能体？", "How to install an agent?"),
                ("市场里都有什么？", "What's in the marketplace?"),
                ("如何卸载智能体？", "How to uninstall an agent?"),
            ]
        case .tasksLogs:
            return [
                ("如何创建定时任务？", "How to create a cron job?"),
                ("如何暂停自动化？", "How to pause automation?"),
                ("如何编辑自动化？", "How to edit automation?"),
            ]
        case .outputs:
            return [
                ("Outputs 里显示什么？", "What appears in Outputs?"),
                ("为什么看不到配置文件？", "Why are config files hidden?"),
                ("如何打开生成文件？", "How to open generated files?"),
            ]
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}
