import Foundation
import Combine
import AppKit

// MARK: - Command Stream Result

enum CommandStreamResult {
    case completed(String?)
    case timedOut(String?)
}

enum ServiceStatus: String {
    case running = "Running"
    case stopped = "Stopped"
    case starting = "Starting"
    case stopping = "Stopping"
    case error = "Error"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .starting: return "arrow.clockwise.circle.fill"
        case .stopping: return "arrow.clockwise.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .running: return "green"
        case .stopped: return "gray"
        case .starting, .stopping: return "orange"
        case .error: return "red"
        case .unknown: return "gray"
        }
    }
}

enum ServiceError: LocalizedError {
    case commandFailed(String)
    case notInstalled
    case timeout

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "Service command failed: \(message)"
        case .notInstalled:
            return "OpenClaw is not installed"
        case .timeout:
            return "Operation timed out"
        }
    }
}

@MainActor
class OpenClawService: ObservableObject {
    @Published var status: ServiceStatus = .unknown
    @Published var isMonitoring = false
    @Published var uptime: TimeInterval = 0
    @Published var version: String = ""
    @Published var port: Int = 18789
    @Published var dashboardURL: String = "http://127.0.0.1:18789"
    @Published var lastError: String?
    @Published var logs: [String] = []

    private let commandExecutor: CommandExecutor
    private var statusTimer: Timer?
    private var startTime: Date?
    var resolvedOpenclawPath: String?

    init(commandExecutor: CommandExecutor) {
        self.commandExecutor = commandExecutor
    }

    deinit {
        Task { @MainActor in
            stopMonitoring()
        }
    }

    /// The dedicated Node.js path installed by NodeInstaller
    private var dedicatedNodePath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDir)/.openclaw/node/bin/node"
    }

    // MARK: - Service Control

    /// Start OpenClaw service
    /// Uses `gateway install` which safely installs + starts the LaunchAgent.
    /// If already running, it does nothing (safe to call anytime).
    func start() async throws {
        status = .starting
        addLog("Starting OpenClaw service...")

        guard let openclawPath = await getOpenclawPath() else {
            status = .error
            let msg = "openclaw command not found at any known location"
            lastError = msg
            addLog("Failed: \(msg)")
            throw ServiceError.notInstalled
        }

        // Ensure gateway.mode is set (required by openclaw)
        if let configCmd = await openclawCmd("config set gateway.mode local 2>&1") {
            let configOutput = await runShellQuietly(configCmd)
            addLog("Config gateway.mode=local: \(configOutput ?? "ok")")
        }

        // Use our dedicated node to run `openclaw gateway install` so that
        // process.execPath points to ~/.openclaw/node/bin/node.
        // This ensures openclaw's resolvePreferredNodePath() writes our node
        // path into the launchd plist.
        let nodePath = dedicatedNodePath
        let cmd: String
        if FileManager.default.isExecutableFile(atPath: nodePath) {
            cmd = "'\(nodePath)' '\(openclawPath)' gateway install 2>&1"
            addLog("Using dedicated node: \(nodePath)")
        } else {
            // Fallback: if dedicated node not found, use openclaw directly
            cmd = "'\(openclawPath)' gateway install 2>&1"
            addLog("Warning: dedicated node not found at \(nodePath), using openclaw directly")
        }

        addLog("Running: \(cmd)")
        let output = await runShellQuietly(cmd, timeout: 30)
        addLog("Start output: \(output ?? "(no output)")")

        // Wait and retry status check — service may need time to start.
        //
        // Was: 3 × 2s = 6s. On first-install machines that's too tight:
        // launchd has to spawn a fresh node process, openclaw has to
        // generate keys, write the local registry, and only THEN bind
        // the gateway port. On slower disks or when ~/.openclaw is
        // being initialized from scratch this routinely takes 15-25s,
        // and the old window false-failed users whose gateway came up
        // moments later (they'd see "网关启动失败" on the install
        // completion screen and dismiss it, then everything worked).
        //
        // New: 9 attempts, progressive backoff, ~28s budget. Any
        // earlier success returns immediately so fast machines aren't
        // penalized.
        let backoffSeconds: [Double] = [1.5, 2.0, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]
        for (i, secs) in backoffSeconds.enumerated() {
            try await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            await checkStatus()
            if status == .running {
                addLog("OpenClaw service started successfully on attempt \(i + 1)")
                startTime = Date()
                return
            }
            addLog("Status check attempt \(i + 1): \(status.rawValue)")
        }

        status = .error
        let msg = "Service did not start. Output: \(output ?? "none")"
        lastError = msg
        addLog("Failed to start: \(msg)")
        throw ServiceError.commandFailed(msg)
    }

    /// Stop OpenClaw service
    func stop() async throws {
        status = .stopping
        addLog("Stopping OpenClaw service...")

        let cmd = await openclawCmd("gateway stop 2>&1") ?? "openclaw gateway stop 2>&1"
        let output = await runShellQuietly(cmd)
        addLog("Stop output: \(output ?? "(no output)")")

        // Wait for service to stop
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Verify stopped
        await checkStatus()

        if status == .stopped {
            addLog("OpenClaw service stopped")
            startTime = nil
            uptime = 0
        }
    }

    /// Restart OpenClaw service
    func restart() async throws {
        status = .starting
        addLog("Restarting OpenClaw service...")

        let cmd = await openclawCmd("gateway restart 2>&1") ?? "openclaw gateway restart 2>&1"
        let output = await runShellQuietly(cmd)
        addLog("Restart output: \(output ?? "(no output)")")

        // Wait for service to restart
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        await checkStatus()

        if status == .running {
            addLog("OpenClaw service restarted successfully")
            startTime = Date()
        } else {
            status = .error
            let msg = "Service did not restart"
            lastError = msg
            addLog("Failed to restart: \(msg)")
            throw ServiceError.commandFailed(msg)
        }
    }

    // MARK: - Status Monitoring

    /// Start monitoring service status
    func startMonitoring(interval: TimeInterval = 5.0) {
        guard !isMonitoring else { return }

        isMonitoring = true
        addLog("Started monitoring service status")

        // Initial check
        Task {
            await checkStatus()
        }

        // Set up timer for periodic checks
        statusTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkStatus()
            }
        }
    }

    /// Stop monitoring service status
    func stopMonitoring() {
        statusTimer?.invalidate()
        statusTimer = nil
        isMonitoring = false
        addLog("Stopped monitoring service status")
    }

    /// Check current service status
    /// Uses fast launchctl + lsof check first, then parses openclaw gateway status for details
    func checkStatus() async {
        // Step 1: Fast check via launchctl (instant, no network probes)
        let launchctlOutput = await runShellQuietly(
            "launchctl list ai.openclaw.gateway 2>&1",
            timeout: 5
        )

        if let output = launchctlOutput {
            let outputLower = output.lowercased()
            // launchctl list returns info if loaded; "could not find service" if not
            if outputLower.contains("could not find service") || outputLower.contains("no such") {
                // Service not loaded - check port as fallback
                await detectByPort()
            } else {
                // Service is loaded in launchctl, check if PID exists (running)
                // launchctl list output has "PID" = xxx; or PID = 0 if not running
                let lines = output.components(separatedBy: .newlines)
                var pidFound = false
                for line in lines {
                    // Format: "PID" = 30626; or tab-separated: pid\tstatus\tlabel
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("\"PID\"") {
                        // Property list format: "PID" = 30626;
                        if let range = trimmed.range(of: "\\d+", options: .regularExpression) {
                            let pidStr = String(trimmed[range])
                            if let pid = Int(pidStr), pid > 0 {
                                pidFound = true
                            }
                        }
                    }
                }

                if pidFound {
                    // PID exists, but verify the port is actually listening.
                    // The process may have started but failed to bind the port
                    // (e.g. "Gateway start blocked: set gateway.mode=local").
                    let portListening = await isPortListening()
                    if portListening {
                        status = .running
                        if startTime == nil { startTime = Date() }
                        if let startTime = startTime {
                            uptime = Date().timeIntervalSince(startTime)
                        }
                    } else {
                        status = .error
                        lastError = "Service process exists but gateway port \(port) is not listening"
                        uptime = 0
                        startTime = nil
                    }
                } else {
                    // Loaded but no PID; double check with port
                    await detectByPort()
                }
            }
        } else {
            // launchctl failed, try port check
            await detectByPort()
        }

        // Step 2: Get details (dashboard URL, port) from gateway status in background
        // Only do this occasionally, not every 5 seconds
        if dashboardURL == "http://127.0.0.1:18789" {
            if let statusCmd = await openclawCmd("gateway status 2>&1") {
                let gatewayOutput = await runShellQuietly(
                    statusCmd,
                    timeout: 10
                )
                if let output = gatewayOutput {
                    parseGatewayDetails(output)
                }
            }
        }

        if status != .error {
            lastError = nil
        }
    }

    /// Parse dashboard URL and port from gateway status output
    private func parseGatewayDetails(_ output: String) {
        for line in output.components(separatedBy: .newlines) {
            let lineLower = line.lowercased()

            if lineLower.hasPrefix("dashboard:") {
                if let range = line.range(of: "http[s]?://[^\\s]+", options: .regularExpression) {
                    let url = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                    dashboardURL = url
                    if let portRange = url.range(of: ":(\\d+)", options: .regularExpression) {
                        let portStr = url[portRange].dropFirst()
                        if let p = Int(portStr) {
                            port = p
                        }
                    }
                }
            }
        }
    }

    /// Check if the gateway port is currently listening
    private func isPortListening() async -> Bool {
        let lsofOutput = await runShellQuietly(
            "lsof -i :\(port) -sTCP:LISTEN 2>/dev/null | grep -c LISTEN",
            timeout: 5
        )
        let count = Int(lsofOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        return count > 0
    }

    /// Detect service by checking if the gateway port is in use
    private func detectByPort() async {
        if await isPortListening() {
            status = .running
            if startTime == nil { startTime = Date() }
        } else {
            status = .stopped
            uptime = 0
            startTime = nil
        }
    }

    /// Resolve the full path to the openclaw binary.
    /// Caches the result for subsequent calls.
    private func getOpenclawPath() async -> String? {
        if let cached = resolvedOpenclawPath {
            return cached
        }

        // 1. Try `which openclaw` via login shell
        //    zsh built-in `which` prints "openclaw not found" to stdout on failure,
        //    so we must verify the result is an actual executable path.
        if let path = await runShellQuietly("which openclaw 2>/dev/null"),
           !path.isEmpty,
           path.hasPrefix("/"),
           FileManager.default.isExecutableFile(atPath: path) {
            resolvedOpenclawPath = path
            return path
        }

        // 2. Check common locations directly
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(homeDir)/.npm-global/bin/openclaw",
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            "\(homeDir)/.volta/bin/openclaw",
            "\(homeDir)/Library/pnpm/openclaw",
            "\(homeDir)/.nvs/default/bin/openclaw",
            "\(homeDir)/tools/nvs/default/bin/openclaw",
        ]
        // nvm: scan ~/.nvm/versions/node/*/bin, pick latest version
        if let nvmBin = CommandExecutor.findLatestNvmBin(homeDir: homeDir, command: "openclaw") {
            candidates.insert(nvmBin, at: 0)
        }
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                resolvedOpenclawPath = candidate
                return candidate
            }
        }

        return nil
    }

    /// Build a shell command using the resolved openclaw path
    private func openclawCmd(_ subcommand: String) async -> String? {
        guard let path = await getOpenclawPath() else { return nil }
        return "'\(path)' \(subcommand)"
    }

    /// Build a PATH string that includes common Node.js installation directories.
    /// macOS GUI apps inherit a minimal environment from launchd, and if the user's
    /// .zshrc guards with `[[ ! -o interactive ]]` the nvm/npm-global PATH entries
    /// added in .zshrc are never loaded.  We inject them explicitly.
    static func buildEnrichedPath() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        // Gather extra directories that may contain node / openclaw
        var extraDirs: [String] = [
            "\(homeDir)/.openclaw/node/bin",       // dedicated node installed by this app
            "\(homeDir)/.npm-global/bin",           // global npm prefix
            "/opt/homebrew/bin",                    // Homebrew (Apple Silicon)
            "/opt/homebrew/opt/node/bin",           // Homebrew node keg
            "/usr/local/bin",                       // Homebrew (Intel) / system-wide
            "\(homeDir)/.volta/bin",
            "\(homeDir)/.bun/bin",
            "\(homeDir)/Library/pnpm",
            "\(homeDir)/.local/bin",
        ]
        // nvm: add the latest installed version's bin directory
        let nvmVersionsDir = "\(homeDir)/.nvm/versions/node"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmVersionsDir) {
            let sorted = entries.filter { $0.hasPrefix("v") }
                .sorted { CommandExecutor.compareNodeVersions($0, $1) }
            if let latest = sorted.first {
                extraDirs.insert("\(nvmVersionsDir)/\(latest)/bin", at: 0)
            }
        }
        // fnm
        let fnmDir = "\(homeDir)/Library/Application Support/fnm/aliases/default/bin"
        if FileManager.default.fileExists(atPath: fnmDir) {
            extraDirs.append(fnmDir)
        }

        // Start with the current process PATH (may be minimal from launchd)
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let currentDirs = Set(currentPath.components(separatedBy: ":"))

        // Prepend extra dirs that aren't already present
        var result = extraDirs.filter { !currentDirs.contains($0) }
        result.append(currentPath)
        return result.joined(separator: ":")
    }

    /// Run a shell command quietly without triggering UI updates
    /// Uses proper pipe reading pattern to avoid deadlocks, with timeout.
    /// Uses DispatchSemaphore instead of busy-wait to avoid CPU spinning.
    private func runShellQuietly(_ command: String, timeout: TimeInterval = 15) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]

                // Enrich environment with common Node.js paths so that
                // #!/usr/bin/env node shebangs work even when .zshrc is
                // skipped in non-interactive mode.
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = Self.buildEnrichedPath()
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                // Use semaphore to wait for process exit without busy-wait
                let exitSemaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    exitSemaphore.signal()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // Read data FIRST (in background), then wait for exit
                // This avoids pipe buffer deadlock
                var outputData = Data()
                let readQueue = DispatchQueue(label: "pipe.read")
                let readGroup = DispatchGroup()
                readGroup.enter()
                readQueue.async {
                    outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    readGroup.leave()
                }

                // Wait for process exit using semaphore (blocks thread, zero CPU)
                let semaphoreResult = exitSemaphore.wait(timeout: .now() + timeout)
                if semaphoreResult == .timedOut && process.isRunning {
                    // Stage 1: SIGTERM — let the process flush state and exit gracefully
                    process.terminate()

                    // Wait up to 10s for graceful exit (terminationHandler signals exitSemaphore)
                    let gracefulWait = exitSemaphore.wait(timeout: .now() + 10)

                    // Stage 2: SIGKILL fallback — prevents orphan processes that ignore SIGTERM
                    if gracefulWait == .timedOut && process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                        _ = exitSemaphore.wait(timeout: .now() + 2)
                    }
                }

                // Wait for pipe read to complete (with timeout to prevent deadlock)
                let waitResult = readGroup.wait(timeout: .now() + 5)
                if waitResult == .timedOut {
                    // Force close the pipe to unblock readDataToEndOfFile
                    try? pipe.fileHandleForReading.close()
                    readGroup.wait()
                }

                let output = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: output)
            }
        }
    }

    /// Get detailed service info
    func getServiceInfo() async -> [String: String] {
        var info: [String: String] = [:]

        info["Status"] = status.rawValue
        info["Port"] = String(port)
        info["Version"] = version.isEmpty ? "Unknown" : version

        if status == .running {
            let uptimeStr = formatUptime(uptime)
            info["Uptime"] = uptimeStr
        }

        if let error = lastError {
            info["Last Error"] = error
        }

        return info
    }

    // MARK: - Dashboard Operations

    /// Open OpenClaw dashboard in browser, with auth token appended as query parameter
    func openDashboard(authToken: String? = nil) {
        var urlString = dashboardURL
        if let token = authToken, !token.isEmpty {
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)token=\(token)"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            addLog("Opened dashboard at \(dashboardURL)")
        }
    }

    /// Open OpenClaw logs in system text editor
    func openLogs() {
        let logPath = NSString("~/.openclaw/logs/gateway.log").expandingTildeInPath
        if FileManager.default.fileExists(atPath: logPath) {
            let url = URL(fileURLWithPath: logPath)
            NSWorkspace.shared.open(url)
            addLog("Opened log file at \(logPath)")
        } else {
            addLog("Log file not found at \(logPath)")
        }
    }

    /// Read latest lines from gateway log file
    func readGatewayLogs(lines: Int = 200) async -> [String] {
        let logPath = NSString("~/.openclaw/logs/gateway.log").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: logPath) else {
            return ["Log file not found: \(logPath)"]
        }

        let output = await runShellQuietly("tail -n \(lines) '\(logPath)'", timeout: 5)
        if let output = output, !output.isEmpty {
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        } else {
            return ["Failed to read logs"]
        }
    }

    // MARK: - Version Info

    /// Get OpenClaw version
    func fetchVersion() async {
        if let cmd = await openclawCmd("--version 2>/dev/null"),
           let output = await runShellQuietly(cmd) {
            let ver = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ver.isEmpty {
                version = ver
            }
        }
    }

    // MARK: - Diagnostics

    /// Run `openclaw doctor` and return the output
    func runDoctor() async -> String {
        addLog("Running openclaw doctor...")
        guard let cmd = await openclawCmd("doctor --fix 2>&1 | sed 's/\\x1b\\[[0-9;]*m//g'") else {
            return "openclaw command not found"
        }
        // Strip ANSI color codes for clean display
        let output = await runShellQuietly(
            cmd,
            timeout: 30
        )
        return output ?? "Failed to run openclaw doctor"
    }

    // MARK: - Logs Management

    /// Add log entry
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logs.append(logEntry)

        // Keep only last 100 logs
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
    }

    /// Clear logs
    func clearLogs() {
        logs.removeAll()
        addLog("Logs cleared")
    }

    /// Get logs as string
    func getLogsString() -> String {
        return logs.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Format uptime duration
    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    /// Check if service is healthy
    func isHealthy() -> Bool {
        return status == .running && lastError == nil
    }

    /// Run an arbitrary shell command and return the output.
    /// Automatically resolves "openclaw" to the full binary path.
    func runCommand(_ command: String, timeout: TimeInterval = 30) async -> String? {
        var resolved = command
        if resolved.hasPrefix("openclaw ") || resolved.contains(" openclaw ") {
            if let fullPath = await getOpenclawPath() {
                // Use word-boundary match to avoid replacing "openclaw" inside paths like ".openclaw"
                if let range = resolved.range(of: "(?<![./\\w])openclaw(?= )", options: .regularExpression) {
                    resolved.replaceSubrange(range, with: "'\(fullPath)'")
                }
            }
        }
        return await runShellQuietly(resolved, timeout: timeout)
    }

    /// Run a shell command with streaming output.
    /// Calls `onOutput` periodically with accumulated stdout so far.
    /// Returns `.completed` or `.timedOut` with whatever output was captured.
    func runCommandStreaming(
        _ command: String,
        timeout: TimeInterval = 300,
        onOutput: @escaping @Sendable (String) -> Void,
        onProcessReady: (@Sendable (Process) -> Void)? = nil
    ) async -> CommandStreamResult {
        var resolved = command
        if resolved.hasPrefix("openclaw ") || resolved.contains(" openclaw ") {
            if let fullPath = await getOpenclawPath() {
                // Use word-boundary match to avoid replacing "openclaw" inside paths like ".openclaw"
                if let range = resolved.range(of: "(?<![./\\w])openclaw(?= )", options: .regularExpression) {
                    resolved.replaceSubrange(range, with: "'\(fullPath)'")
                }
            }
        }
        return await runShellStreaming(resolved, timeout: timeout, onOutput: onOutput, onProcessReady: onProcessReady)
    }

    /// Internal streaming shell execution.
    /// Uses DispatchSemaphore for process exit instead of busy-wait.
    private func runShellStreaming(
        _ command: String,
        timeout: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void,
        onProcessReady: (@Sendable (Process) -> Void)? = nil
    ) async -> CommandStreamResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-l", "-c", command]

                var env = ProcessInfo.processInfo.environment
                env["PATH"] = Self.buildEnrichedPath()
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                // Use semaphore to detect process exit without busy-wait
                let exitSemaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    exitSemaphore.signal()
                }

                do {
                    try process.run()
                    onProcessReady?(process)
                } catch {
                    continuation.resume(returning: .completed(nil))
                    return
                }

                // Read pipe data in a background thread, converting chunks to string incrementally
                var accumulatedString = ""
                let stringLock = NSLock()
                var hasNewData = false
                let readGroup = DispatchGroup()
                readGroup.enter()
                DispatchQueue(label: "pipe.stream.read").async {
                    let handle = pipe.fileHandleForReading
                    while true {
                        let chunk = handle.availableData
                        if chunk.isEmpty { break }  // EOF
                        if let text = String(data: chunk, encoding: .utf8) {
                            stringLock.lock()
                            accumulatedString.append(text)
                            hasNewData = true
                            stringLock.unlock()
                        }
                    }
                    readGroup.leave()
                }

                // Wait for process with timeout, periodically emitting output
                // Use semaphore.wait with 1s intervals to check for new output
                let deadline = DispatchTime.now() + timeout
                var exited = false
                while !exited {
                    let waitResult = exitSemaphore.wait(timeout: .now() + 1.0)
                    if waitResult == .success {
                        exited = true
                    } else if DispatchTime.now() >= deadline {
                        break  // timeout
                    }
                    // Emit accumulated output
                    stringLock.lock()
                    let shouldEmit = hasNewData
                    let snapshot = shouldEmit ? accumulatedString : ""
                    hasNewData = false
                    stringLock.unlock()
                    if shouldEmit {
                        onOutput(snapshot)
                    }
                }

                if !exited && process.isRunning {
                    // Stage 1: SIGTERM — give the CLI a chance to flush state and shut down
                    process.terminate()

                    // Wait up to 10s for graceful exit (independent of pipe drain)
                    let gracefulWait = exitSemaphore.wait(timeout: .now() + 10)

                    // Stage 2: SIGKILL fallback — prevents orphan agents from lingering
                    // (still consuming API tokens / budget) when SIGTERM is ignored or trapped.
                    if gracefulWait == .timedOut && process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                        _ = exitSemaphore.wait(timeout: .now() + 2)
                    }

                    // Wait with timeout to prevent deadlock if pipe reader is stuck.
                    // Bumped from 5s → 10s: long-running agents can produce a lot of
                    // late-stage output (final progress dump) that needs to drain.
                    let waitResult = readGroup.wait(timeout: .now() + 10)
                    if waitResult == .timedOut {
                        // Force close the pipe to unblock the reader
                        try? pipe.fileHandleForReading.close()
                        readGroup.wait()
                    }
                    stringLock.lock()
                    let partial = accumulatedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    stringLock.unlock()
                    continuation.resume(returning: .timedOut(partial.isEmpty ? nil : partial))
                } else {
                    let waitResult = readGroup.wait(timeout: .now() + 5)
                    if waitResult == .timedOut {
                        try? pipe.fileHandleForReading.close()
                        readGroup.wait()
                    }
                    // Emit final output
                    stringLock.lock()
                    let output = accumulatedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    stringLock.unlock()
                    if !output.isEmpty {
                        onOutput(output)
                    }
                    continuation.resume(returning: .completed(output.isEmpty ? nil : output))
                }
            }
        }
    }
}
