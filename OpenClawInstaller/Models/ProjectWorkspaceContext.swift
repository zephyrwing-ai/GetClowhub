import Foundation

struct ProjectWorkspaceContext: Codable, Equatable, Hashable {
    let projectId: String
    let projectRoot: String
    let projectDisplayName: String
    let agentWorkspace: String
    let cwd: String

    init(
        projectId: String,
        projectRoot: String,
        projectDisplayName: String,
        agentWorkspace: String,
        cwd: String? = nil
    ) {
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.projectDisplayName = projectDisplayName
        self.agentWorkspace = agentWorkspace
        self.cwd = cwd ?? projectRoot
    }
}
