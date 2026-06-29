import Foundation

struct ProjectSessionContextBuilder {
    static func message(for project: ProjectRecord?) -> String {
        guard let project else { return "" }
        return """

        [Project Context]
        Current project: \(project.displayName)
        Project root: \(project.rootPath)
        Use local project tools or local file paths to inspect source. Do not assume stale paths are correct.
        """
    }
}
