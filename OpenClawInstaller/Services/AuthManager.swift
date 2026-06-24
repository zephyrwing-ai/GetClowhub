import Foundation
import Security
import AppKit
import Combine

// MARK: - AuthState

enum AuthState: Equatable {
    case checking
    case notLoggedIn
    case polling(deviceCode: String)
    case timeout
    case error(message: String)
    case loggedIn(nickname: String)
}

// MARK: - AuthConfig

enum AuthConfig {
    static let clientId = "getclawhub-macos"
    static let baseURL = "https://www.getclawhub.com"
    // static let baseURL = "http://localhost:5001"
    // static let baseURL = "http://ai-town.cn:5001/"
    static let deviceRegisterPath = "/api/auth/device-register"
    static let devicePollPath = "/api/auth/device-poll"
    static let refreshPath = "/api/auth/refresh"
    static let keychainService = "com.getclawhub.auth"
    static let profilePath = "/api/user/profile"
    static let keysBillingPath = "/api/user/keys-billing"
    static let pollingInterval: TimeInterval = 5
    static let pollingTimeout: TimeInterval = 600
    static let launchCheckTimeout: TimeInterval = 8
    static let maxLoginAttempts = 5
}

// MARK: - AuthManager

@MainActor
class AuthManager: ObservableObject {
    @Published var state: AuthState = .checking

    let loginSubject = PassthroughSubject<String, Never>()
    let logoutSubject = PassthroughSubject<Void, Never>()

    var accessToken: String? {
        readKeychain(key: "access_token")
    }

    var userId: String? {
        readKeychain(key: "user_id")
    }

    var userEmail: String? {
        readKeychain(key: "user_email")
    }

    var isLoggedIn: Bool {
        if case .loggedIn = state { return true }
        return false
    }

    private var pollingTimer: Timer?
    private var pollingStartTime: Date?
    private var loginAttempts = 0

    // MARK: - Launch Check

    func checkOnLaunch() {
        state = .checking

        guard let accessToken = readKeychain(key: "access_token"),
              !accessToken.isEmpty else {
            state = .notLoggedIn
            return
        }

        // Check if token is expired
        if let expiresAtStr = readKeychain(key: "token_expires_at"),
           let expiresAt = TimeInterval(expiresAtStr) {
            let now = Date().timeIntervalSince1970
            if now >= expiresAt {
                // Token expired, try refresh
                Task {
                    let refreshed = await withTimeout(seconds: AuthConfig.launchCheckTimeout) {
                        await self.refreshTokenIfNeeded()
                    } ?? false
                    if refreshed {
                        let nickname = readKeychain(key: "user_nickname") ?? "User"
                        state = .loggedIn(nickname: nickname)
                        if let token = self.accessToken {
                            loginSubject.send(token)
                        }
                    } else {
                        state = .notLoggedIn
                    }
                }
                return
            }
        }

        let nickname = readKeychain(key: "user_nickname") ?? "User"
        state = .loggedIn(nickname: nickname)
        loginSubject.send(accessToken)
    }

    // MARK: - Login

    func login() {
        Task {
            await performLogin()
        }
    }

    private func performLogin() async {
        // Check retry limit
        loginAttempts += 1
        if loginAttempts > AuthConfig.maxLoginAttempts {
            state = .error(message: String(localized: "Too many login attempts, please try again later"))
            return
        }

        let urlString = "\(AuthConfig.baseURL)\(AuthConfig.deviceRegisterPath)"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "client_id": AuthConfig.clientId,
            "app_version": Self.appVersion,
            "language": Self.appLanguage,
            "os_version": Self.osVersion,
            "device_model": Self.deviceModel,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[AuthManager] device-register HTTP \(statusCode): \(body)")
                state = .error(message: String(format: String(localized: "Login service error (HTTP %d), please try again later"), statusCode))
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceCode = json["device_code"] as? String,
                  let loginUrl = json["login_url"] as? String else {
                state = .error(message: String(localized: "Login service returned invalid data"))
                return
            }

            // Open browser for user to login
            if let url = URL(string: loginUrl) {
                NSWorkspace.shared.open(url)
            }

            state = .polling(deviceCode: deviceCode)
            startPolling(deviceCode: deviceCode)
        } catch {
            print("[AuthManager] device-register failed: \(error)")
            state = .error(message: String(format: String(localized: "Unable to connect to login service: %@"), error.localizedDescription))
        }
    }

    // MARK: - Logout

    func logout() {
        stopPolling()
        loginAttempts = 0
        deleteKeychain(key: "access_token")
        deleteKeychain(key: "refresh_token")
        deleteKeychain(key: "token_expires_at")
        deleteKeychain(key: "user_nickname")
        deleteKeychain(key: "user_email")
        deleteKeychain(key: "user_id")
        state = .notLoggedIn
        logoutSubject.send()
    }

    // MARK: - Retry

    func retry() {
        loginAttempts = 0
        login()
    }

    // MARK: - Polling

    private func startPolling(deviceCode: String) {
        stopPolling()
        pollingStartTime = Date()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: AuthConfig.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollDeviceStatus(deviceCode: deviceCode)
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        pollingStartTime = nil
    }

    private func pollDeviceStatus(deviceCode: String) async {
        // Check timeout
        if let startTime = pollingStartTime,
           Date().timeIntervalSince(startTime) >= AuthConfig.pollingTimeout {
            stopPolling()
            state = .timeout
            return
        }

        var components = URLComponents(string: "\(AuthConfig.baseURL)\(AuthConfig.devicePollPath)")
        components?.queryItems = [URLQueryItem(name: "device_code", value: deviceCode)]

        guard let url = components?.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                return
            }

            if status == "completed" {
                stopPolling()

                // Extract tokens
                if let accessToken = json["access_token"] as? String,
                   let refreshToken = json["refresh_token"] as? String,
                   let expiresIn = json["expires_in"] as? TimeInterval {

                    let expiresAt = Date().timeIntervalSince1970 + expiresIn
                    saveKeychain(key: "access_token", value: accessToken)
                    saveKeychain(key: "refresh_token", value: refreshToken)
                    saveKeychain(key: "token_expires_at", value: String(expiresAt))

                    // Extract user info
                    var nickname = "User"
                    if let user = json["user"] as? [String: Any],
                       let name = user["nickname"] as? String {
                        nickname = name
                        if let uid = user["user_id"] as? String {
                            saveKeychain(key: "user_id", value: uid)
                        }
                        if let email = user["email"] as? String, !email.isEmpty {
                            saveKeychain(key: "user_email", value: email)
                        }
                    }
                    saveKeychain(key: "user_nickname", value: nickname)

                    loginAttempts = 0
                    state = .loggedIn(nickname: nickname)
                    loginSubject.send(accessToken)
                }
            }
            // If status is "pending", keep polling (do nothing)
        } catch {
            // Network error during poll, keep trying
        }
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async -> Bool {
        guard let refreshToken = readKeychain(key: "refresh_token"),
              !refreshToken.isEmpty else {
            return false
        }

        let urlString = "\(AuthConfig.baseURL)\(AuthConfig.refreshPath)"
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AuthConfig.launchCheckTimeout

        let body: [String: String] = [
            "client_id": AuthConfig.clientId,
            "refresh_token": refreshToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String,
                  let newRefreshToken = json["refresh_token"] as? String,
                  let expiresIn = json["expires_in"] as? TimeInterval else {
                return false
            }

            let expiresAt = Date().timeIntervalSince1970 + expiresIn
            saveKeychain(key: "access_token", value: newAccessToken)
            saveKeychain(key: "refresh_token", value: newRefreshToken)
            saveKeychain(key: "token_expires_at", value: String(expiresAt))

            return true
        } catch {
            return false
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    // MARK: - Device Info

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var appLanguage: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.current.identifier
    }

    private static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    // MARK: - Keychain Operations

    private func saveKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AuthConfig.keychainService,
            kSecAttrAccount as String: key
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func readKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AuthConfig.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AuthConfig.keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
