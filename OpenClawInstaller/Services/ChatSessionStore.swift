import Combine
import Foundation
import os.log

/// Local-only chat session persistence.
///
/// Layout:
///   ~/.openclaw/workspace/.sessions/
///   ~/.openclaw/workspace-<agentId>/.sessions/
///
/// Legacy layout, still read for backward compatibility:
///   ~/Library/Application Support/<bundleID>/chat-sessions/
///     ├── index.json                    # all metadata, loaded eagerly
///     └── <sessionId>.json              # full ChatSession including messages, loaded on demand
///
/// Why split: the index is small and read once on launch; per-session files
/// can grow large with months of history, so we don't want to deserialize
/// every thread just to render the sidebar list.
@MainActor
final class ChatSessionStore: ObservableObject {
    private let log = Logger(subsystem: "com.openclaw.installer", category: "ChatSessionStore")

    private let legacyBaseDir: URL
    private let legacyIndexURL: URL
    private let openclawBaseDir: URL

    /// Cached metadata for every persisted session, sorted only on read.
    @Published private(set) var index: [ChatSessionMetadata] = []

    /// In-flight debounced save tasks, keyed by session id, so rapid writes
    /// to the same session collapse into one disk write.
    private var saveDebouncers: [UUID: Task<Void, Never>] = [:]

    /// Recently-loaded full session cache. Keyed by id; entries are
    /// invalidated on `saveSession` / `deleteSession` so the cache never
    /// goes stale. Avoids re-parsing a (potentially large) chat history
    /// every time the user flips back to a session — repeated switches
    /// between two sessions used to hit disk on every flip.
    ///
    /// LRU with a small cap (the working set in practice is the agent's
    /// few most-recent sessions, not the whole history).
    private var sessionCache: [UUID: ChatSession] = [:]
    private var cacheOrder: [UUID] = []  // most-recently used at end
    private let cacheCapacity = 12

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.cc.OpenClawInstaller"
        self.legacyBaseDir = appSupport
            .appendingPathComponent(bundleId)
            .appendingPathComponent("chat-sessions")
        self.legacyIndexURL = legacyBaseDir.appendingPathComponent("index.json")
        self.openclawBaseDir = URL(fileURLWithPath: NSString("~/.openclaw").expandingTildeInPath, isDirectory: true)

        try? FileManager.default.createDirectory(
            at: legacyBaseDir,
            withIntermediateDirectories: true
        )
        loadIndex()
    }

    // MARK: - Index I/O

    func loadIndex() {
        var combined: [UUID: ChatSessionMetadata] = [:]

        for meta in readIndex(from: legacyIndexURL) {
            combined[meta.id] = meta
        }

        let agentsFromLegacy = Set(combined.values.map(\.agentId))
        for agentId in agentsFromLegacy.union(discoverAgentIdsFromWorkspaces()) {
            for meta in readIndex(from: indexURL(forAgent: agentId)) {
                combined[meta.id] = meta
            }
        }

        index = Array(combined.values)
    }

    private func writeIndex(forAgent agentId: String) {
        let url = indexURL(forAgent: agentId)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let agentIndex = index.filter { $0.agentId == agentId }
            let data = try Self.encoder().encode(agentIndex)
            try data.write(to: url, options: .atomic)
        } catch {
            log.error("Failed to write index for \(agentId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readIndex(from url: URL) -> [ChatSessionMetadata] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try Self.decoder().decode([ChatSessionMetadata].self, from: data)
        } catch {
            log.error("Failed to decode index at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func writeLegacyIndex() {
        do {
            let data = try Self.encoder().encode(index)
            try data.write(to: legacyIndexURL, options: .atomic)
        } catch {
            log.error("Failed to write legacy index: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Session I/O

    /// Read a session's full content (including all messages) from disk.
    /// Returns nil if the file is missing or corrupt. Cached so repeated
    /// reads (e.g. flipping back and forth between sessions) don't re-hit
    /// disk and re-parse JSON.
    func loadSession(id: UUID) -> ChatSession? {
        if let cached = sessionCache[id] {
            touchCache(id: id)
            return cached
        }
        guard let url = sessionURL(for: id) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let session = try Self.decoder().decode(ChatSession.self, from: data)
            insertCache(id: id, session: session)
            return session
        } catch {
            log.error("Failed to decode session \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cached lookup without touching disk. Returns nil on a cache miss
    /// — callers can use this to do a fast in-memory unstash and fall
    /// back to async disk-load when it's not there.
    func cachedSession(id: UUID) -> ChatSession? {
        return sessionCache[id]
    }

    /// Off-main-thread variant: decode the JSON on a background queue so
    /// the main thread isn't blocked on a multi-hundred-KB session file.
    /// Result populates the same LRU cache used by `loadSession`, so the
    /// next sync call returns instantly.
    func loadSessionAsync(id: UUID) async -> ChatSession? {
        if let cached = sessionCache[id] {
            touchCache(id: id)
            return cached
        }
        guard let url = sessionURL(for: id) else { return nil }
        // Detached so we yield the main actor for the decode.
        let session = await Task.detached(priority: .userInitiated) { () -> ChatSession? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            do {
                let d = JSONDecoder()
                d.dateDecodingStrategy = .iso8601
                return try d.decode(ChatSession.self, from: data)
            } catch {
                return nil
            }
        }.value
        if let session = session {
            insertCache(id: id, session: session)
        }
        return session
    }

    /// Persist a session immediately. Updates `index` in place so the UI
    /// reflects the new metadata (title, message count, …) right away.
    func saveSession(_ session: ChatSession) {
        let url = sessionURL(for: session)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.encoder().encode(session)
            try data.write(to: url, options: .atomic)
            // Keep the cache coherent with disk: whatever we just wrote is
            // exactly what a subsequent loadSession should return.
            insertCache(id: session.id, session: session)

            let meta = ChatSessionMetadata(from: session)
            if let idx = index.firstIndex(where: { $0.id == session.id }) {
                index[idx] = meta
            } else {
                index.append(meta)
            }
            writeIndex(forAgent: session.agentId)
        } catch {
            log.error("Failed to save session \(session.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Cache

    /// Move `id` to the most-recently-used end of the eviction order.
    private func touchCache(id: UUID) {
        if let idx = cacheOrder.firstIndex(of: id) {
            cacheOrder.remove(at: idx)
        }
        cacheOrder.append(id)
    }

    /// Insert (or overwrite) a session in the cache, evicting the oldest
    /// entry if over capacity.
    private func insertCache(id: UUID, session: ChatSession) {
        sessionCache[id] = session
        touchCache(id: id)
        while cacheOrder.count > cacheCapacity {
            let oldest = cacheOrder.removeFirst()
            sessionCache.removeValue(forKey: oldest)
        }
    }

    private func invalidateCache(id: UUID) {
        sessionCache.removeValue(forKey: id)
        cacheOrder.removeAll { $0 == id }
    }

    /// Defers the actual disk write by `delay` so a burst of streamed deltas
    /// (e.g. token-by-token assistant output) collapses into a single write.
    func saveSessionDebounced(_ session: ChatSession, delay: TimeInterval = 0.5) {
        saveDebouncers[session.id]?.cancel()
        saveDebouncers[session.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.saveSession(session)
        }
    }

    /// Force any pending debounced writes for a session to land synchronously.
    /// Useful before app shutdown or when switching active session.
    func flush(id: UUID, current: ChatSession?) {
        saveDebouncers[id]?.cancel()
        saveDebouncers[id] = nil
        if let s = current { saveSession(s) }
    }

    func deleteSession(id: UUID) {
        saveDebouncers[id]?.cancel()
        saveDebouncers[id] = nil
        invalidateCache(id: id)
        if let url = sessionURL(for: id) {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: legacySessionURL(for: id))
        let affectedAgentIds = Set(index.filter { $0.id == id }.map(\.agentId))
        index.removeAll { $0.id == id }
        for agentId in affectedAgentIds {
            writeIndex(forAgent: agentId)
        }
        writeLegacyIndex()
    }

    // MARK: - Queries

    /// Sessions for one agent, pinned first then newest first. Hides archived
    /// sessions unless `includeArchived` is true.
    func sessions(forAgent agentId: String, includeArchived: Bool = false) -> [ChatSessionMetadata] {
        ChatSessionSearch.search(
            index.filter { $0.agentId == agentId },
            query: "",
            includeArchived: includeArchived
        )
    }

    /// Global session search across every agent workspace. Empty queries
    /// return recent sessions, which powers the search palette's default state.
    func searchSessions(query: String, includeArchived: Bool = false) -> [ChatSessionMetadata] {
        ChatSessionSearch.search(index, query: query, includeArchived: includeArchived)
    }

    // MARK: - Helpers

    private func sessionURL(for id: UUID) -> URL? {
        if let meta = index.first(where: { $0.id == id }) {
            let scoped = sessionURL(forAgent: meta.agentId, id: id)
            if FileManager.default.fileExists(atPath: scoped.path) {
                return scoped
            }
        }

        let legacy = legacySessionURL(for: id)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }

        if let meta = index.first(where: { $0.id == id }) {
            return sessionURL(forAgent: meta.agentId, id: id)
        }
        return nil
    }

    private func sessionURL(for session: ChatSession) -> URL {
        sessionURL(forAgent: session.agentId, id: session.id)
    }

    private func sessionURL(forAgent agentId: String, id: UUID) -> URL {
        sessionsDirectory(forAgent: agentId)
            .appendingPathComponent("\(id.uuidString).json")
    }

    private func legacySessionURL(for id: UUID) -> URL {
        legacyBaseDir.appendingPathComponent("\(id.uuidString).json")
    }

    private func indexURL(forAgent agentId: String) -> URL {
        sessionsDirectory(forAgent: agentId)
            .appendingPathComponent("index.json")
    }

    private func sessionsDirectory(forAgent agentId: String) -> URL {
        workspaceDirectory(forAgent: agentId)
            .appendingPathComponent(".sessions", isDirectory: true)
    }

    private func workspaceDirectory(forAgent agentId: String) -> URL {
        if agentId == "main" {
            return openclawBaseDir.appendingPathComponent("workspace", isDirectory: true)
        }
        return openclawBaseDir.appendingPathComponent("workspace-\(agentId)", isDirectory: true)
    }

    private func discoverAgentIdsFromWorkspaces() -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: openclawBaseDir.path) else {
            return []
        }
        var ids: Set<String> = []
        if names.contains("workspace") {
            ids.insert("main")
        }
        for name in names where name.hasPrefix("workspace-") {
            let id = String(name.dropFirst("workspace-".count))
            if !id.isEmpty {
                ids.insert(id)
            }
        }
        return ids
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
