import Foundation

final class ProjectWorkspaceService {
    private let registryStore: ProjectRegistryStore
    private let repoMapService: SemanticRepoMapService

    init(
        registryStore: ProjectRegistryStore = ProjectRegistryStore(),
        repoMapService: SemanticRepoMapService = SemanticRepoMapService()
    ) {
        self.registryStore = registryStore
        self.repoMapService = repoMapService
    }

    func loadRegistry() -> ProjectRegistryStore.Snapshot? {
        registryStore.load()
    }

    func saveRegistry(projects: [ProjectRecord], bindingsByAgent: [String: [AgentProjectBinding]]) throws {
        try registryStore.save(projects: projects, bindings: bindingsByAgent.values.flatMap { $0 })
    }

    func attachProject(
        url: URL,
        toAgent agentId: String,
        projectsById: [String: ProjectRecord],
        bindingsByAgent: [String: [AgentProjectBinding]]
    ) -> ProjectWorkspaceAttachment {
        let standardized = url.standardizedFileURL
        let rootPath = standardized.path
        let displayName = standardized.lastPathComponent.isEmpty ? rootPath : standardized.lastPathComponent
        let existing = projectsById.values.first { $0.rootPath == rootPath }
        var project = existing ?? ProjectRecord(displayName: displayName, rootPath: rootPath)
        project.displayName = displayName
        project.rootPath = rootPath
        project.lastOpenedAt = Date()
        project.indexStatus = .ready

        var updatedProjects = projectsById
        updatedProjects[project.id] = project

        var updatedBindings = bindingsByAgent
        var bindings = updatedBindings[agentId] ?? []
        if let idx = bindings.firstIndex(where: { $0.projectId == project.id }) {
            bindings[idx].lastOpenedAt = Date()
        } else {
            bindings.append(AgentProjectBinding(agentId: agentId, projectId: project.id, sortOrder: bindings.count))
        }
        updatedBindings[agentId] = bindings

        return ProjectWorkspaceAttachment(
            project: project,
            projectsById: updatedProjects,
            bindingsByAgent: updatedBindings
        )
    }

    func toggleCollapse(
        agentId: String,
        projectId: String,
        bindingsByAgent: [String: [AgentProjectBinding]]
    ) -> [String: [AgentProjectBinding]] {
        var updated = bindingsByAgent
        guard var bindings = updated[agentId],
              let idx = bindings.firstIndex(where: { $0.projectId == projectId }) else {
            return updated
        }
        bindings[idx].isCollapsed.toggle()
        updated[agentId] = bindings
        return updated
    }

    func removeProject(
        _ projectId: String,
        fromAgent agentId: String,
        bindingsByAgent: [String: [AgentProjectBinding]]
    ) -> [String: [AgentProjectBinding]] {
        var updated = bindingsByAgent
        updated[agentId]?.removeAll { $0.projectId == projectId }
        return updated
    }

    func bootstrapProject(_ project: ProjectRecord) async {
        await repoMapService.bootstrapProject(project)
    }
}

struct ProjectWorkspaceAttachment {
    let project: ProjectRecord
    let projectsById: [String: ProjectRecord]
    let bindingsByAgent: [String: [AgentProjectBinding]]
}
