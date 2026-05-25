#if REQUIRE_LOGIN
import Foundation
import Combine
import os.log

// MARK: - Membership Level

enum MembershipLevel: String, Codable {
    case free = "free"
    case pro = "pro"
    case max = "max"

    var displayName: String {
        switch self {
        case .free: return "FREE"
        case .pro: return "PRO"
        case .max: return "MAX"
        }
    }

    /// 本地预设模型列表（当后端未返回时的 fallback）
    var defaultModels: [String] {
        switch self {
        case .free:
            return [
                "deepseek-v4-pro", "qwen3.6-flash",
                "doubao-seed-2.0-lite", "minimax-m2.7",
            ]
        case .pro:
            return [
                "deepseek-v4-pro", "deepseek-v4-flash",
                "qwen3.6-plus", "minimax-m2.7-highspeed",
                "glm-5.1", "glm-5v-turbo",
                "kimi-k2.6", "kimi-k2.5",
                "doubao-seed-2.0-pro", "doubao-seed-code",
                "ernie-x1.1-preview",
                "gemini-2.5-flash-lite", "gemini-3.1-pro-preview",
                "grok-4.1-fast",
                "claude-opus-4.6", "claude-sonnet-4.6", "claude-haiku-4.5",
            ]
        case .max:
            return [
                "deepseek-v4-pro", "deepseek-v4-flash",
                "qwen3.6-plus", "minimax-m2.7-highspeed",
                "glm-5.1", "glm-5v-turbo",
                "kimi-k2.6", "kimi-k2.5",
                "doubao-seed-2.0-pro", "doubao-seed-code",
                "ernie-x1.1-preview",
                "gemini-2.5-flash-lite", "gemini-3.1-pro-preview",
                "grok-4.1-fast",
                "claude-opus-4.7", "claude-opus-4.6", "claude-sonnet-4.6", "claude-haiku-4.5",
                "gpt-5.5",
            ]
        }
    }
}

// MARK: - Membership Info

struct MembershipInfo {
    let level: MembershipLevel
    let expiresAt: Date?
    let models: [String]
    let maxBudget: Double
    let rpmLimit: Int
    let maxKeys: Int
}

// MARK: - API Key Info

struct ApiKeyInfo: Identifiable, Equatable {
    let keyId: String
    let keyName: String
    let fullKey: String
    let models: [String]
    let label: String?
    let status: Int // 1 = active

    var id: String { keyId }
    var isActive: Bool { status == 1 }
}

// MARK: - Key Billing Info

struct KeyBillingInfo: Identifiable {
    let keyId: String         // key_id (e.g. "tk_15")
    let key: String           // 脱敏 key
    let keyName: String       // label or masked key
    let keyAlias: String?     // LiteLLM key_alias
    let spend: Double         // 已消费金额
    let maxBudget: Double?    // 预算上限
    let budgetDuration: String? // "30d"
    let createdAt: Date?      // 创建时间
    let updatedAt: Date?      // 最后更新时间
    let expires: Date?        // 过期时间
    let rpmLimit: Int?
    let models: [String]
    let status: Int           // 1 = active
    var id: String { keyId }

    /// 优先展示 alias，其次 keyName，最后 key
    var displayName: String {
        if let alias = keyAlias, !alias.isEmpty { return alias }
        if !keyName.isEmpty { return keyName }
        return key
    }
}

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case synced
    case error(String)
}

// MARK: - MembershipManager

@MainActor
class MembershipManager: ObservableObject {
    @Published var membership: MembershipInfo?
    @Published var apiKeys: [ApiKeyInfo] = []
    @Published var syncState: SyncState = .idle
    @Published var keysBilling: [KeyBillingInfo] = []
    @Published var isBillingLoading: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private weak var authManager: AuthManager?
    private var presetManager = ProviderPresetManager()

    init() {}

    /// Call this after both AuthManager and MembershipManager are initialized.
    func setup(authManager: AuthManager) {
        self.authManager = authManager

        authManager.loginSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.syncProfile()
                }
            }
            .store(in: &cancellables)

        authManager.logoutSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.membership = nil
                self?.apiKeys = []
                self?.keysBilling = []
                self?.syncState = .idle
            }
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    var hasValidKey: Bool {
        apiKeys.contains { $0.isActive }
    }

    // MARK: - Sync Profile

    func syncProfile() async {
        guard let auth = authManager else {
            syncState = .error("No auth manager")
            return
        }
        guard let token = auth.accessToken else {
            syncState = .error("No access token")
            return
        }

        syncState = .syncing

        let result = await fetchProfile(token: token)

        switch result {
        case .success:
            break  // already handled inside fetchProfile
        case .unauthorized:
            // Token expired or invalid — try refresh then retry once
            let refreshed = await auth.refreshTokenIfNeeded()
            if refreshed, let newToken = auth.accessToken {
                let retryResult = await fetchProfile(token: newToken)
                if case .unauthorized = retryResult {
                    // Refresh token also invalid (e.g. server restarted) — force re-login
                    syncState = .error("Session expired, please log in again")
                    auth.logout()
                } else if case .otherError(let msg) = retryResult {
                    syncState = .error(msg)
                }
            } else {
                // Refresh failed — force re-login
                syncState = .error("Session expired, please log in again")
                auth.logout()
            }
        case .otherError(let msg):
            syncState = .error(msg)
        }
    }

    private enum SyncResult {
        case success
        case unauthorized
        case otherError(String)
    }

    private func fetchProfile(token: String) async -> SyncResult {
        let urlString = "\(AuthConfig.baseURL)\(AuthConfig.profilePath)"
        guard let url = URL(string: urlString) else {
            return .otherError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                syncState = .error("No HTTP response")
                return .otherError("No HTTP response")
            }

            if httpResponse.statusCode == 401 {
                return .unauthorized
            }

            guard httpResponse.statusCode == 200 else {
                syncState = .error("HTTP \(httpResponse.statusCode)")
                return .otherError("HTTP \(httpResponse.statusCode)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                syncState = .error("Invalid response")
                return .otherError("Invalid response")
            }

            // Parse membership info
            if let membershipDict = json["membership"] as? [String: Any] {
                let levelStr = membershipDict["level"] as? String ?? "free"
                let level = MembershipLevel(rawValue: levelStr) ?? .free

                var expiresAt: Date? = nil
                if let expiresAtStr = membershipDict["expires_at"] as? String {
                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    expiresAt = isoFormatter.date(from: expiresAtStr)
                    if expiresAt == nil {
                        isoFormatter.formatOptions = [.withInternetDateTime]
                        expiresAt = isoFormatter.date(from: expiresAtStr)
                    }
                    if expiresAt == nil {
                        // MySQL datetime format: "2026-05-02 10:30:44"
                        let mysqlFormatter = DateFormatter()
                        mysqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        mysqlFormatter.timeZone = TimeZone(identifier: "UTC")
                        expiresAt = mysqlFormatter.date(from: expiresAtStr)
                    }
                }

                let models = membershipDict["models"] as? [String] ?? []
                // Fallback: use level's default models if backend didn't return any
                let finalModels = models.isEmpty ? level.defaultModels : models
                let maxBudget = membershipDict["max_budget"] as? Double ?? 0
                let rpmLimit = membershipDict["rpm_limit"] as? Int ?? 0
                let maxKeys = membershipDict["max_keys"] as? Int ?? 0

                membership = MembershipInfo(
                    level: level,
                    expiresAt: expiresAt,
                    models: finalModels,
                    maxBudget: maxBudget,
                    rpmLimit: rpmLimit,
                    maxKeys: maxKeys
                )
            }

            // Parse API keys
            if let keysArray = json["api_keys"] as? [[String: Any]] {
                apiKeys = keysArray.compactMap { dict in
                    guard let keyId = dict["key_id"] as? String,
                          let keyName = dict["key_name"] as? String,
                          let fullKey = dict["key"] as? String else {
                        return nil
                    }
                    let models = dict["models"] as? [String] ?? []
                    let label = dict["label"] as? String
                    let status = dict["status"] as? Int ?? 0

                    return ApiKeyInfo(
                        keyId: keyId,
                        keyName: keyName,
                        fullKey: fullKey,
                        models: models,
                        label: label,
                        status: status
                    )
                }
            }

            syncState = .synced

            // Auto-apply first active key
            autoApplyFirstKey()

            return .success

        } catch {
            syncState = .error(error.localizedDescription)
            return .otherError(error.localizedDescription)
        }
    }

    // MARK: - Key Billing

    func fetchKeysBilling() async {
        guard let auth = authManager, let token = auth.accessToken else { return }

        isBillingLoading = true
        defer { isBillingLoading = false }

        let urlString = "\(AuthConfig.baseURL)\(AuthConfig.keysBillingPath)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 401 {
                // Try refresh and retry once
                let refreshed = await auth.refreshTokenIfNeeded()
                if refreshed, let newToken = auth.accessToken {
                    var retryRequest = request
                    retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                    guard let retryHttp = retryResponse as? HTTPURLResponse, retryHttp.statusCode == 200 else { return }
                    keysBilling = Self.parseBillingArray(retryData)
                }
                return
            }

            guard httpResponse.statusCode == 200 else { return }
            keysBilling = Self.parseBillingArray(data)
        } catch {
            print("[MembershipManager] fetchKeysBilling failed: \(error)")
        }
    }

    private static func parseBillingArray(_ data: Data) -> [KeyBillingInfo] {
        // API returns { "user_budget": {...}, "keys": [...] }
        let array: [[String: Any]]
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let keys = root["keys"] as? [[String: Any]] {
            array = keys
        } else if let directArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            array = directArray
        } else {
            return []
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let mysqlFormatter = DateFormatter()
        mysqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        mysqlFormatter.timeZone = TimeZone(identifier: "UTC")

        func parseDate(_ value: Any?) -> Date? {
            guard let str = value as? String else { return nil }
            return dateFormatter.date(from: str)
                ?? fallbackFormatter.date(from: str)
                ?? mysqlFormatter.date(from: str)
        }

        return array.compactMap { dict -> KeyBillingInfo? in
            guard let key = dict["key"] as? String else { return nil }
            let keyId = dict["key_id"] as? String ?? key
            let keyName = dict["key_name"] as? String ?? key
            let keyAlias = dict["key_alias"] as? String

            let spend = dict["spend"] as? Double ?? 0
            let maxBudget = dict["max_budget"] as? Double
            let budgetDuration = dict["budget_duration"] as? String
            let rpmLimit = dict["rpm_limit"] as? Int
            let models = dict["models"] as? [String] ?? []
            let status = dict["status"] as? Int ?? 0

            let createdAt = parseDate(dict["created_at"])
            let updatedAt = parseDate(dict["updated_at"])
            let expires = parseDate(dict["expires"])

            return KeyBillingInfo(
                keyId: keyId,
                key: key,
                keyName: keyName,
                keyAlias: keyAlias,
                spend: spend,
                maxBudget: maxBudget,
                budgetDuration: budgetDuration,
                createdAt: createdAt,
                updatedAt: updatedAt,
                expires: expires,
                rpmLimit: rpmLimit,
                models: models,
                status: status
            )
        }
    }

    // MARK: - Apply Key to Config

    func applyKeyToConfig(_ key: ApiKeyInfo, activate: Bool = false) {
        // Match preset models against the key's allow-list case-insensitively. The
        // backend has historically shipped `MiniMax-*` in mixed case while the
        // preset (and LiteLLM model registry) use lowercase; an exact-case Set
        // contains() silently dropped those models from the UI.
        let allowedLowercased = Set(key.models.map { $0.lowercased() })

        // IMPORTANT: If API key has no allowed models, don't overwrite existing config
        // This prevents clearing the model list when API returns empty models array
        guard !allowedLowercased.isEmpty else {
            os_log("[MembershipManager] API key %@ has no allowed models, skipping config update to preserve existing configuration", log: OSLog.default, type: .info, key.keyId)
            return
        }

        let allPresetModels = presetManager.findProvider(byKey: "getclawhub")?.models ?? []
        let models = allPresetModels.filter { allowedLowercased.contains($0.id.lowercased()) }
        let baseUrl = presetManager.findProvider(byKey: "getclawhub")?.baseUrl ?? "https://ai.getclawhub.com/v1"
        AppSettingsManager.writeGetClawHubProvider(apiKey: key.fullKey, models: models, baseUrl: baseUrl, activate: activate)
    }

    /// Automatically apply the most recently created active key to config.
    func autoApplyFirstKey() {
        let shouldActivate = AppSettingsManager.shouldAutoApplyGetClawHubProvider()
        guard let latestActive = apiKeys.last(where: { $0.isActive }) else { return }
        if !shouldActivate {
            os_log("[MembershipManager] Custom provider is active, syncing GetClawHub key without switching models", log: OSLog.default, type: .info)
        }
        applyKeyToConfig(latestActive, activate: shouldActivate)
    }
}
#endif
