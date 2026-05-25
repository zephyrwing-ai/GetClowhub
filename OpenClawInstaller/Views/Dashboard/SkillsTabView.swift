import SwiftUI
import AppKit

struct SkillsTabView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var searchText = ""
    @State private var filterStatus: SkillFilterStatus = .all
    @State private var showInstallSheet = false
    @State private var skillPendingRemoval: SkillInfo?

    enum SkillFilterStatus: String, CaseIterable {
        case all = "All"
        case ready = "Ready"
        case missing = "Missing"
    }

    private var filteredSkills: [SkillInfo] {
        var result = viewModel.skills

        // Filter by status
        switch filterStatus {
        case .all: break
        case .ready: result = result.filter { $0.status == .ready }
        case .missing: result = result.filter { $0.status == .missing }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query) ||
                $0.source.lowercased().contains(query)
            }
        }

        return result
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Skills")
                        .font(.headline)

                    if viewModel.skillsSummary.total > 0 {
                        Text("(\(viewModel.skillsSummary.ready)/\(viewModel.skillsSummary.total) ready)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Filter picker
                    Picker("", selection: $filterStatus) {
                        ForEach(SkillFilterStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    // Market button
                    Button(action: {
                        if let url = URL(string: "https://skills.sh/") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "storefront")
                            Text("Market")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    // Install button
                    Button(action: { showInstallSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    // Refresh button
                    Button(action: {
                        Task { await viewModel.loadSkills() }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoadingSkills)
                }

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                if viewModel.isLoadingSkills && viewModel.skills.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading skills...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else if filteredSkills.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(viewModel.skills.isEmpty ? "No skills found" : "No matching skills")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    // Skills list
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSkills.enumerated()), id: \.element.id) { index, skill in
                            SkillRow(
                                skill: skill,
                                isLoadingDetail: viewModel.isLoadingSkillDetail,
                                isRemoving: viewModel.removingSkillName == skill.name,
                                canRemove: DashboardViewModel.canRemoveSkill(skill),
                                onInfo: {
                                    Task { await viewModel.loadSkillDetail(skill.name) }
                                },
                                onRemove: {
                                    skillPendingRemoval = skill
                                }
                            )

                            if index < filteredSkills.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding(24)
        }
        .task {
            await viewModel.loadSkills()
        }
        .sheet(item: $viewModel.selectedSkillDetail) { detail in
            SkillDetailSheet(detail: detail, isPresented: Binding(
                get: { viewModel.selectedSkillDetail != nil },
                set: { if !$0 { viewModel.selectedSkillDetail = nil } }
            ))
        }
        .sheet(isPresented: $showInstallSheet) {
            SkillInstallSheet(
                viewModel: viewModel,
                isPresented: $showInstallSheet,
                searchText: $searchText,
                filterStatus: $filterStatus
            )
        }
        .alert(item: $skillPendingRemoval) { skill in
            Alert(
                title: Text("Remove Skill"),
                message: Text("Remove \"\(skill.name)\" from installed skills?"),
                primaryButton: .destructive(Text("Remove")) {
                    Task { await viewModel.removeSkill(skill) }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

// MARK: - Skill Install Sheet

struct SkillInstallSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool
    @Binding var searchText: String
    @Binding var filterStatus: SkillsTabView.SkillFilterStatus

    @State private var commandText = ""
    @State private var isInstalling = false
    @State private var installOutput = ""
    @State private var installFinished = false
    @State private var installSuccess = false
    @State private var validationError = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)

                Text("Install Skill")
                    .font(.headline)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Instructions
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste the install command from Skills Market:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Format: npx skills add <url> --skill <name>")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }

                // Command input
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundColor(.secondary)
                        TextField("npx skills add https://github.com/... --skill skill-name", text: $commandText)
                            .textFieldStyle(.plain)
                            .fontDesign(.monospaced)
                            .disabled(isInstalling)
                            .onSubmit { installSkill() }
                    }
                    .padding(10)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(validationError.isEmpty ? Color.clear : Color.red, lineWidth: 1)
                    )

                    if !validationError.isEmpty {
                        Text(validationError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Install button
                HStack {
                    Spacer()
                    Button(action: { installSkill() }) {
                        HStack(spacing: 6) {
                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                                Text("Installing...")
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Install")
                            }
                        }
                        .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(commandText.trimmingCharacters(in: .whitespaces).isEmpty || isInstalling)
                }

                // Output area
                if !installOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Output")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if installFinished {
                                Label(
                                    installSuccess ? "Done" : "Failed",
                                    systemImage: installSuccess ? "checkmark.circle.fill" : "xmark.circle.fill"
                                )
                                .font(.caption)
                                .foregroundColor(installSuccess ? .green : .red)
                            }
                        }

                        ScrollView {
                            Text(installOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 380)
    }

    /// Validate and extract skill name from command
    private func validateCommand(_ cmd: String) -> (valid: Bool, skillName: String?) {
        let trimmed = cmd.trimmingCharacters(in: .whitespaces)

        // Must start with "npx skills add" (or "npx clawhub add")
        guard trimmed.hasPrefix("npx skills add ") || trimmed.hasPrefix("npx clawhub add ") else {
            return (false, nil)
        }

        // Extract --skill name
        var skillName: String?
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if let idx = parts.firstIndex(of: "--skill"), idx + 1 < parts.count {
            skillName = parts[idx + 1]
        }

        return (true, skillName)
    }

    private func installSkill() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        let (valid, skillName) = validateCommand(cmd)
        guard valid else {
            validationError = "Invalid format. Command must start with \"npx skills add\""
            return
        }
        validationError = ""

        isInstalling = true
        installOutput = ""
        installFinished = false
        installSuccess = false

        // Auto-append -y (skip prompts) and -g (global install) if not already present
        var finalCmd = cmd
        if !finalCmd.contains("-y") && !finalCmd.contains("--yes") {
            finalCmd += " -y"
        }
        if !finalCmd.contains("-g") && !finalCmd.contains("--global") {
            finalCmd += " -g"
        }

        Task {
            let output = await viewModel.openclawService.runCommand(
                "\(finalCmd) 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'",
                timeout: 120
            )
            installOutput = output ?? "No output"
            let hasError = output?.lowercased().contains("error") == true
                && output?.lowercased().contains("error") != output?.lowercased().contains("0 error")
            installSuccess = !hasError
            installFinished = true
            isInstalling = false

            // Refresh skills list and auto-search for installed skill
            if installSuccess {
                await viewModel.loadSkills()
                if let name = skillName, !name.isEmpty {
                    filterStatus = .all
                    searchText = name
                }
            }
        }
    }
}

// MARK: - Skill Row

struct SkillRow: View {
    let skill: SkillInfo
    let isLoadingDetail: Bool
    let isRemoving: Bool
    let canRemove: Bool
    let onInfo: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(skill.status == .ready ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            // Skill info
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(skill.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Source badge
            Text(sourceLabel)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sourceColor.opacity(0.15))
                .foregroundColor(sourceColor)
                .cornerRadius(4)

            // Status badge
            if skill.status == .ready {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("Missing", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Remove button
            Button(action: onRemove) {
                if isRemoving {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(canRemove ? .red : .secondary)
            .disabled(!canRemove || isRemoving)
            .help(canRemove ? "Remove skill" : "Bundled skills cannot be removed")

            // Info button
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(isLoadingDetail)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sourceLabel: String {
        switch skill.source {
        case "openclaw-bundled": return "Bundled"
        case "openclaw-extra": return "Extra"
        case "openclaw-workspace": return "Workspace"
        default: return skill.source
        }
    }

    private var sourceColor: Color {
        switch skill.source {
        case "openclaw-bundled": return .blue
        case "openclaw-extra": return .purple
        case "openclaw-workspace": return .orange
        default: return .secondary
        }
    }
}

// MARK: - Skill Detail Sheet

struct SkillDetailSheet: View {
    let detail: SkillDetailInfo
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(detail.isReady ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                Text(detail.name)
                    .font(.headline)

                Text(detail.status)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(detail.isReady ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(detail.isReady ? .green : .orange)
                    .cornerRadius(4)

                Spacer()

                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    if !detail.description.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(detail.description)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    // Details
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        if !detail.source.isEmpty {
                            DetailRow(label: "Source", value: detail.source)
                        }
                        if !detail.path.isEmpty {
                            DetailRow(label: "Path", value: detail.path)
                        }
                    }

                    // Requirements
                    if !detail.requirements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Requirements")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            ForEach(detail.requirements, id: \.self) { req in
                                HStack(spacing: 6) {
                                    Image(systemName: req.contains("\u{2713}") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(req.contains("\u{2713}") ? .green : .orange)
                                        .font(.caption)

                                    Text(req)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .frame(width: 500, height: 400)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

#Preview {
    SkillsTabView(
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
    .frame(width: 700, height: 600)
}
