import Foundation

struct ChatSessionMetadata: Identifiable, Equatable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var isPinned: Bool
    var isArchived: Bool
}

extension ChatSessionMetadata: ChatSessionSearchable {}

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let now = Date()
let mainSession = ChatSessionMetadata(
    id: UUID(),
    agentId: "main",
    title: "Project Research",
    createdAt: now.addingTimeInterval(-400),
    updatedAt: now.addingTimeInterval(-100),
    messageCount: 3,
    isPinned: false,
    isArchived: false
)
let ux = ChatSessionMetadata(
    id: UUID(),
    agentId: "ux",
    title: "Project Search Overlay",
    createdAt: now.addingTimeInterval(-300),
    updatedAt: now.addingTimeInterval(-50),
    messageCount: 5,
    isPinned: false,
    isArchived: false
)
let archived = ChatSessionMetadata(
    id: UUID(),
    agentId: "writer",
    title: "Project Archive",
    createdAt: now.addingTimeInterval(-200),
    updatedAt: now,
    messageCount: 2,
    isPinned: false,
    isArchived: true
)

@main
struct GlobalSessionSearchVerification {
    static func main() {
        let results = ChatSessionSearch.search([mainSession, ux, archived], query: "project")

        guard results.map(\.id) == [ux.id, mainSession.id] else {
            fail("global search should return matching unarchived sessions from all agents, newest first")
        }

        let recent = ChatSessionSearch.search([mainSession, ux, archived], query: "")
        guard recent.map(\.id) == [ux.id, mainSession.id] else {
            fail("empty global search should show recent unarchived sessions from all agents")
        }

        print("Global session search verification passed")
    }
}
