import Foundation
import os.log

private let tokenStoreLog = Logger(subsystem: "com.openclaw.installer", category: "DeviceAuthTokenStore")

/// Per-role device auth token returned by the gateway in the `helloOk.auth`
/// response after a successful pair. Reusing this token on subsequent
/// connects skips the full re-signing flow and proves "yes, this is the
/// device the gateway already approved" — which also lets the gateway
/// match the connection to the existing `approvedScopes` record.
struct StoredDeviceAuthToken: Codable {
    let token: String
    let scopes: [String]
    let updatedAtMs: Int64
}

/// `~/.openclaw/identity/device-auth.json`, schema-compatible with openclaw's
/// own `device-auth` store (one entry per role, keyed by role string).
///
/// Schema (matches Node side):
/// ```json
/// {
///   "version": 1,
///   "deviceId": "<sha256-of-public-key-hex>",
///   "tokens": {
///     "operator": { "token": "...", "scopes": [...], "updatedAtMs": 12345 }
///   }
/// }
/// ```
///
/// We persist `deviceId` redundantly so a stale token file left over from a
/// re-keyed identity is easy to spot during recovery (don't load if it
/// doesn't match the current `DeviceIdentity.deviceId`).
final class DeviceAuthTokenStore {

    /// Wire-format root we store on disk. Internal — callers only ever see
    /// `StoredDeviceAuthToken` per role.
    private struct Root: Codable {
        let version: Int
        let deviceId: String
        var tokens: [String: StoredDeviceAuthToken]
    }

    private let url: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.url = home
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent("device-auth.json")
    }

    /// Returns the stored token for `role` IF it belongs to the device with
    /// `currentDeviceId`. If the file is missing, corrupt, or written for a
    /// different deviceId (e.g. the identity was regenerated), returns nil
    /// and lets the caller fall through to the bootstrap-token + pairing path.
    func load(role: String, currentDeviceId: String) -> StoredDeviceAuthToken? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            return nil
        }
        guard root.deviceId == currentDeviceId else {
            tokenStoreLog.warning("load: token file's deviceId mismatch — discarding stale store")
            return nil
        }
        return root.tokens[role]
    }

    /// Upsert a token for `role`. Creates the file (and parent dir) on first
    /// write with the same 0700/0600 permission discipline as the identity
    /// file.
    func save(role: String, deviceId: String, token: StoredDeviceAuthToken) {
        var root: Root
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode(Root.self, from: data),
           existing.deviceId == deviceId {
            root = existing
            root.tokens[role] = token
        } else {
            root = Root(version: 1, deviceId: deviceId, tokens: [role: token])
        }
        writeAtomic(root)
    }

    /// Drop the token for `role`. Used when the gateway tells us the token
    /// is revoked/mismatched — the next connect should fall back to pairing
    /// rather than retry-loop with a dead token.
    func remove(role: String, deviceId: String) {
        guard let data = try? Data(contentsOf: url),
              var root = try? JSONDecoder().decode(Root.self, from: data),
              root.deviceId == deviceId else {
            return
        }
        root.tokens.removeValue(forKey: role)
        writeAtomic(root)
    }

    // MARK: - I/O

    private func writeAtomic(_ root: Root) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard var data = try? enc.encode(root) else {
            tokenStoreLog.error("writeAtomic: encode failed")
            return
        }
        data.append(0x0a)
        do {
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            tokenStoreLog.error("writeAtomic: write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
