import SwiftUI
import Combine

// MARK: - SubAgentsTabView

struct SubAgentsTabView: View {
    @StateObject private var viewModel: SubAgentsViewModel
    @State private var showCreateSheet = false
    @State private var showSaveSuccess = false
    @State private var saveSuccessMessage = ""
    @Environment(\.locale) private var locale

    init(openclawService: OpenClawService) {
        _viewModel = StateObject(wrappedValue: SubAgentsViewModel(openclawService: openclawService))
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Multi-Agent")
                            .font(.title2)
                            .fontWeight(.bold)

                        if !viewModel.agents.isEmpty {
                            Text("(\(viewModel.agents.count) agents)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { showCreateSheet = true }) {
                            Label("New Agent", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isPerformingAction)

                        Button(action: {
                            Task { await viewModel.loadAgents() }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.isLoading || viewModel.isPerformingAction)
                    }

                    if viewModel.isLoading && viewModel.agents.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading agents...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else if viewModel.agents.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "person.3")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)

                            Text("No agents yet")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text("Create an agent to specialize in different tasks")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                    } else {
                        // Agent card grid
                        AgentCardGrid(
                            agents: viewModel.agents,
                            expandedAgent: viewModel.expandedAgent,
                            isPerformingAction: viewModel.isPerformingAction,
                            availableModels: viewModel.availableModels,
                            onToggle: { id in viewModel.toggleExpand(id) },
                            onSave: { agent, file in
                                viewModel.save(agentId: agent.id, file: file)
                                let fileName: String
                                switch file {
                                case .identity: fileName = "IDENTITY.md"
                                case .soul: fileName = "SOUL.md"
                                case .memory: fileName = "MEMORY.md"
                                case .user: fileName = "USER.md"
                                }
                                showSaveToast(String(format: String(localized: "%@ %@ saved"), agent.name, fileName))
                            },
                            onSaveByName: { agent, fileName in
                                viewModel.saveByName(agentId: agent.id, fileName: fileName)
                                showSaveToast(String(format: String(localized: "%@ %@ saved"), agent.name, fileName))
                            },
                            onDelete: { agent in
                                let name = agent.name
                                Task {
                                    await viewModel.deleteAgent(agentId: agent.id)
                                    showSaveToast("Agent \"\(name)\" deleted")
                                }
                            },
                            onOpenWorkspace: { agent in
                                if !agent.workspace.isEmpty {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: agent.workspace)
                                }
                            },
                            onModelChange: { agent, model in
                                viewModel.updateModel(agentId: agent.id, model: model)
                                let shortModel = model.isEmpty ? "Default" : (model.components(separatedBy: "/").last ?? model)
                                showSaveToast(String(format: String(localized: "%@ model → %@"), agent.name, shortModel))
                            },
                            bindingForAgent: { agentId, file in
                                viewModel.binding(for: agentId, file: file)
                            },
                            bindingByNameForAgent: { agentId, fileName in
                                viewModel.bindingByName(for: agentId, fileName: fileName)
                            }
                        )
                    }
                }
                .padding(24)
            }
            .onChange(of: viewModel.expandedAgent) { newValue in
                if let agentId = newValue {
                    withAnimation {
                        scrollProxy.scrollTo("detail-\(agentId)", anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if showSaveSuccess {
                SuccessToast(message: saveSuccessMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if viewModel.isPerformingAction {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text(viewModel.actionMessage)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPerformingAction)
        .animation(.easeInOut, value: showSaveSuccess)
        .task {
            await viewModel.loadAgents()
            await viewModel.loadModels()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet(
                viewModel: viewModel,
                isPresented: $showCreateSheet,
                onCreated: { name in
                    showSaveToast("Agent \"\(name)\" created")
                }
            )
            .environment(\.locale, locale)
        }
    }

    private func showSaveToast(_ message: String) {
        saveSuccessMessage = message
        showSaveSuccess = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSaveSuccess = false
        }
    }
}

// MARK: - Agent Card Grid

private struct AgentCardGrid: View {
    let agents: [SubAgentInfo]
    let expandedAgent: String?
    let isPerformingAction: Bool
    let availableModels: [ModelOption]
    let onToggle: (String) -> Void
    let onSave: (SubAgentInfo, PersonaViewModel.FileType) -> Void
    let onSaveByName: (SubAgentInfo, String) -> Void
    let onDelete: (SubAgentInfo) -> Void
    let onOpenWorkspace: (SubAgentInfo) -> Void
    let onModelChange: (SubAgentInfo, String) -> Void
    let bindingForAgent: (String, PersonaViewModel.FileType) -> Binding<String>
    let bindingByNameForAgent: (String, String) -> Binding<String>

    private var rows: [[SubAgentInfo]] {
        stride(from: 0, to: agents.count, by: 3).map { i in
            Array(agents[i..<min(i + 3, agents.count)])
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                // Card row
                HStack(spacing: 12) {
                    ForEach(row) { agent in
                        AgentSummaryCard(
                            agent: agent,
                            isSelected: expandedAgent == agent.id,
                            isPerformingAction: isPerformingAction,
                            onToggle: { onToggle(agent.id) },
                            onDelete: { onDelete(agent) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                    // Fill remaining slots with invisible spacers
                    if row.count < 3 {
                        ForEach(0..<(3 - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }

                // Detail panel below the row containing the expanded agent
                if let expandedId = expandedAgent,
                   let agent = row.first(where: { $0.id == expandedId }) {
                    AgentDetailPanel(
                        agent: agent,
                        isPerformingAction: isPerformingAction,
                        availableModels: availableModels,
                        onClose: { onToggle(expandedId) },
                        onSave: { file in onSave(agent, file) },
                        onSaveByName: { fileName in onSaveByName(agent, fileName) },
                        onOpenWorkspace: { onOpenWorkspace(agent) },
                        onModelChange: { model in onModelChange(agent, model) },
                        identityContent: bindingForAgent(agent.id, .identity),
                        soulContent: bindingForAgent(agent.id, .soul),
                        memoryContent: bindingForAgent(agent.id, .memory),
                        userContent: bindingByNameForAgent(agent.id, "USER.md"),
                        agentsContent: bindingByNameForAgent(agent.id, "AGENTS.md"),
                        bootstrapContent: bindingByNameForAgent(agent.id, "BOOTSTRAP.md"),
                        heartbeatContent: bindingByNameForAgent(agent.id, "HEARTBEAT.md"),
                        toolsContent: bindingByNameForAgent(agent.id, "TOOLS.md")
                    )
                    .id("detail-\(expandedId)")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: expandedAgent)
    }
}

// MARK: - Agent Summary Card

private struct AgentSummaryCard: View {
    let agent: SubAgentInfo
    let isSelected: Bool
    let isPerformingAction: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                // Top-right delete button area
                HStack {
                    Spacer()
                    if !agent.isDefault && agent.id != "commander" && isHovering {
                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPerformingAction)
                        .transition(.opacity)
                    } else {
                        // Reserve space
                        Color.clear.frame(width: 14, height: 14)
                    }
                }

                // Emoji
                Text(agent.emoji)
                    .font(.system(size: 36))

                // Name
                Text(agent.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // ID
                Text(agent.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Model + Default tags
                HStack(spacing: 4) {
                    if !agent.model.isEmpty {
                        let shortModel = agent.model.components(separatedBy: "/").last ?? agent.model
                        TagView(text: shortModel, color: .blue)
                    }
                    if agent.isDefault {
                        TagView(text: "Default", color: .orange)
                    }
                }

                // Document status dots
                HStack(spacing: 8) {
                    DocStatusDot(label: "ID", hasContent: !agent.identityContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    DocStatusDot(label: "SOUL", hasContent: !agent.soulContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    DocStatusDot(label: "MEM", hasContent: !agent.memoryContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 6 : 2, y: isHovering ? 3 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .alert("Delete Agent", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("Delete \"\(agent.name)\"? This will remove the agent and its workspace.")
        }
    }
}

// MARK: - Doc Status Dot

private struct DocStatusDot: View {
    let label: String
    let hasContent: Bool

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(hasContent ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Agent Detail Panel

private struct AgentDetailPanel: View {
    let agent: SubAgentInfo
    let isPerformingAction: Bool
    let availableModels: [ModelOption]
    let onClose: () -> Void
    let onSave: (PersonaViewModel.FileType) -> Void
    let onSaveByName: (String) -> Void
    let onOpenWorkspace: () -> Void
    let onModelChange: (String) -> Void
    @Binding var identityContent: String
    @Binding var soulContent: String
    @Binding var memoryContent: String
    @Binding var userContent: String
    @Binding var agentsContent: String
    @Binding var bootstrapContent: String
    @Binding var heartbeatContent: String
    @Binding var toolsContent: String

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

                if !agent.workspace.isEmpty {
                    Button(action: onOpenWorkspace) {
                        Label("Open Workspace", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

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

            Divider()

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
                        ForEach(availableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 260)
                    .onChange(of: selectedModel) { newValue in
                        if newValue != agent.model {
                            onModelChange(newValue)
                        }
                    }
                }

                if !agent.workspace.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(agent.workspace.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

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
                    content: $identityContent,
                    isDirty: agent.identityDirty,
                    onSave: { onSave(.identity) },
                    initiallyExpanded: false
                )

                MarkdownFileEditor(
                    title: "SOUL.md",
                    icon: "heart.fill",
                    content: $soulContent,
                    isDirty: agent.soulDirty,
                    onSave: { onSave(.soul) },
                    initiallyExpanded: false
                )

                MarkdownFileEditor(
                    title: "MEMORY.md",
                    icon: "brain.head.profile",
                    content: $memoryContent,
                    isDirty: agent.memoryDirty,
                    onSave: { onSave(.memory) },
                    initiallyExpanded: false
                )

                // Additional .md files — only shown when present in workspace
                if !agent.userContent.isEmpty || !agent.userOriginal.isEmpty {
                    MarkdownFileEditor(
                        title: "USER.md",
                        icon: "person.fill",
                        content: $userContent,
                        isDirty: agent.userDirty,
                        onSave: { onSaveByName("USER.md") },
                        initiallyExpanded: false
                    )
                }

                if !agent.agentsContent.isEmpty || !agent.agentsOriginal.isEmpty {
                    MarkdownFileEditor(
                        title: "AGENTS.md",
                        icon: "person.3.fill",
                        content: $agentsContent,
                        isDirty: agent.agentsDirty,
                        onSave: { onSaveByName("AGENTS.md") },
                        initiallyExpanded: false
                    )
                }

                if !agent.bootstrapContent.isEmpty || !agent.bootstrapOriginal.isEmpty {
                    MarkdownFileEditor(
                        title: "BOOTSTRAP.md",
                        icon: "power",
                        content: $bootstrapContent,
                        isDirty: agent.bootstrapDirty,
                        onSave: { onSaveByName("BOOTSTRAP.md") },
                        initiallyExpanded: false
                    )
                }

                if !agent.heartbeatContent.isEmpty || !agent.heartbeatOriginal.isEmpty {
                    MarkdownFileEditor(
                        title: "HEARTBEAT.md",
                        icon: "heart.text.clipboard",
                        content: $heartbeatContent,
                        isDirty: agent.heartbeatDirty,
                        onSave: { onSaveByName("HEARTBEAT.md") },
                        initiallyExpanded: false
                    )
                }

                if !agent.toolsContent.isEmpty || !agent.toolsOriginal.isEmpty {
                    MarkdownFileEditor(
                        title: "TOOLS.md",
                        icon: "wrench.and.screwdriver",
                        content: $toolsContent,
                        isDirty: agent.toolsDirty,
                        onSave: { onSaveByName("TOOLS.md") },
                        initiallyExpanded: false
                    )
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        )
        .onAppear {
            selectedModel = agent.model
        }
    }
}

// MARK: - Tag View

struct TagView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Create Agent Sheet

struct CreateAgentSheet: View {
    @ObservedObject var viewModel: SubAgentsViewModel
    @Binding var isPresented: Bool
    var onCreated: ((String) -> Void)?
    var onCreatedWithId: ((String) -> Void)?

    @State private var agentId = ""
    @State private var displayName = ""
    @State private var selectedModel = ""
    @State private var selectedDivision = "Custom"

    private static let divisionOptions = [
        "Custom", "Academic", "Design", "Engineering", "Game Development",
        "Marketing", "Paid Media", "Product", "Project Management",
        "Sales", "Spatial Computing", "Specialized", "Support", "Testing"
    ]

    /// Sanitize input to valid agent ID chars (lowercase a-z, 0-9, hyphen)
    private var sanitizedId: String {
        let raw = agentId.trimmingCharacters(in: .whitespaces).lowercased()
        return String(raw.unicodeScalars.filter {
            CharacterSet.lowercaseLetters.contains($0) ||
            CharacterSet.decimalDigits.contains($0) ||
            $0 == "-"
        })
    }

    private var isIdValid: Bool {
        let id = sanitizedId
        return !id.isEmpty && id.first != "-" && id.last != "-"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Agent")
                    .font(.headline)

                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Agent ID
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent ID")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("e.g. news-helper", text: $agentId)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentId) { newValue in
                            // Auto-filter: only allow a-z, 0-9, hyphen
                            let filtered = String(newValue.lowercased().unicodeScalars.filter {
                                CharacterSet.lowercaseLetters.contains($0) ||
                                CharacterSet.decimalDigits.contains($0) ||
                                $0 == "-"
                            })
                            if filtered != newValue {
                                agentId = filtered
                            }
                        }

                    Text("Lowercase letters, numbers, hyphens only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Display Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display Name")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("e.g. News Helper", text: $displayName)
                        .textFieldStyle(.roundedBorder)

                    Text("Optional. Written to IDENTITY.md as the agent's name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Model picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if viewModel.availableModels.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("", selection: $selectedModel) {
                            Text("Default (inherit from config)").tag("")
                            ForEach(viewModel.availableModels) { model in
                                HStack {
                                    Text(model.name)
                                    if model.tags.contains("default") {
                                        Text("(default)")
                                    }
                                }
                                .tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                // Division picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Division")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("", selection: $selectedDivision) {
                        ForEach(Self.divisionOptions, id: \.self) { div in
                            Text(div).tag(div)
                        }
                    }
                    .labelsHidden()

                    Text("Agent category for sidebar grouping")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Create") {
                    let name = displayName.trimmingCharacters(in: .whitespaces)
                    let finalName = name.isEmpty ? sanitizedId : name
                    Task {
                        await viewModel.createAgent(
                            agentId: sanitizedId,
                            displayName: name,
                            model: selectedModel,
                            division: selectedDivision
                        )
                        isPresented = false
                        onCreated?(finalName)
                        onCreatedWithId?(sanitizedId)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isIdValid || viewModel.isPerformingAction)
            }
            .padding(16)
        }
        .frame(width: 420)
        .task {
            await viewModel.loadModels()
        }
    }
}

// MARK: - SubAgentInfo

struct SubAgentInfo: Identifiable {
    let id: String
    var name: String
    var emoji: String
    var creature: String
    var model: String
    var isDefault: Bool
    var bindingsCount: Int
    var bindingDetails: [String]
    var identitySource: String
    var workspace: String
    var agentDir: String

    var identityContent: String = ""
    var soulContent: String = ""
    var memoryContent: String = ""
    var userContent: String = ""
    var agentsContent: String = ""
    var bootstrapContent: String = ""
    var heartbeatContent: String = ""
    var toolsContent: String = ""

    var identityOriginal: String = ""
    var soulOriginal: String = ""
    var memoryOriginal: String = ""
    var userOriginal: String = ""
    var agentsOriginal: String = ""
    var bootstrapOriginal: String = ""
    var heartbeatOriginal: String = ""
    var toolsOriginal: String = ""

    var identityDirty: Bool { identityContent != identityOriginal }
    var soulDirty: Bool { soulContent != soulOriginal }
    var memoryDirty: Bool { memoryContent != memoryOriginal }
    var userDirty: Bool { userContent != userOriginal }
    var agentsDirty: Bool { agentsContent != agentsOriginal }
    var bootstrapDirty: Bool { bootstrapContent != bootstrapOriginal }
    var heartbeatDirty: Bool { heartbeatContent != heartbeatOriginal }
    var toolsDirty: Bool { toolsContent != toolsOriginal }
}

// MARK: - Model Option

struct ModelOption: Identifiable {
    let id: String   // key like "provider/model"
    let name: String
    let tags: [String]
}

// MARK: - SubAgentsViewModel

class SubAgentsViewModel: ObservableObject {
    private let openclawService: OpenClawService

    @Published var agents: [SubAgentInfo] = []
    @Published var expandedAgent: String?
    @Published var availableModels: [ModelOption] = []
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var actionMessage = ""

    init(openclawService: OpenClawService) {
        self.openclawService = openclawService
    }

    // MARK: - Load Agents via CLI

    func loadAgents() async {
        await MainActor.run { isLoading = true }
        NSLog("[SubAgents] loadAgents: calling openclaw agents list...")
        let output = await openclawService.runCommand(
            "openclaw agents list --json --bindings 2>&1",
            timeout: 60
        )
        NSLog("[SubAgents] loadAgents: output is %@, length=%d", output == nil ? "nil" : "non-nil", output?.count ?? 0)
        var parsed = Self.parseAgentList(output: output)

        // Load persona files for each agent
        for i in parsed.indices {
            let ws = parsed[i].workspace
            guard !ws.isEmpty else { continue }

            let identityContent = readFile(ws, "IDENTITY.md")
            let soulContent = readFile(ws, "SOUL.md")
            let memoryContent = readFile(ws, "MEMORY.md")
            let userContent = readFile(ws, "USER.md")
            let agentsContent = readFile(ws, "AGENTS.md")
            let bootstrapContent = readFile(ws, "BOOTSTRAP.md")
            let heartbeatContent = readFile(ws, "HEARTBEAT.md")
            let toolsContent = readFile(ws, "TOOLS.md")

            parsed[i].identityContent = identityContent
            parsed[i].soulContent = soulContent
            parsed[i].memoryContent = memoryContent
            parsed[i].userContent = userContent
            parsed[i].agentsContent = agentsContent
            parsed[i].bootstrapContent = bootstrapContent
            parsed[i].heartbeatContent = heartbeatContent
            parsed[i].toolsContent = toolsContent
            parsed[i].identityOriginal = identityContent
            parsed[i].soulOriginal = soulContent
            parsed[i].memoryOriginal = memoryContent
            parsed[i].userOriginal = userContent
            parsed[i].agentsOriginal = agentsContent
            parsed[i].bootstrapOriginal = bootstrapContent
            parsed[i].heartbeatOriginal = heartbeatContent
            parsed[i].toolsOriginal = toolsContent

            // Parse creature from IDENTITY.md
            let identity = PersonaViewModel.parseIdentity(identityContent)
            if !identity.creature.isEmpty {
                parsed[i].creature = identity.creature
            }
        }

        // Always synthesize a "main" entry from openclaw.json so the user sees
        // their primary agent (often customized — e.g. 蛋蛋) alongside any
        // sub-agents. The CLI's `openclaw agents list` typically only returns
        // sub-agents, which leaves users wondering where their main agent is.
        if !parsed.contains(where: { $0.id == "main" }),
           let mainInfo = Self.readMainAgentFromConfig() {
            parsed.insert(mainInfo, at: 0)
        }

        NSLog("[SubAgents] loadAgents: loaded %d agents, updating UI", parsed.count)
        await MainActor.run {
            // Filter out internal agents (help-assistant) from user-facing list
            agents = parsed.filter { !DashboardViewModel.internalAgentIds.contains($0.id) }
            isLoading = false
        }
    }

    /// Read the "main" agent stub from ~/.openclaw/openclaw.json and build a
    /// SubAgentInfo from it. Returns nil if the config is missing or the
    /// main entry can't be parsed. Mirrors DashboardViewModel.loadSelectedAgentDetail
    /// so the resulting card has the same persona files / display name as
    /// the sidebar agent picker.
    static func readMainAgentFromConfig() -> SubAgentInfo? {
        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath

        // The main agent is allowed to NOT exist in agents.list — openclaw
        // typically defines it solely via the workspace. Treat a missing
        // entry as an empty dict, and require only the workspace to exist.
        let entry: [String: Any] = {
            guard let data = FileManager.default.contents(atPath: configPath),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agents = json["agents"] as? [String: Any],
                  let list = agents["list"] as? [[String: Any]] else { return [:] }
            return list.first(where: { $0["id"] as? String == "main" }) ?? [:]
        }()

        // Resolve via the shared resolver so "main" maps to its real runtime
        // dir (e.g. workspace-main when main isn't the default agent), not the
        // stale bare ~/.openclaw/workspace.
        let workspace = DashboardViewModel.resolveAgentWorkspace("main")
        // Bail only if the workspace truly doesn't exist — without it we
        // can't even read the agent's name from IDENTITY.md.
        guard FileManager.default.fileExists(atPath: workspace) else {
            NSLog("[SubAgents] readMainAgentFromConfig: no workspace at %@", workspace)
            return nil
        }
        let model = entry["model"] as? String ?? ""
        let isDefault = entry["isDefault"] as? Bool ?? true
        let agentDir = entry["agentDir"] as? String ?? ""
        let identitySource = entry["identitySource"] as? String ?? ""

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

        // Read persona files from the workspace
        let fm = FileManager.default
        func read(_ relPath: String) -> String {
            let p = (workspace as NSString).appendingPathComponent(relPath)
            return (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
        }
        let identityContent = read("IDENTITY.md")
        let soulContent = read("SOUL.md")
        let memoryContent = read("MEMORY.md")
        let userContent = read("USER.md")
        let agentsContent = read("AGENTS.md")
        let bootstrapContent = read("BOOTSTRAP.md")
        let heartbeatContent = read("HEARTBEAT.md")
        let toolsContent = read("TOOLS.md")

        // Resolve display name + emoji: prefer parsed IDENTITY.md, else
        // fall back to identity dict, else config name
        let parsedIdentity = PersonaViewModel.parseIdentity(identityContent)
        let identity = entry["identity"] as? [String: Any]
        let name: String = {
            if !parsedIdentity.name.isEmpty { return parsedIdentity.name }
            if let n = identity?["name"] as? String, !n.isEmpty { return n }
            return entry["name"] as? String ?? "main"
        }()
        let emoji: String = {
            if !parsedIdentity.emoji.isEmpty { return parsedIdentity.emoji }
            return identity?["emoji"] as? String ?? "🤖"
        }()
        let creature = parsedIdentity.creature

        var info = SubAgentInfo(
            id: "main",
            name: name,
            emoji: emoji,
            creature: creature,
            model: model,
            isDefault: isDefault,
            bindingsCount: bindingDetails.count,
            bindingDetails: bindingDetails,
            identitySource: identitySource,
            workspace: fm.fileExists(atPath: workspace) ? workspace : "",
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
        return info
    }

    static func parseAgentList(output: String?) -> [SubAgentInfo] {
        guard let output = output else {
            NSLog("[SubAgents] parseAgentList: output is nil")
            return []
        }
        NSLog("[SubAgents] parseAgentList: output length=%d, first 200 chars: %@", output.count, String(output.prefix(200)))

        // Strip ANSI escape codes
        let ansiPattern = "\\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

        let lines = cleaned.components(separatedBy: .newlines)
        var jsonString = ""
        var inJson = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inJson {
                // Only start JSON on lines that look like actual JSON structure
                // "[" alone or "[{" is JSON array start, but "[agent-scope]" is not
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
        NSLog("[SubAgents] parseAgentList: jsonString length=%d, first 100: %@", jsonString.count, String(jsonString.prefix(100)))

        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            NSLog("[SubAgents] parseAgentList: FAILED - empty json or data conversion")
            return []
        }

        // Try parsing as array first, then as wrapper object
        let array: [[String: Any]]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            array = arr
        } else if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agents = wrapper["agents"] as? [[String: Any]] {
            array = agents
        } else {
            NSLog("[SubAgents] parseAgentList: FAILED - JSON parse failed")
            if let rawObj = try? JSONSerialization.jsonObject(with: data) {
                NSLog("[SubAgents] parseAgentList: parsed type = %@", String(describing: type(of: rawObj)))
            }
            return []
        }
        NSLog("[SubAgents] parseAgentList: parsed %d agents", array.count)

        return array.compactMap { dict -> SubAgentInfo? in
            guard let id = dict["id"] as? String else { return nil }

            let identityName = dict["identityName"] as? String ?? dict["name"] as? String ?? id
            let emoji = dict["identityEmoji"] as? String ?? "🤖"
            let model = dict["model"] as? String ?? ""
            let isDefault = dict["isDefault"] as? Bool ?? false
            let bindings = dict["bindings"] as? Int ?? 0
            let bindingDetails = dict["bindingDetails"] as? [String] ?? []
            let identitySource = dict["identitySource"] as? String ?? ""
            let workspace = dict["workspace"] as? String ?? ""
            let agentDir = dict["agentDir"] as? String ?? ""

            return SubAgentInfo(
                id: id,
                name: identityName,
                emoji: emoji,
                creature: "",
                model: model,
                isDefault: isDefault,
                bindingsCount: bindings,
                bindingDetails: bindingDetails,
                identitySource: identitySource,
                workspace: workspace,
                agentDir: agentDir
            )
        }
    }

    // MARK: - Load Models via CLI

    func loadModels() async {
        let output = await openclawService.runCommand(
            "openclaw models list --json 2>&1",
            timeout: 30
        )
        let models = Self.parseModelList(output: output)
        await MainActor.run { availableModels = models }
    }

    static func parseModelList(output: String?) -> [ModelOption] {
        guard let output = output else { return [] }

        // Strip ANSI escape codes
        let ansiPattern = "\\u{1B}\\[[0-9;]*[a-zA-Z]"
        let cleaned = output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)

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
            if inJson { jsonString += line + "\n" }
        }
        guard !jsonString.isEmpty, let data = jsonString.data(using: .utf8) else { return [] }

        if let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = wrapper["models"] as? [[String: Any]] {
            return models.compactMap { dict -> ModelOption? in
                guard let key = dict["key"] as? String else { return nil }
                let name = dict["name"] as? String ?? key
                let tags = dict["tags"] as? [String] ?? []
                return ModelOption(id: key, name: name, tags: tags)
            }
        }
        return []
    }

    // MARK: - Create Agent via CLI

    func createAgent(agentId: String, displayName: String, model: String, division: String = "Custom") async {
        guard !agentId.isEmpty else { return }

        await MainActor.run {
            isPerformingAction = true
            actionMessage = "Creating agent..."
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var cmd = "openclaw agents add '\(agentId)'"
        cmd += " --workspace '\(homeDir)/.openclaw/workspace-\(agentId)/'"
        cmd += " --agent-dir '\(homeDir)/.openclaw/agents/\(agentId)/agent/'"
        if !model.isEmpty {
            cmd += " --model '\(model)'"
        }
        cmd += " --non-interactive --json 2>&1"

        NSLog("[SubAgents] createAgent: running cmd: %@", cmd)
        let result = await openclawService.runCommand(cmd, timeout: 30)
        NSLog("[SubAgents] createAgent: result is %@, length=%d", result == nil ? "nil" : "non-nil", result?.count ?? 0)

        // Write identity into openclaw.json config (agents.list[].identity)
        let nameForIdentity = displayName.isEmpty ? agentId : displayName
        let emoji = Self.emojiForName(nameForIdentity)
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        Self.patchAgentIdentity(configPath: configPath, agentId: agentId, name: nameForIdentity, emoji: emoji)

        // Write persona files to workspace
        let workspace = "\(homeDir)/.openclaw/workspace-\(agentId)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: workspace, withIntermediateDirectories: true)

        // Always write IDENTITY.md with the correct name and emoji
        let identityTemplate = """
        # IDENTITY.md - Who Am I?

        - **Name:** \(nameForIdentity)
        - **Creature:**\u{20}
        - **Vibe:**\u{20}
        - **Emoji:** \(emoji)
        - **Division:** \(division)

        ---

        _Describe this agent's identity here._
        """
        writeFile(workspace, "IDENTITY.md", content: identityTemplate)

        if !fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("SOUL.md")) {
            let soulTemplate = """
            # SOUL.md - Who You Are

            _Define this agent's personality, behavior, and style._

            ## Core Truths

            - Be helpful and focused on your specialty.

            ## Vibe

            _Describe the tone and style._
            """
            writeFile(workspace, "SOUL.md", content: soulTemplate)
        }
        if !fm.fileExists(atPath: (workspace as NSString).appendingPathComponent("MEMORY.md")) {
            writeFile(workspace, "MEMORY.md", content: "# MEMORY.md\n\n_Long-term memory for this agent._\n")
        }

        await loadAgents()
        await MainActor.run {
            expandedAgent = agentId
            isPerformingAction = false
        }
    }

    /// Patch openclaw.json to add identity { name, emoji } to a specific agent in agents.list
    static func patchAgentIdentity(configPath: String, agentId: String, name: String, emoji: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var agents = root["agents"] as? [String: Any],
              var list = agents["list"] as? [[String: Any]] else {
            NSLog("[SubAgents] patchAgentIdentity: failed to read config")
            return
        }

        guard let idx = list.firstIndex(where: { $0["id"] as? String == agentId }) else {
            NSLog("[SubAgents] patchAgentIdentity: agent %@ not found in list", agentId)
            return
        }

        list[idx]["identity"] = ["name": name, "emoji": emoji]
        agents["list"] = list
        root["agents"] = agents

        guard let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            NSLog("[SubAgents] patchAgentIdentity: failed to serialize")
            return
        }

        // Write with backup
        let backupPath = configPath + ".bak"
        try? FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
        try? updatedData.write(to: URL(fileURLWithPath: configPath))
        NSLog("[SubAgents] patchAgentIdentity: wrote identity for %@ -> %@", agentId, name)
    }

    /// Match an emoji based on keywords in the agent name
    static func emojiForName(_ name: String) -> String {
        let lower = name.lowercased()
        let mapping: [(keywords: [String], emoji: String)] = [
            (["新闻", "news"],                    "📰"),
            (["代码", "code", "coder", "编程"],     "💻"),
            (["数据", "data"],                     "📊"),
            (["文档", "doc", "文章"],               "📚"),
            (["娱乐", "八卦", "gossip"],            "🗣️"),
            (["翻译", "translate"],                "🌐"),
            (["设计", "design", "美术"],            "🎨"),
            (["音乐", "music"],                    "🎵"),
            (["财经", "金融", "finance"],            "💰"),
            (["客服", "support", "客户"],           "💁"),
            (["视频", "video"],                    "🎬"),
            (["写作", "writer", "文案"],            "✍️"),
            (["搜索", "search"],                   "🔍"),
            (["学习", "教育", "study"],             "📖"),
            (["运维", "devops", "部署"],            "⚙️"),
            (["测试", "test", "qa"],               "🧪"),
            (["安全", "security"],                 "🔒"),
        ]
        for entry in mapping {
            for keyword in entry.keywords {
                if lower.contains(keyword) {
                    return entry.emoji
                }
            }
        }
        return "🤖"
    }

    // MARK: - Delete Agent via CLI

    func deleteAgent(agentId: String) async {
        await MainActor.run {
            isPerformingAction = true
            actionMessage = "Deleting agent..."
        }
        _ = await openclawService.runCommand(
            "openclaw agents delete '\(agentId)' --force --json 2>&1",
            timeout: 30
        )

        await MainActor.run {
            if expandedAgent == agentId { expandedAgent = nil }
        }
        await loadAgents()
        await MainActor.run { isPerformingAction = false }
    }

    // MARK: - Update Model

    func updateModel(agentId: String, model: String) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(homeDir)/.openclaw/openclaw.json"
        Self.patchAgentModel(configPath: configPath, agentId: agentId, model: model)

        // Update local state immediately
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].model = model
        }
    }

    static func patchAgentModel(configPath: String, agentId: String, model: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[SubAgents] patchAgentModel: failed to read config")
            return
        }

        // Initialize agents/list if either is missing — happens for fresh
        // installs where the user has only the implicit main workspace.
        var agents = root["agents"] as? [String: Any] ?? [:]
        var list = agents["list"] as? [[String: Any]] ?? []

        if let idx = list.firstIndex(where: { $0["id"] as? String == agentId }) {
            // Existing agent — patch in place
            if model.isEmpty {
                list[idx].removeValue(forKey: "model")
            } else {
                list[idx]["model"] = model
            }
        } else {
            // Agent not in agents.list yet. This is normal for the implicit
            // "main" agent (its identity lives in ~/.openclaw/workspace/
            // and openclaw.json never gets a `main` entry until someone
            // sets a per-agent override). Without this branch the model
            // change is a silent no-op — `loadAvailableAgents` re-reads
            // disk after the patch and reverts the in-memory state,
            // leaving the top header out of sync with the side panel.
            //
            // If the user is clearing the override (model == ""), we
            // don't bother adding a stub entry — inheriting is already
            // the default for agents not present in the list.
            guard !model.isEmpty else {
                NSLog("[SubAgents] patchAgentModel: agent %@ not in list and model is empty — nothing to do (already inheriting)", agentId)
                return
            }
            list.append(["id": agentId, "model": model])
            NSLog("[SubAgents] patchAgentModel: agent %@ added to list with model %@", agentId, model)
        }

        agents["list"] = list
        root["agents"] = agents

        guard let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            NSLog("[SubAgents] patchAgentModel: failed to serialize")
            return
        }

        let backupPath = configPath + ".bak"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
        try? updatedData.write(to: URL(fileURLWithPath: configPath))
        NSLog("[SubAgents] patchAgentModel: wrote model for %@ -> %@", agentId, model.isEmpty ? "(default)" : model)
    }

    // MARK: - File-based Persona Editing (unchanged)

    func toggleExpand(_ id: String) {
        withAnimation {
            expandedAgent = (expandedAgent == id) ? nil : id
        }
    }

    func binding(for agentId: String, file: PersonaViewModel.FileType) -> Binding<String> {
        Binding<String>(
            get: {
                guard let idx = self.agents.firstIndex(where: { $0.id == agentId }) else { return "" }
                switch file {
                case .identity: return self.agents[idx].identityContent
                case .soul: return self.agents[idx].soulContent
                case .memory: return self.agents[idx].memoryContent
                case .user: return ""
                }
            },
            set: { newValue in
                guard let idx = self.agents.firstIndex(where: { $0.id == agentId }) else { return }
                switch file {
                case .identity: self.agents[idx].identityContent = newValue
                case .soul: self.agents[idx].soulContent = newValue
                case .memory: self.agents[idx].memoryContent = newValue
                case .user: break
                }
            }
        )
    }

    func save(agentId: String, file: PersonaViewModel.FileType) {
        guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
        let workspace = agents[idx].workspace
        guard !workspace.isEmpty else { return }

        switch file {
        case .identity:
            writeFile(workspace, "IDENTITY.md", content: agents[idx].identityContent)
            agents[idx].identityOriginal = agents[idx].identityContent
        case .soul:
            writeFile(workspace, "SOUL.md", content: agents[idx].soulContent)
            agents[idx].soulOriginal = agents[idx].soulContent
        case .memory:
            writeFile(workspace, "MEMORY.md", content: agents[idx].memoryContent)
            agents[idx].memoryOriginal = agents[idx].memoryContent
        case .user:
            break
        }
    }

    func bindingByName(for agentId: String, fileName: String) -> Binding<String> {
        Binding<String>(
            get: {
                guard let idx = self.agents.firstIndex(where: { $0.id == agentId }) else { return "" }
                switch fileName {
                case "USER.md": return self.agents[idx].userContent
                case "AGENTS.md": return self.agents[idx].agentsContent
                case "BOOTSTRAP.md": return self.agents[idx].bootstrapContent
                case "HEARTBEAT.md": return self.agents[idx].heartbeatContent
                case "TOOLS.md": return self.agents[idx].toolsContent
                default: return ""
                }
            },
            set: { newValue in
                guard let idx = self.agents.firstIndex(where: { $0.id == agentId }) else { return }
                switch fileName {
                case "USER.md": self.agents[idx].userContent = newValue
                case "AGENTS.md": self.agents[idx].agentsContent = newValue
                case "BOOTSTRAP.md": self.agents[idx].bootstrapContent = newValue
                case "HEARTBEAT.md": self.agents[idx].heartbeatContent = newValue
                case "TOOLS.md": self.agents[idx].toolsContent = newValue
                default: break
                }
            }
        )
    }

    func saveByName(agentId: String, fileName: String) {
        guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
        let workspace = agents[idx].workspace
        guard !workspace.isEmpty else { return }

        switch fileName {
        case "USER.md":
            writeFile(workspace, fileName, content: agents[idx].userContent)
            agents[idx].userOriginal = agents[idx].userContent
        case "AGENTS.md":
            writeFile(workspace, fileName, content: agents[idx].agentsContent)
            agents[idx].agentsOriginal = agents[idx].agentsContent
        case "BOOTSTRAP.md":
            writeFile(workspace, fileName, content: agents[idx].bootstrapContent)
            agents[idx].bootstrapOriginal = agents[idx].bootstrapContent
        case "HEARTBEAT.md":
            writeFile(workspace, fileName, content: agents[idx].heartbeatContent)
            agents[idx].heartbeatOriginal = agents[idx].heartbeatContent
        case "TOOLS.md":
            writeFile(workspace, fileName, content: agents[idx].toolsContent)
            agents[idx].toolsOriginal = agents[idx].toolsContent
        default: break
        }
    }

    private func readFile(_ dirPath: String, _ name: String) -> String {
        let path = (dirPath as NSString).appendingPathComponent(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeFile(_ dirPath: String, _ name: String, content: String) {
        let path = (dirPath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
