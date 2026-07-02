import Foundation
import Combine
import os.log

private let gwLog = Logger(subsystem: "com.openclaw.installer", category: "GatewayClient")

/// Events emitted by the gateway for chat sessions.
enum GatewayChatEvent {
    case delta(runId: String, sessionKey: String, text: String)
    case final_(runId: String, sessionKey: String, text: String)
    case aborted(runId: String, sessionKey: String)
    case error(runId: String, sessionKey: String, message: String)
    case activity(runId: String, sessionKey: String?, event: GatewayActivityEvent)
}

struct GatewayActivityEvent: Equatable {
    enum Kind: String, Equatable {
        case loadedTools
        case searchedCode
        case readFiles
        case ranCommands
        case editedFiles
        case createdFiles
        case selectedModel
        case agentUsed
        case agentRecruited
        case toolFailed
    }

    let kind: Kind
    let detail: String?
    let dedupeKey: String
}

/// Last gateway-side rejection seen on the connect handshake. Carries the raw
/// error envelope so the UI can show *why* the WS won't connect (e.g.
/// `NOT_PAIRED` / `DEVICE_IDENTITY_REQUIRED` vs `token_mismatch`) instead of
/// the generic "Gateway is not connected".
struct GatewayConnectError: Equatable {
    let code: String          // e.g. "NOT_PAIRED", "INVALID_REQUEST"
    let detailCode: String?   // e.g. "DEVICE_IDENTITY_REQUIRED", "token_mismatch"
    let message: String
}

/// Lightweight WebSocket client for the OpenClaw gateway.
/// Uses native `URLSessionWebSocketTask` (macOS 13+), no third-party dependencies.
class GatewayClient: ObservableObject {
    @Published var isConnected = false
    @Published var lastConnectError: GatewayConnectError?

    private var port: Int
    private var authToken: String
    /// Called before each connection attempt to get fresh port and token from config file
    private var credentialsProvider: (() -> (port: Int, authToken: String))?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let delegateHandler = WebSocketDelegate()
    private var reconnectAttempt = 0
    private let maxReconnectDelay: TimeInterval = 15
    private var isIntentionalDisconnect = false
    private var pendingResponses: [String: CheckedContinuation<Bool, Never>] = [:]
    private var pendingChatSendResponses: [String: CheckedContinuation<String?, Never>] = [:]
    private var pendingChatSendStartedAt: [String: ContinuousClock.Instant] = [:]
    private var pendingChatHistoryResponses: [String: CheckedContinuation<String?, Never>] = [:]
    private let responseLock = NSLock()
    private var eventContinuations: [String: AsyncStream<GatewayChatEvent>.Continuation] = [:]
    private let eventLock = NSLock()

    /// Serializes all mutations of `webSocketTask` / `urlSession` / `reconnectAttempt` /
    /// `isIntentionalDisconnect` / `reconnectPending`.
    ///
    /// Without this, failure callbacks from `URLSessionWebSocketTask.receive`, send-callback
    /// errors, and the auth-failure handler can fire concurrently on different queues and
    /// each call `scheduleReconnect()`, racing to teardown/rebuild the URLSession. That race
    /// produces a double-release on the previous CF-backed URLSession and crashes the app
    /// with `malloc_zone_error` → `abort()` inside `_CFRelease`. See crash report
    /// 2026-05-12 (v1.1.46) Thread 9: `GatewayClient.establishConnection() + 330`.
    private let stateQueue = DispatchQueue(label: "com.openclaw.gateway.state")

    /// True between the moment a reconnect is scheduled and the moment a new connection
    /// has been established. Prevents concurrent failure callbacks from each kicking off
    /// their own reconnect timer.
    private var reconnectPending = false

    /// Timestamp of the last WebSocket message received (any chat event, response, etc.).
    /// Used by the ViewModel as a coarse "WebSocket is alive" signal — note the gateway
    /// itself does NOT emit periodic tick/heartbeat broadcasts today (the older comment
    /// claiming it did was aspirational), so for a real liveness probe we run a separate
    /// client heartbeat below.
    private(set) var lastMessageReceivedAt = Date()

    /// Repeating `DispatchSourceTimer` that fires `sendPing` while the WS is up.
    /// Created on `stateQueue` after a successful connect ack, cancelled in
    /// `teardownSession()`. nil while disconnected.
    ///
    /// Why: macOS TCP keepalive defaults to ~2 hours of idle before the kernel sends
    /// its first probe, which means a silently half-open WS (Wi-Fi router flake / VPN
    /// reconnect / cell handoff) goes undetected for hours until the user next tries
    /// to `chat.send`. A 30s WS-protocol ping closes that gap — the server stack
    /// (per RFC 6455) auto-responds with a pong, so no gateway change is required.
    private var heartbeatTimer: DispatchSourceTimer?

    /// Set when a ping is in flight (we asked URLSession to send one, the pong hasn't
    /// arrived yet). nil otherwise. Read/written only on `stateQueue`.
    private var outstandingPingSentAt: Date?

    private let pingInterval: TimeInterval = 30
    private let pingTimeout: TimeInterval = 30  // pong must arrive within this window

    // MARK: - Device pairing state

    /// Ed25519 keypair lazily loaded from (or generated into)
    /// `~/.openclaw/identity/device.json`. Carries the deviceId we present
    /// to the gateway and the private key we sign connect challenges with.
    /// See `DeviceIdentity.swift` for full rationale.
    private let deviceIdentity = DeviceIdentityStore.loadOrCreate()

    /// Stores the per-role `deviceToken` returned by `helloOk.auth.deviceToken`
    /// after a successful pair. Reused on reconnect to skip the full pairing
    /// flow and to land back on the SAME server-side device record (so its
    /// existing `approvedScopes` are reused, not reset).
    private let tokenStore = DeviceAuthTokenStore()

    /// Most recent connect-challenge nonce, captured by `handleMessage` when
    /// the gateway sends `event: "connect.challenge"`. Used as the `nonce`
    /// component of the v3 sign payload. nil until the challenge arrives —
    /// `sendConnectRequest()` falls back to no-device mode if nil so we
    /// keep working against older gateways that don't issue challenges.
    private var pendingChallengeNonce: String?

    /// Role we connect under. Hard-coded here because we always behave as the
    /// macOS operator UI; sub-agent / talk roles aren't in scope for this
    /// client. Pulling it into a property mostly so the v3 payload + token
    /// lookup don't drift apart from one literal.
    private let connectRole = "operator"

    init(port: Int, authToken: String, credentialsProvider: (() -> (port: Int, authToken: String))? = nil) {
        self.port = port
        self.authToken = authToken
        self.credentialsProvider = credentialsProvider
    }

    private static func elapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
        let duration = start.duration(to: ContinuousClock.now)
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.1f", milliseconds)
    }

    // MARK: - Public API

    func connect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionalDisconnect = false
            self.reconnectAttempt = 0
            self.reconnectPending = false
            self.establishConnection()
        }
    }

    func disconnect() {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            self.isIntentionalDisconnect = true
            self.teardownSession()
            DispatchQueue.main.async {
                self.isConnected = false
                self.lastConnectError = nil
            }
        }
    }

    /// Send `chat.abort` to the gateway. Returns `true` if the abort was acknowledged.
    func abortChat(sessionKey: String, runId: String? = nil) async -> Bool {
        guard let ws = webSocketTask else { return false }

        let requestId = UUID().uuidString
        var params: [String: Any] = [
            "sessionKey": sessionKey
        ]
        if let runId = runId {
            params["runId"] = runId
        }
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.abort",
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }

        // Register a continuation to wait for the response
        let result: Bool = await withCheckedContinuation { continuation in
            responseLock.lock()
            pendingResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: false)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: false)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return result
    }

    /// Apply a session-only model override through `sessions.patch`.
    /// This updates gateway session state without changing agent defaults in openclaw.json.
    func patchSessionModel(sessionKey: String, model: String) async -> Bool {
        guard let ws = webSocketTask else { return false }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return false }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "sessions.patch",
            "params": [
                "key": sessionKey,
                "model": trimmedModel
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }

        let result: Bool = await withCheckedContinuation { continuation in
            responseLock.lock()
            pendingResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: false)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: false)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return result
    }

    /// Send a chat message via `chat.send`. Returns the runId on success, nil on failure.
    func chatSend(sessionKey: String, message: String, attachments: [[String: Any]]? = nil) async -> String? {
        guard let ws = webSocketTask else { return nil }

        let requestId = UUID().uuidString
        let idempotencyKey = UUID().uuidString
        let chatSendStartedAt = ContinuousClock.now

        var params: [String: Any] = [
            "sessionKey": sessionKey,
            "idempotencyKey": idempotencyKey,
            "message": message
        ]
        if let attachments = attachments, !attachments.isEmpty {
            params["attachments"] = attachments
        }

        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": params
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            gwLog.error("chatSend: failed to serialize payload to JSON")
            if let attachments = attachments {
                for (i, att) in attachments.enumerated() {
                    let contentLen = (att["content"] as? String)?.count ?? 0
                    gwLog.error("  attachment[\(i)] content length: \(contentLen)")
                }
            }
            return nil
        }

        gwLog.info("chatSend: JSON size = \(jsonString.count) bytes, attachments = \(attachments?.count ?? 0)")

        // Use a separate continuation map for chat.send responses to extract runId
        let runId: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            responseLock.lock()
            pendingChatSendResponses[requestId] = continuation
            pendingChatSendStartedAt[requestId] = chatSendStartedAt
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if let error = error {
                    gwLog.error("chatSend: WebSocket send error: \(error.localizedDescription)")
                    self?.responseLock.lock()
                    if let cont = self?.pendingChatSendResponses.removeValue(forKey: requestId) {
                        self?.pendingChatSendStartedAt.removeValue(forKey: requestId)
                        self?.responseLock.unlock()
                        cont.resume(returning: nil)
                    } else {
                        self?.responseLock.unlock()
                    }
                } else {
                    gwLog.info("phase=chat_send_ws_send request=\(requestId, privacy: .public) bytes=\(jsonString.count, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: chatSendStartedAt), privacy: .public)")
                }
            }

            // Timeout after 10 seconds for the send acknowledgement
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingChatSendResponses.removeValue(forKey: requestId) {
                    let startedAt = self?.pendingChatSendStartedAt.removeValue(forKey: requestId)
                    self?.responseLock.unlock()
                    if let startedAt {
                        gwLog.warning("phase=chat_send_ack_timeout request=\(requestId, privacy: .public) elapsed_ms=\(Self.elapsedMillisecondsText(since: startedAt), privacy: .public)")
                    } else {
                        gwLog.warning("phase=chat_send_ack_timeout request=\(requestId, privacy: .public) elapsed_ms=unknown")
                    }
                    cont.resume(returning: nil)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return runId
    }

    /// Subscribe to chat events. Returns an AsyncStream that yields `GatewayChatEvent` values.
    /// The caller should filter events by runId as needed.
    func subscribeToEvents(subscriberId: String) -> AsyncStream<GatewayChatEvent> {
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.eventLock.lock()
                self?.eventContinuations.removeValue(forKey: subscriberId)
                self?.eventLock.unlock()
            }
            eventLock.lock()
            eventContinuations[subscriberId] = continuation
            eventLock.unlock()
        }
    }

    /// Remove a subscriber and terminate its event stream.
    func unsubscribe(subscriberId: String) {
        eventLock.lock()
        let continuation = eventContinuations.removeValue(forKey: subscriberId)
        eventLock.unlock()
        continuation?.finish()
    }

    /// Fetch the last assistant message from chat history for a given session.
    /// Used as a fallback when the final event has no message content.
    func fetchLastAssistantMessage(sessionKey: String) async -> String? {
        guard let ws = webSocketTask else { return nil }

        let requestId = UUID().uuidString
        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": 5
            ] as [String: Any]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Reuse pendingChatSendResponses to get the full response payload
        let result: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            responseLock.lock()
            pendingChatHistoryResponses[requestId] = continuation
            responseLock.unlock()

            ws.send(.string(jsonString)) { [weak self] error in
                if error != nil {
                    self?.responseLock.lock()
                    if let cont = self?.pendingChatHistoryResponses.removeValue(forKey: requestId) {
                        self?.responseLock.unlock()
                        cont.resume(returning: nil)
                    } else {
                        self?.responseLock.unlock()
                    }
                }
            }

            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.responseLock.lock()
                if let cont = self?.pendingChatHistoryResponses.removeValue(forKey: requestId) {
                    self?.responseLock.unlock()
                    cont.resume(returning: nil)
                } else {
                    self?.responseLock.unlock()
                }
            }
        }

        return result
    }

    // MARK: - Connection Management

    /// Tear down the current session/task. **Caller must be on `stateQueue`.**
    private func teardownSession() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        stopHeartbeat()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    /// Build a fresh URLSession + WebSocket task. **Caller must be on `stateQueue`.**
    ///
    /// Defensively tears down any stale session first so the property write below cannot
    /// stomp on a still-live URLSession owned by another in-flight reconnect.
    private func establishConnection() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard !isIntentionalDisconnect else { return }

        // Defensive: any prior session must be torn down before we overwrite the property,
        // otherwise the old strong reference is dropped without `invalidateAndCancel`.
        teardownSession()

        // Refresh credentials from config file before each connection attempt
        if let provider = credentialsProvider {
            let creds = provider()
            self.port = creds.port
            self.authToken = creds.authToken
        }

        let urlString = "ws://127.0.0.1:\(port)/"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("http://127.0.0.1:\(port)", forHTTPHeaderField: "Origin")

        // Explicit bounds on the WS handshake — `timeoutIntervalForRequest` applies to
        // the initial HTTP upgrade; the WS stream itself is open-ended (long-running
        // tasks can stream for hours and that's fine). macOS defaults to 60s here,
        // which is unhelpfully generous given our 30s client heartbeat already proves
        // post-handshake liveness — drop to 30s so a stuck handshake surfaces fast
        // enough to schedule a reconnect rather than blocking for a minute.
        //
        // `timeoutIntervalForResource` defaults to ~7 days (DT_RESOURCE_TIMEOUT) which
        // matches what we want — a streaming WS is a long-lived resource by design.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30

        let session = URLSession(configuration: config, delegate: delegateHandler, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        listenForMessages()
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self.listenForMessages()

            case .failure:
                DispatchQueue.main.async { self.isConnected = false }
                // Only reconnect if socket wasn't already cleaned up by auth failure handler
                guard self.webSocketTask != nil else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Track that the WebSocket is alive (any inbound message counts: chat events,
        // response acks, etc. — gateway does not emit periodic ticks today; client-side
        // ping/pong is what actively probes the link).
        lastMessageReceivedAt = Date()

        let type = json["type"] as? String

        if type == "event", let event = json["event"] as? String, event == "connect.challenge" {
            // Capture nonce for the v3 device signature. Older gateways may
            // omit the payload — we fall through with nonce=nil and
            // sendConnectRequest will skip the device field (i.e. behave like
            // pre-pairing clients did, working against legacy gateways).
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String,
               !nonce.trimmingCharacters(in: .whitespaces).isEmpty {
                self.pendingChallengeNonce = nonce
            } else {
                self.pendingChallengeNonce = nil
            }
            sendConnectRequest()
            return
        }

        // Handle chat events
        if type == "event", let event = json["event"] as? String, event == "chat" {
            if let payload = json["payload"] as? [String: Any] {
                handleChatEventPayload(payload)
            }
            return
        }

        if type == "event", let event = json["event"] as? String, event == "agent" {
            if let payload = json["payload"] as? [String: Any] {
                handleAgentEventPayload(payload)
            }
            return
        }

        if type == "res" {
            if let id = json["id"] as? String {
                // Check if there is a pending chat.send request (returns runId)
                responseLock.lock()
                let chatSendCont = pendingChatSendResponses.removeValue(forKey: id)
                let chatSendStartedAt = pendingChatSendStartedAt.removeValue(forKey: id)
                responseLock.unlock()

                if let chatSendCont = chatSendCont {
                    let isError = json["error"] != nil
                    if isError {
                        let elapsedText = chatSendStartedAt.map { Self.elapsedMillisecondsText(since: $0) } ?? "unknown"
                        gwLog.error("phase=chat_send_ack_error request=\(id, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public) error=\(String(describing: json["error"]), privacy: .public)")
                    }
                    if !isError, let payloadDict = json["payload"] as? [String: Any],
                       let runId = payloadDict["runId"] as? String {
                        let elapsedText = chatSendStartedAt.map { Self.elapsedMillisecondsText(since: $0) } ?? "unknown"
                        gwLog.info("phase=chat_send_ack request=\(id, privacy: .public) runId=\(runId, privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
                        chatSendCont.resume(returning: runId)
                    } else {
                        chatSendCont.resume(returning: nil)
                    }
                    return
                }

                // Check if there is a pending chat.history request (returns last assistant text)
                responseLock.lock()
                let chatHistoryCont = pendingChatHistoryResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let chatHistoryCont = chatHistoryCont {
                    let isError = json["error"] != nil
                    if !isError, let payloadDict = json["payload"] as? [String: Any],
                       let messages = payloadDict["messages"] as? [[String: Any]] {
                        // Find the last assistant message
                        let lastAssistant = messages.last(where: { ($0["role"] as? String) == "assistant" })
                        if let lastAssistant = lastAssistant {
                            let text = self.extractTextFromMessage(lastAssistant)
                            chatHistoryCont.resume(returning: text.isEmpty ? nil : text)
                        } else {
                            chatHistoryCont.resume(returning: nil)
                        }
                    } else {
                        chatHistoryCont.resume(returning: nil)
                    }
                    return
                }

                // Check if there is a pending Bool request (abort, etc.)
                responseLock.lock()
                let continuation = pendingResponses.removeValue(forKey: id)
                responseLock.unlock()

                if let continuation = continuation {
                    let isError = json["error"] != nil
                    continuation.resume(returning: !isError)
                    return
                }
            }

            // No pending response matched — treat as connect ack or connect error
            let isError = json["error"] != nil
            if !isError {
                gwLog.info("Gateway connected successfully")
                // Persist the deviceToken from `helloOk.auth.deviceToken` if
                // present — lets the next connect re-bind to the same paired
                // device record (and its `approvedScopes`) without re-signing.
                self.persistDeviceTokenFromHello(json["payload"] as? [String: Any])
                // reconnectAttempt is part of the state-machine and must only be mutated
                // on stateQueue (it races with scheduleReconnect()'s `+= 1` otherwise).
                // Start heartbeat on the same queue so a stale prior timer is replaced
                // atomically with the fresh connection.
                stateQueue.async { [weak self] in
                    self?.reconnectAttempt = 0
                    self?.reconnectPending = false
                    self?.startHeartbeat()
                }
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.lastConnectError = nil
                }
            } else {
                // Connect auth failed (e.g. stale token after gateway restart).
                // Close this dead socket and reconnect with fresh credentials. The teardown
                // touches `webSocketTask` / `urlSession` so it must run on stateQueue,
                // otherwise it can race with scheduleReconnect()'s reconnect timer and
                // double-free the URLSession (crash on `_CFRelease` inside establishConnection).
                let parsedError = Self.parseConnectError(from: json["error"])
                gwLog.error("Gateway connect failed: code=\(parsedError.code) detail=\(parsedError.detailCode ?? "-") msg=\(parsedError.message). Will reconnect.")
                // If the failure looks token-related, drop our stored deviceToken
                // so the next reconnect re-pairs from scratch. Without this we'd
                // loop forever sending the same bad token. Heuristic: gateway
                // surfaces these as `detail-code` strings (see
                // connect-error-details-BuyNSAkw.js on server side).
                if Self.isDeviceTokenAuthFailure(parsedError) {
                    self.clearStoredDeviceTokenForCurrentRole()
                    gwLog.info("Cleared stored deviceToken due to token-related auth failure")
                }
                stateQueue.async { [weak self] in
                    self?.teardownSession()
                }
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.lastConnectError = parsedError
                }
                self.scheduleReconnect()
            }
        }
    }

    /// Pull `code` / `message` / `details.code` out of the gateway error envelope.
    /// Tolerant of unknown shapes: never throws, always yields something the UI
    /// can show even when the server's payload is unfamiliar.
    private static func parseConnectError(from raw: Any?) -> GatewayConnectError {
        let dict = raw as? [String: Any] ?? [:]
        let code = (dict["code"] as? String) ?? "UNKNOWN"
        let message = (dict["message"] as? String) ?? "Gateway rejected the connection"
        let detailCode = (dict["details"] as? [String: Any])?["code"] as? String
        return GatewayConnectError(code: code, detailCode: detailCode, message: message)
    }

    /// Whether `err` is the gateway saying our stored deviceToken is no good
    /// (revoked, mismatched, doesn't cover the requested scopes). When yes we
    /// drop the stored token so the next connect re-pairs from scratch.
    ///
    /// Strings derived from openclaw's `connect-error-details-BuyNSAkw.js`
    /// `ConnectErrorDetailCodes` enum + `formatGatewayAuthFailureMessage` —
    /// matched loosely on detailCode keywords so we don't pin to one exact
    /// spelling that the server might rename across versions.
    private static func isDeviceTokenAuthFailure(_ err: GatewayConnectError) -> Bool {
        let detail = (err.detailCode ?? "").lowercased()
        let msg = err.message.lowercased()
        let tokenSignals = [
            "device_token", "device-token",
            "token_revoked", "token-revoked",
            "token_mismatch", "token-mismatch",
            "scope_mismatch", "scope-mismatch",
            "device_token_mismatch",
        ]
        for s in tokenSignals {
            if detail.contains(s) || msg.contains(s) { return true }
        }
        return false
    }

    private func sendConnectRequest() {
        let requestId = UUID().uuidString
        let instanceId = UUID().uuidString
        let locale = Locale.current.language.languageCode?.identifier ?? "en"

        // Static descriptors for the v3 signed payload. Must match the
        // strings we send in `params.client.*` and `params.role` exactly —
        // the gateway re-derives the payload from those request fields and
        // verifies the signature against it. Drift here → server reports
        // "invalid device signature" and 1008-closes the socket.
        let clientId = "openclaw-macos"
        let clientMode = "webchat"
        // CRITICAL: use "darwin" (Node's `process.platform` on macOS), NOT
        // "macos". When the openclaw CLI / setup wizard ran on this same
        // machine, it auto-paired using `process.platform = "darwin"`, so
        // the server's `paired.platform` is "darwin". If our client claims
        // "macos", server detects `platformMismatch` and demands a
        // metadata-upgrade re-approval (preview-58 v2 hit exactly this on
        // 2026-05-15 19:22 — `reason=pairing required: device identity
        // changed and must be re-approved`). Aligning to "darwin" lets the
        // server match the existing record on the first try.
        let platformForAuth = "darwin"
        let deviceFamilyForAuth = ""
        let scopes = [
            // operator.write: required for chat.send / chat.abort / node.invoke
            // (the actual write-class RPCs we use). Older clients relied on
            // gateway's `if (scopes.includes("operator.admin")) return null`
            // bypass, but newer openclaw filters requested scopes against the
            // paired device's `approvedScopes`, so admin-only no longer works.
            // operator.admin: kept for cron.* / sessions.patch / etc admin RPCs.
            // operator.approvals: tool-approval RPCs.
            // operator.pairing: needed to do the device-pair handshake itself.
            "operator.admin",
            "operator.write",
            "operator.approvals",
            "operator.pairing",
        ]

        // Build auth payload from the gateway bootstrap token in
        // ~/.openclaw/openclaw.json. We intentionally do not prefer
        // device-auth.json here: a stale low-scope device token can block the
        // operator UI from reconnecting with the admin/write scopes it needs.
        let signatureToken: String? = authToken.isEmpty ? nil : authToken
        var auth: [String: Any] = [:]
        if let tok = signatureToken {
            auth["token"] = tok
        }

        // Build the v3 signed device descriptor. Skip silently if (a) the
        // gateway didn't send a connect-challenge nonce (legacy server, or
        // server crashed between accept and challenge) or (b) signing fails
        // for any reason — better to attempt a no-device connect (might still
        // succeed under admin-bypass on older gateways) than to deadlock the
        // app on an unsignable handshake.
        var device: [String: Any]? = nil
        if let nonce = pendingChallengeNonce, !nonce.isEmpty {
            let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            // Use the SAME single token we put in `auth.token`. Empty string
            // when no auth available (server's resolveSignatureToken falls
            // through to "" too in that case).
            let tokenForSignature = signatureToken ?? ""
            let signPayload = [
                "v3",
                deviceIdentity.deviceId,
                clientId,
                clientMode,
                connectRole,
                scopes.joined(separator: ","),
                String(signedAtMs),
                tokenForSignature,
                nonce,
                platformForAuth,
                deviceFamilyForAuth,
            ].joined(separator: "|")
            if let signature = DeviceIdentityStore.sign(signPayload, with: deviceIdentity),
               let publicKeyB64 = DeviceIdentityStore.publicKeyRawBase64Url(deviceIdentity) {
                device = [
                    "id": deviceIdentity.deviceId,
                    "publicKey": publicKeyB64,
                    "signature": signature,
                    "signedAt": signedAtMs,
                    "nonce": nonce,
                ]
                gwLog.info("Connect: signing v3 device payload deviceId=\(self.deviceIdentity.deviceId.prefix(12), privacy: .public)… usingBootstrapToken=\(signatureToken != nil)")
            } else {
                gwLog.warning("Connect: device payload could not be signed — falling back to non-device connect")
            }
        } else {
            gwLog.warning("Connect: no challenge nonce — falling back to non-device connect (legacy gateway?)")
        }

        // Nonce is single-use; clear so a forced reconnect that arrives
        // before the next challenge doesn't reuse a stale value.
        pendingChallengeNonce = nil

        var params: [String: Any] = [
            "minProtocol": 3,
            "maxProtocol": 4,                   // gateway accepts highest mutual; v4 unlocks newer event shapes
            "client": [
                "id": clientId,
                "version": "1.1.16",
                "platform": platformForAuth,
                "mode": clientMode,
                "instanceId": instanceId,
            ],
            "role": connectRole,
            "scopes": scopes,
            "caps": ["tool-events"],
            "auth": auth,
            "locale": locale,
        ]
        if let device = device {
            params["device"] = device
        }

        let payload: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if error != nil {
                self?.scheduleReconnect()
            }
        }
    }

    /// Persist the `deviceToken` returned in `helloOk.auth.deviceToken` after
    /// a successful pair. Subsequent connects use it (see `sendConnectRequest`)
    /// so the gateway matches us back to the same paired-device record.
    /// Returning nil here is a no-op — older gateways or fallback paths may
    /// not include `auth` in the hello payload at all.
    private func persistDeviceTokenFromHello(_ helloPayload: [String: Any]?) {
        guard let authDict = helloPayload?["auth"] as? [String: Any],
              let token = authDict["deviceToken"] as? String,
              !token.isEmpty else {
            return
        }
        let scopes = (authDict["scopes"] as? [String]) ?? []
        let role = (authDict["role"] as? String) ?? connectRole
        tokenStore.save(role: role,
                        deviceId: deviceIdentity.deviceId,
                        token: StoredDeviceAuthToken(
                            token: token,
                            scopes: scopes,
                            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
                        ))
        let scopeList = scopes.joined(separator: ",")
        gwLog.info("Persisted deviceToken for role=\(role, privacy: .public), scopes=\(scopeList, privacy: .public)")
    }

    /// Clear a stored deviceToken (typically because the gateway just told us
    /// it's revoked / mismatched). Next connect will fall back to the
    /// bootstrap-token + sign path and re-pair.
    private func clearStoredDeviceTokenForCurrentRole() {
        tokenStore.remove(role: connectRole, deviceId: deviceIdentity.deviceId)
    }

    /// Schedule a reconnect after exponential backoff.
    ///
    /// Can be invoked from any queue (URLSession delegate queue, send-callback queue,
    /// main, etc.). Coalesces concurrent invocations via `reconnectPending` — only the
    /// first call within a reconnect cycle actually arms a timer; subsequent calls are
    /// no-ops until the new connection is established (or torn down by `disconnect()`).
    ///
    /// Was: dispatched the reconnect body to `DispatchQueue.global()`, which let multiple
    /// failure callbacks each rebuild the URLSession in parallel and race on releasing
    /// the previous one — root cause of the v1.1.46 `_CFRelease` crash.
    private func scheduleReconnect() {
        stateQueue.async { [weak self] in
            guard let self = self,
                  !self.isIntentionalDisconnect,
                  !self.reconnectPending else { return }
            self.reconnectPending = true

            // Finish all active event streams so consumers don't hang forever
            self.eventLock.lock()
            let activeContinuations = self.eventContinuations
            self.eventContinuations.removeAll()
            self.eventLock.unlock()
            for (_, continuation) in activeContinuations {
                continuation.finish()
            }

            self.reconnectAttempt += 1
            // Exponential backoff: 1s, 2s, 4s, 8s, capped at maxReconnectDelay
            let delay = min(pow(2.0, Double(self.reconnectAttempt - 1)),
                            self.maxReconnectDelay)

            self.stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, !self.isIntentionalDisconnect else { return }
                // Stays inside stateQueue: teardown + rebuild are both serial.
                // reconnectPending flips false at the moment we begin establishing —
                // a fresh failure from the new socket is allowed to re-arm the timer.
                self.reconnectPending = false
                self.establishConnection()
            }
        }
    }

    // MARK: - Heartbeat (client → gateway WS-protocol ping)

    /// Start the heartbeat timer. **Caller must be on `stateQueue`.**
    ///
    /// Idempotent — any prior timer is cancelled and the outstanding-ping marker
    /// is reset before the new timer arms. Safe to call after each successful
    /// connect even if a previous heartbeat was still in some half-state.
    private func startHeartbeat() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        stopHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            self?.heartbeatTick()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    /// Cancel the heartbeat timer and clear the outstanding-ping marker.
    /// Safe to call from any queue (DispatchSourceTimer.cancel is thread-safe).
    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        outstandingPingSentAt = nil
    }

    /// Fires every `pingInterval` seconds while connected.
    ///
    /// Two cases per tick:
    ///   1. A previous ping is still outstanding AND it was sent more than
    ///      `pingTimeout` ago — the gateway never pong'd, presume dead and
    ///      force a reconnect. Without this branch we'd happily keep firing
    ///      pings into the void forever.
    ///   2. No outstanding ping — send a fresh one and record the timestamp.
    ///      The pong handler clears the marker. If the handler is invoked
    ///      with an error, the WS is provably bad and we reconnect immediately
    ///      rather than waiting for the next tick.
    private func heartbeatTick() {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let ws = webSocketTask, !isIntentionalDisconnect else { return }

        if let sentAt = outstandingPingSentAt {
            let elapsed = Date().timeIntervalSince(sentAt)
            if elapsed >= pingTimeout {
                gwLog.warning("Heartbeat: pong overdue by \(Int(elapsed))s, forcing reconnect")
                stopHeartbeat()
                scheduleReconnect()
            }
            // Else: still within the timeout window — wait, don't pile on extra pings.
            return
        }

        outstandingPingSentAt = Date()
        ws.sendPing { [weak self] error in
            // Pong handler runs on URLSession's internal queue; bounce back to
            // stateQueue so we mutate `outstandingPingSentAt` under the same
            // serialization that everything else uses.
            self?.stateQueue.async {
                guard let self = self else { return }
                if let error = error {
                    gwLog.warning("Heartbeat ping send/pong error: \(error.localizedDescription) — reconnecting")
                    self.stopHeartbeat()
                    self.scheduleReconnect()
                } else {
                    // Pong received cleanly. Clear the marker so the next tick
                    // fires a fresh ping.
                    self.outstandingPingSentAt = nil
                }
            }
        }
    }

    // MARK: - Chat Event Helpers

    private func handleAgentEventPayload(_ payload: [String: Any]) {
        guard let runId = payload["runId"] as? String else { return }
        let sessionKey = payload["sessionKey"] as? String
        guard let event = parseGatewayActivity(from: payload) else { return }
        broadcastEvent(.activity(runId: runId, sessionKey: sessionKey, event: event))
    }

    private func parseGatewayActivity(from payload: [String: Any]) -> GatewayActivityEvent? {
        let stream = payload["stream"] as? String
        let data = payload["data"] as? [String: Any] ?? [:]

        if let modelEvent = parseModelActivity(data: data, payload: payload) {
            return modelEvent
        }
        if let agentEvent = parseAgentActivity(data: data, payload: payload) {
            return agentEvent
        }

        guard stream == "tool" else {
            if stream == "error" {
                let key = stableActivityKey(prefix: "agent-error", payload: payload, data: data)
                return GatewayActivityEvent(kind: .toolFailed, detail: nil, dedupeKey: key)
            }
            return nil
        }

        let toolName = firstString(in: data, keys: ["toolName", "name", "tool", "commandName"])
            ?? firstString(in: payload, keys: ["toolName", "name", "tool"])
        let normalizedTool = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isError = boolValue(data["isError"])
            || ["error", "failed", "failure"].contains((firstString(in: data, keys: ["status", "state", "phase"]) ?? "").lowercased())

        let detail = sanitizedActivityDetail(for: normalizedTool, data: data)
        let key = stableActivityKey(prefix: "tool", payload: payload, data: data, fallback: "\(normalizedTool ?? "unknown"):\(detail ?? "")")

        if isError {
            return GatewayActivityEvent(kind: .toolFailed, detail: detail ?? toolName, dedupeKey: key)
        }

        switch normalizedTool {
        case "read", "read_file", "file_read":
            return GatewayActivityEvent(kind: .readFiles, detail: detail, dedupeKey: key)
        case "exec", "bash", "shell", "command", "run_command":
            return GatewayActivityEvent(kind: .ranCommands, detail: detail, dedupeKey: key)
        case "write", "create_file":
            return GatewayActivityEvent(kind: .createdFiles, detail: detail, dedupeKey: key)
        case "edit", "patch", "apply_patch", "str_replace", "replace", "write_file":
            return GatewayActivityEvent(kind: .editedFiles, detail: detail, dedupeKey: key)
        case "grep", "rg", "search", "glob", "find", "list", "ls", "list_dir":
            return GatewayActivityEvent(kind: .searchedCode, detail: detail, dedupeKey: key)
        case "agent", "agents", "subagent", "subagents", "delegate", "dispatch_agent":
            return GatewayActivityEvent(kind: .agentUsed, detail: detail ?? toolName, dedupeKey: key)
        case "recruit", "recruit_agent", "agent_recruit", "marketplace_agent":
            return GatewayActivityEvent(kind: .agentRecruited, detail: detail ?? toolName, dedupeKey: key)
        case .some:
            return GatewayActivityEvent(kind: .loadedTools, detail: toolName, dedupeKey: key)
        case .none:
            return nil
        }
    }

    private func parseModelActivity(data: [String: Any], payload: [String: Any]) -> GatewayActivityEvent? {
        let provider = firstString(in: data, keys: ["provider"])
        let model = firstString(in: data, keys: ["model", "modelId"])
        guard provider != nil || model != nil else { return nil }
        let detail = [provider, model]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard !detail.isEmpty else { return nil }
        let key = stableActivityKey(prefix: "model", payload: payload, data: data, fallback: detail)
        return GatewayActivityEvent(kind: .selectedModel, detail: detail, dedupeKey: key)
    }

    private func parseAgentActivity(data: [String: Any], payload: [String: Any]) -> GatewayActivityEvent? {
        let phase = (
            firstString(in: data, keys: ["phase", "action", "event", "status", "state"])
            ?? firstString(in: payload, keys: ["phase", "action", "event", "status", "state"])
            ?? ""
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

        let agentId = firstString(in: data, keys: ["agentId", "agent", "subagent", "subAgentId", "name"])
            ?? firstString(in: payload, keys: ["agentId", "agent", "subagent", "subAgentId", "name"])
        let detail = agentId.flatMap { clippedDetail($0) }
        let key = stableActivityKey(prefix: "agent", payload: payload, data: data, fallback: "\(phase):\(detail ?? "")")

        if phase.contains("recruit") || phase.contains("install") {
            return GatewayActivityEvent(kind: .agentRecruited, detail: detail, dedupeKey: key)
        }
        guard detail != nil else { return nil }
        if phase.contains("agent") || phase.contains("delegate") || phase.contains("dispatch") || phase.contains("subagent") {
            return GatewayActivityEvent(kind: .agentUsed, detail: detail, dedupeKey: key)
        }
        return nil
    }

    private func sanitizedActivityDetail(for toolName: String?, data: [String: Any]) -> String? {
        let argumentKeys: [String]
        switch toolName {
        case "read", "read_file", "file_read", "write", "create_file", "edit", "patch", "apply_patch", "str_replace", "replace", "write_file":
            argumentKeys = ["path", "file", "filePath", "target", "resolvedPath"]
        case "exec", "bash", "shell", "command", "run_command":
            argumentKeys = ["command", "cmd"]
        case "grep", "rg", "search", "glob", "find", "list", "ls", "list_dir":
            argumentKeys = ["query", "pattern", "path", "cwd", "command"]
        case "agent", "agents", "subagent", "subagents", "delegate", "dispatch_agent", "recruit", "recruit_agent", "agent_recruit", "marketplace_agent":
            argumentKeys = ["agentId", "agent", "subagent", "subAgentId", "name", "role"]
        default:
            argumentKeys = ["path", "command", "query", "name", "agentId", "agent"]
        }

        if let direct = firstString(in: data, keys: argumentKeys) {
            return clippedDetail(direct)
        }
        if let arguments = data["arguments"] as? [String: Any],
           let nested = firstString(in: arguments, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        if let input = data["input"] as? [String: Any],
           let nested = firstString(in: input, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        if let args = data["args"] as? [String: Any],
           let nested = firstString(in: args, keys: argumentKeys) {
            return clippedDetail(nested)
        }
        return nil
    }

    private func stableActivityKey(prefix: String, payload: [String: Any], data: [String: Any], fallback: String = "") -> String {
        let id = firstString(in: data, keys: ["toolCallId", "callId", "id"])
            ?? firstString(in: payload, keys: ["toolCallId", "callId", "id"])
        if let id, !id.isEmpty {
            return "\(prefix):\(id)"
        }
        let runId = payload["runId"] as? String ?? ""
        let seq = payload["seq"].map { String(describing: $0) } ?? ""
        return "\(prefix):\(runId):\(seq):\(fallback)"
    }

    private func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
            if let value = dict[key] {
                let description = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !description.isEmpty, description != "Optional(nil)" {
                    return description
                }
            }
        }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let string = value as? String {
            return ["true", "yes", "1"].contains(string.lowercased())
        }
        return false
    }

    private func clippedDetail(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 160 {
            return trimmed
        }
        return String(trimmed.prefix(157)) + "..."
    }

    private func handleChatEventPayload(_ payload: [String: Any]) {
        guard let state = payload["state"] as? String,
              let runId = payload["runId"] as? String ?? payload["idempotencyKey"] as? String,
              let sessionKey = payload["sessionKey"] as? String else {
            gwLog.warning("chat event missing required fields: state/runId/sessionKey")
            return
        }

        let event: GatewayChatEvent
        switch state {
        case "delta":
            let text = extractTextFromMessage(payload["message"])
            gwLog.debug("chat event: state=delta, runId=\(runId), textLen=\(text.count), subscribers=\(self.eventContinuations.count)")
            event = .delta(runId: runId, sessionKey: sessionKey, text: text)
        case "final":
            let text = extractTextFromMessage(payload["message"])
            let hasMessage = payload["message"] != nil
            gwLog.info("chat event: state=final, runId=\(runId), textLen=\(text.count), hasMessage=\(hasMessage), subscribers=\(self.eventContinuations.count)")
            event = .final_(runId: runId, sessionKey: sessionKey, text: text)
        case "aborted":
            event = .aborted(runId: runId, sessionKey: sessionKey)
        case "error":
            var message = ""

            // Try to extract from payload.message.errorMessage (nested-dict format)
            if let msgDict = payload["message"] as? [String: Any],
               let errorMsg = msgDict["errorMessage"] as? String {
                message = errorMsg
            }
            // Flat format: gateway also emits errorMessage directly on payload.
            // Was missing — user-visible bug: LLM-timeout errors showed up as
            // ⚠️ ["errorMessage": LLM request timed out., "seq": 2, "runId": ...,
            // "state": error, "sessionKey": ...] (whole payload dumped via
            // String(describing:) because none of the legacy paths matched).
            else if let errorMsg = payload["errorMessage"] as? String {
                message = errorMsg
            }
            // Fallback to payload.message if it's a string
            else if let msg = payload["message"] as? String {
                message = msg
            }
            // Fallback to payload.error.message
            else if let errDict = payload["error"] as? [String: Any],
                    let errMsg = errDict["message"] as? String {
                message = errMsg
            }

            // Check the full payload description for known error patterns
            let payloadDesc = String(describing: payload)
            if message.contains("Key is blocked") || payloadDesc.contains("Key is blocked") {
                message = "Your API key has exceeded its budget. For details, please visit: https://www.getclawhub.com/member/billing/"
            } else if message.contains("Unable to find token") || payloadDesc.contains("Unable to find token")
                        || message.contains("Invalid proxy server token") || payloadDesc.contains("Invalid proxy server token") {
                message = "Your API key may not exist or has been deleted. Please check: https://www.getclawhub.com/member/api-keys/"
            } else if message.isEmpty {
                // No known extraction path matched — show raw payload
                message = payloadDesc
            }

            gwLog.warning("chat error event: runId=\(runId), message=\(message)")
            event = .error(runId: runId, sessionKey: sessionKey, message: message)
        default:
            return
        }

        broadcastEvent(event)
    }

    private func extractTextFromMessage(_ message: Any?) -> String {
        guard let message = message else { return "" }

        // Direct string
        if let text = message as? String {
            return text
        }

        // Dict with content array: { content: [{type:"text", text:"..."}] }
        if let dict = message as? [String: Any] {
            if let contentArray = dict["content"] as? [[String: Any]] {
                let texts = contentArray.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                return texts.joined()
            }
            // Dict with text property
            if let text = dict["text"] as? String {
                return text
            }
        }

        return ""
    }

    private func broadcastEvent(_ event: GatewayChatEvent) {
        eventLock.lock()
        let continuations = Array(eventContinuations.values)
        eventLock.unlock()

        // Broadcast event to all active subscribers
        // Using DispatchQueue to avoid blocking if a subscriber is slow to consume
        DispatchQueue.global().async { [continuations] in
            for continuation in continuations {
                continuation.yield(event)
            }
        }
    }
}

// MARK: - URLSession WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        // Connection opened — challenge will arrive as a message
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        // Handled by receive failure path
    }
}
