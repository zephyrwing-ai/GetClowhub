import Foundation
import CryptoKit
import os.log

private let identityLog = Logger(subsystem: "com.openclaw.installer", category: "DeviceIdentity")

/// Ed25519 device identity, format-compatible with openclaw's
/// `~/.openclaw/identity/device.json`.
///
/// **Why this exists**: openclaw 2026.5.x tightened the gateway scope check
/// for `chat.send` / `chat.abort` so a connection without a paired device's
/// `approvedScopes` covering those methods is rejected with
/// `missing scope: operator.write`. Pre-existing pairing records — auto-created
/// by older clients that didn't send `device` — were stamped with the OLD
/// scope set (`admin/approvals/pairing`) which doesn't include write; merely
/// adding `operator.write` to the client's requested scopes doesn't help
/// because the gateway filters requests against the stored `approvedScopes`.
///
/// The escape hatch is to actually pair the device: send a signed `device`
/// field in `connect`, let the gateway record a fresh pairing keyed by our
/// public-key fingerprint with the FULL requested scope set, and then reuse
/// the returned `deviceToken` on subsequent connects.
///
/// **Format compatibility**: we store PEM (SPKI public, PKCS#8 private) so
/// the JSON file is byte-compatible with the file the openclaw gateway
/// produces itself — admins can `cat ~/.openclaw/identity/device.json` and
/// run `openclaw devices list` on it indifferently. Same dir, same schema.
struct DeviceIdentity: Codable {
    let version: Int
    let deviceId: String          // sha256(rawPublicKey) hex
    let publicKeyPem: String      // SPKI PEM
    let privateKeyPem: String     // PKCS#8 PEM
    let createdAtMs: Int64

    init(version: Int = 1, deviceId: String, publicKeyPem: String, privateKeyPem: String, createdAtMs: Int64) {
        self.version = version
        self.deviceId = deviceId
        self.publicKeyPem = publicKeyPem
        self.privateKeyPem = privateKeyPem
        self.createdAtMs = createdAtMs
    }
}

enum DeviceIdentityStore {

    /// `~/.openclaw/identity/device.json` — same path openclaw's Node side uses.
    /// `resolveStateDir()` on the Node side falls back to `~/.openclaw`, and
    /// we always run a per-user agent so `homeDirectoryForCurrentUser` is correct.
    static func identityPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent("device.json")
    }

    /// Load an existing identity, or generate + persist a fresh one on first
    /// access. Defensive: if the on-disk file is unparseable or fails the
    /// keypair self-check, we regenerate rather than crash — the previous
    /// identity wasn't usable anyway, and a new one will silent-auto-pair
    /// on loopback so the user doesn't notice.
    static func loadOrCreate() -> DeviceIdentity {
        let url = identityPath()
        if let existing = tryLoad(at: url), keypairSelfCheck(existing) {
            return existing
        }
        let fresh = generate()
        write(fresh, to: url)
        identityLog.info("Generated new device identity: \(fresh.deviceId.prefix(12), privacy: .public)…")
        return fresh
    }

    /// Sign `payload` (UTF-8) with the identity's private key, return the
    /// Base64URL-encoded signature (matching `signDevicePayload` in
    /// `device-identity-BnE1pk2N.js:174`).
    static func sign(_ payload: String, with identity: DeviceIdentity) -> String? {
        guard let key = privateSigningKey(from: identity.privateKeyPem),
              let data = payload.data(using: .utf8) else {
            identityLog.error("sign: failed to load private key or encode payload")
            return nil
        }
        do {
            let sig = try key.signature(for: data)
            return base64UrlEncode(sig)
        } catch {
            identityLog.error("sign: ed25519 sign threw: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Base64URL-encoded raw public key (32 bytes), matching
    /// `publicKeyRawBase64UrlFromPem` in `device-identity-BnE1pk2N.js:199`.
    static func publicKeyRawBase64Url(_ identity: DeviceIdentity) -> String? {
        guard let raw = rawPublicKeyBytes(fromPem: identity.publicKeyPem) else { return nil }
        return base64UrlEncode(raw)
    }

    // MARK: - File I/O

    private static func tryLoad(at url: URL) -> DeviceIdentity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DeviceIdentity.self, from: data)
    }

    private static func write(_ id: DeviceIdentity, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        // 0700 directory + 0600 file — matches openclaw's `privateFileStoreSync`
        // semantics so we don't expose the private key in a world-readable spot.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? enc.encode(id) else { return }
        // Atomic write + trailing newline (openclaw's writer does it too)
        var withTrailing = data
        withTrailing.append(0x0a)
        try? withTrailing.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Crypto

    private static func generate() -> DeviceIdentity {
        let priv = Curve25519.Signing.PrivateKey()
        let pubRaw = priv.publicKey.rawRepresentation
        let privRaw = priv.rawRepresentation
        let publicPem = pemEncode("PUBLIC KEY", der: ed25519SpkiPrefix + pubRaw)
        let privatePem = pemEncode("PRIVATE KEY", der: ed25519Pkcs8PrivatePrefix + privRaw)
        let deviceId = SHA256.hash(data: pubRaw).hex
        return DeviceIdentity(
            deviceId: deviceId,
            publicKeyPem: publicPem,
            privateKeyPem: privatePem,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Sign a small probe + verify with the corresponding public key. Catches
    /// corruption (file edited by hand, partial write, etc.) before we try
    /// to use the key with the gateway and get a confusing 1008 close.
    private static func keypairSelfCheck(_ id: DeviceIdentity) -> Bool {
        guard let priv = privateSigningKey(from: id.privateKeyPem),
              let pubRaw = rawPublicKeyBytes(fromPem: id.publicKeyPem) else {
            return false
        }
        let probe = Data("openclaw-device-identity-self-check".utf8)
        guard let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw),
              let sig = try? priv.signature(for: probe) else {
            return false
        }
        guard pub.isValidSignature(sig, for: probe) else { return false }
        // Also check deviceId == sha256(pubRaw) hex — protects against someone
        // hand-editing the JSON file to point deviceId at one key but stash a
        // different public/private pair.
        return SHA256.hash(data: pubRaw).hex == id.deviceId
    }

    private static func privateSigningKey(from pem: String) -> Curve25519.Signing.PrivateKey? {
        guard let der = pemDecode(pem, expectedLabel: "PRIVATE KEY"),
              der.count == ed25519Pkcs8PrivatePrefix.count + 32,
              der.prefix(ed25519Pkcs8PrivatePrefix.count) == ed25519Pkcs8PrivatePrefix else {
            return nil
        }
        let raw = der.suffix(32)
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    }

    private static func rawPublicKeyBytes(fromPem pem: String) -> Data? {
        guard let der = pemDecode(pem, expectedLabel: "PUBLIC KEY") else { return nil }
        if der.count == ed25519SpkiPrefix.count + 32,
           der.prefix(ed25519SpkiPrefix.count) == ed25519SpkiPrefix {
            return Data(der.suffix(32))
        }
        // Fallback: if some other tool ever writes a raw 32-byte public key
        // without the SPKI wrapper, accept it. The openclaw Node implementation
        // also has a graceful path for this (`derivePublicKeyRaw` in
        // device-identity-BnE1pk2N.js:30).
        return der.count == 32 ? der : nil
    }

    // MARK: - PEM helpers

    /// Ed25519 SPKI header (RFC 8410). Same bytes openclaw's Node side hard-codes.
    private static let ed25519SpkiPrefix = Data([
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65,
        0x70, 0x03, 0x21, 0x00
    ])
    /// Ed25519 PKCS#8 v1 private-key header.
    private static let ed25519Pkcs8PrivatePrefix = Data([
        0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
        0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20
    ])

    private static func pemEncode(_ label: String, der: Data) -> String {
        let b64 = der.base64EncodedString()
        var lines: [String] = []
        var idx = b64.startIndex
        while idx < b64.endIndex {
            let end = b64.index(idx, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append(String(b64[idx..<end]))
            idx = end
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----\n"
    }

    private static func pemDecode(_ pem: String, expectedLabel: String) -> Data? {
        let begin = "-----BEGIN \(expectedLabel)-----"
        let end = "-----END \(expectedLabel)-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end),
              beginRange.upperBound < endRange.lowerBound else {
            return nil
        }
        let body = pem[beginRange.upperBound..<endRange.lowerBound]
        let b64 = body.split(separator: "\n").map(String.init).joined()
        return Data(base64Encoded: b64)
    }

    // MARK: - Base64URL

    private static func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64UrlEncode<S: Sequence>(_ seq: S) -> String where S.Element == UInt8 {
        return base64UrlEncode(Data(seq))
    }
}

private extension SHA256.Digest {
    /// Lowercase hex string (sha256 → 64 chars). Matches Node's `digest('hex')`.
    var hex: String {
        return self.map { String(format: "%02x", $0) }.joined()
    }
}
