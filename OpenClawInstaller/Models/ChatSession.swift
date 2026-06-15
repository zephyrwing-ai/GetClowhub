import Foundation

/// One conversation thread for a given agent. Persisted as a single JSON file
/// under that agent workspace's `.sessions` directory.
struct ChatSession: Codable, Identifiable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var isPinned: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        agentId: String,
        title: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = [],
        isPinned: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.agentId = agentId
        self.title = title ?? Self.defaultTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.isPinned = isPinned
        self.isArchived = isArchived
    }

    static let defaultTitle = "新会话"

    /// Build a title from the first user message in the thread, capped at `maxLength`.
    /// Falls back to `defaultTitle` when no usable user content exists.
    static func deriveTitle(from messages: [ChatMessage], maxLength: Int = 30) -> String {
        guard let firstUserText = messages.first(where: { $0.role == .user })?.content,
              !firstUserText.isEmpty else {
            return defaultTitle
        }
        let trimmed = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultTitle }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}

/// Lightweight metadata stored in `index.json` so we don't have to read every
/// session file at launch. The full `ChatSession` is loaded lazily when the
/// user actually opens that thread.
struct ChatSessionMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    let agentId: String
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var isPinned: Bool
    var isArchived: Bool

    init(from session: ChatSession) {
        self.id = session.id
        self.agentId = session.agentId
        self.title = session.title
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.messageCount = session.messages.count
        self.isPinned = session.isPinned
        self.isArchived = session.isArchived
    }
}

extension ChatSessionMetadata: ChatSessionSearchable {}
