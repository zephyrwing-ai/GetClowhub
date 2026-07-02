import SwiftUI
import MarkdownUI

struct MarketplaceDetailView: View {
    let agent: MarketplaceAgent
    let openclawService: OpenClawService
    let onInstalled: (String) -> Void  // callback with agentId
    let onClose: () -> Void
    var onDismissDisabledChange: ((Bool) -> Void)? = nil

    @EnvironmentObject var languageManager: LanguageManager
    @State private var isInstalling = false
    @State private var isInstalled = false
    @State private var showContent = true
    @State private var installError: String?

    private var display: MarketplaceAgentDisplay {
        agent.localizedDisplay(localeID: languageManager.currentLocale.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.bottom, 16)

            Text(display.description)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.bottom, 18)

            if !display.vibe.isEmpty {
                Text(I18n.t("agents.detail.vibe"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                Text(display.vibe)
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.bottom, 18)
            }

            contentSection
        }
        .padding(28)
        .frame(width: 640)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 24, x: 0, y: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            checkInstalled()
            onDismissDisabledChange?(isInstalling)
        }
        .onDisappear {
            onDismissDisabledChange?(false)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            AgentAvatarImage(size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(display.name)
                    .font(.title)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text(display.division)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)

                    if !agent.color.isEmpty {
                        Circle()
                            .fill(Color(hex: agent.color))
                            .frame(width: 10, height: 10)
                    }
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                installButton

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isInstalling)
                .help(I18n.t("catalog.action.close"))
            }
        }
    }

    // MARK: - Install Button

    private var installButton: some View {
        CatalogActionButton(
            title: I18n.t("agents.action.recruit"),
            loadingTitle: I18n.t("agents.action.recruiting"),
            completedTitle: I18n.t("agents.action.recruited"),
            systemImage: "arrow.down.circle",
            state: recruitButtonState,
            width: 100,
            action: installAgent
        )
        .alert(I18n.t("agents.alert.recruitFailed"), isPresented: Binding<Bool>(
            get: { installError != nil },
            set: { if !$0 { installError = nil } }
        )) {
            Button(I18n.t("agents.alert.ok"), role: .cancel) {}
        } message: {
            Text(installError ?? "")
        }
    }

    private var recruitButtonState: CatalogActionButton.State {
        if isInstalling {
            return .loading
        }
        if isInstalled {
            return .completed
        }
        return .normal
    }

    // MARK: - Content Preview

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showContent.toggle()
                }
            } label: {
                HStack {
                    Text(I18n.t("agents.detail.personaContent"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: showContent ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showContent {
                ScrollView {
                    Markdown(display.content)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                }
                .frame(height: 344)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Install Logic

    private func checkInstalled() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let agentDir = "\(homeDir)/.openclaw/agents/\(sanitizedAgentId)/agent"
        isInstalled = FileManager.default.fileExists(atPath: agentDir)
    }

    private var sanitizedAgentId: String {
        // Convert agent id to a valid openclaw agent id (lowercase, alphanumeric + hyphens)
        agent.id
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func installAgent() {
        isInstalling = true
        onDismissDisabledChange?(true)
        let agentId = sanitizedAgentId
        let displayName = agent.name

        Task {
            // Step 0: Load available models to auto-pick the best one
            let modelsOutput = await openclawService.runCommand(
                "openclaw models list --json 2>&1",
                timeout: 30
            )
            let availableModels = SubAgentsViewModel.parseModelList(output: modelsOutput)
            let bestModel = availableModels.first(where: { $0.tags.contains("default") })
                ?? availableModels.first

            // Step 1: Create agent via CLI
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            var cmd = "openclaw agents add '\(agentId)'"
            cmd += " --workspace '\(homeDir)/.openclaw/workspace-\(agentId)/'"
            cmd += " --agent-dir '\(homeDir)/.openclaw/agents/\(agentId)/agent/'"
            if let model = bestModel {
                cmd += " --model '\(model.id)'"
            }
            cmd += " --non-interactive --json 2>&1"

            NSLog("[Marketplace] Installing agent: %@, model: %@, cmd: %@",
                  agentId, bestModel?.id ?? "(default)", cmd)
            let _ = await openclawService.runCommand(cmd, timeout: 30)

            // Step 2: Patch agent identity in openclaw.json
            let configPath = "\(homeDir)/.openclaw/openclaw.json"
            SubAgentsViewModel.patchAgentIdentity(
                configPath: configPath,
                agentId: agentId,
                name: displayName
            )

            // Step 3: Patch agent model in openclaw.json
            if let model = bestModel {
                SubAgentsViewModel.patchAgentModel(
                    configPath: configPath,
                    agentId: agentId,
                    model: model.id
                )
                NSLog("[Marketplace] Agent %@ model set to %@", agentId, model.id)
            }

            // Step 4: Write marketplace-converted persona files
            let workspace = "\(homeDir)/.openclaw/workspace-\(agentId)"
            let fm = FileManager.default
            try? fm.createDirectory(atPath: workspace, withIntermediateDirectories: true)

            let localeID = languageManager.currentLocale.identifier
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

            // Step 5: For awesome-design-system agent, prepare a lightweight design-system index.
            if agentId == "awesome-design-system" {
                _ = await MainActor.run {
                    DesignSystemManager.shared.prepareWorkspace(at: workspace)
                }
            }

            NSLog("[Marketplace] Agent %@ installed successfully", agentId)

            await MainActor.run {
                isInstalling = false
                onDismissDisabledChange?(false)
                isInstalled = true
                onInstalled(agentId)
            }
        }
    }
}

// MARK: - Color hex extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            // Try to match named colors
            switch hex.lowercased() {
            case "blue": r = 0.2; g = 0.4; b = 0.9
            case "red": r = 0.9; g = 0.2; b = 0.2
            case "green": r = 0.2; g = 0.8; b = 0.4
            case "purple": r = 0.6; g = 0.3; b = 0.8
            case "orange": r = 0.9; g = 0.5; b = 0.1
            case "yellow": r = 0.9; g = 0.8; b = 0.1
            case "pink": r = 0.9; g = 0.4; b = 0.6
            case "teal": r = 0.2; g = 0.7; b = 0.7
            case "indigo": r = 0.3; g = 0.2; b = 0.8
            case "cyan": r = 0.2; g = 0.8; b = 0.9
            default: r = 0.5; g = 0.5; b = 0.5
            }
        }
        self.init(red: r, green: g, blue: b)
    }
}
