import Foundation

struct GatewayWorkspaceContext: Codable, Equatable, Hashable {
    let projectId: String
    let projectRoot: String
    let projectDisplayName: String
    let agentWorkspace: String
    let cwd: String

    init(projectContext: ProjectWorkspaceContext) {
        self.projectId = projectContext.projectId
        self.projectRoot = projectContext.projectRoot
        self.projectDisplayName = projectContext.projectDisplayName
        self.agentWorkspace = projectContext.agentWorkspace
        self.cwd = projectContext.cwd
    }
}
