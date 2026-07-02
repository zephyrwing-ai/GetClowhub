import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")

let filteredSkills = slice(
    dashboard,
    from: "private var filteredSkills: [SkillInfo]",
    to: "    private var skillCatalogItemsByName"
)
let showSkillsPanel = slice(
    dashboard,
    from: "private var showSkillsPanel: Bool",
    to: "    /// Filtered agents"
)
let skillsPanel = slice(
    dashboard,
    from: "private var skillsPanel: some View",
    to: "    private var agentMentionPanel"
)
let selectSkill = slice(
    dashboard,
    from: "private func selectSkill(_ skill: SkillInfo)",
    to: "    private func selectAgent"
)

require(
    filteredSkills.contains("readyComposerSkills"),
    "composer /skills filtering must start from ready-only skills"
)
require(
    dashboard.contains("private var readyComposerSkills: [SkillInfo]") && dashboard.contains(".status == .ready"),
    "composer /skills candidates must exclude missing or needs-setup skills"
)
require(
    showSkillsPanel.contains("!readyComposerSkills.isEmpty"),
    "composer /skills panel visibility must depend on ready skills, not the full Skills page list"
)
require(
    selectSkill.contains("guard skill.status == .ready else { return }"),
    "selectSkill must defensively ignore non-ready skills"
)
require(
    !skillsPanel.contains("Color.orange"),
    "composer /skills panel should not render missing-state orange dots because missing skills are not candidates"
)

print("Composer /skills ready-only verification passed")
