import Foundation

protocol ChatSessionSearchable {
    var title: String { get }
    var updatedAt: Date { get }
    var isPinned: Bool { get }
    var isArchived: Bool { get }
}

enum ChatSessionSearch {
    static func search<Session: ChatSessionSearchable>(
        _ sessions: [Session],
        query: String,
        includeArchived: Bool = false
    ) -> [Session] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions
            .filter { includeArchived || !$0.isArchived }
            .filter { meta in
                trimmed.isEmpty || meta.title.localizedCaseInsensitiveContains(trimmed)
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
}
