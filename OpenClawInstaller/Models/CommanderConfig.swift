import Foundation

// MARK: - Commander Configuration

struct CommanderConfig: Codable, Equatable {
    /// Agent execution timeout in seconds (controls both openclaw --timeout and Process timeout)
    var agentTimeout: Int = 1200

    /// Maximum number of subtasks to execute in parallel (0 = unlimited)
    var maxConcurrency: Int = 0

    /// Maximum characters of progress-history.md to include in retry prompt
    var progressHistoryLimit: Int = 3000

    /// Maximum characters of taskContext to display in the panel UI
    var taskContextDisplayLimit: Int = 500

    // MARK: - Persistence

    private static var configFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.openclaw/commander-config.json"
    }

    static func load() -> CommanderConfig {
        let path = configFilePath
        guard let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(CommanderConfig.self, from: data) else {
            return CommanderConfig()
        }
        return config
    }

    func save() {
        let path = Self.configFilePath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: - Computed

    /// Graceful shutdown buffer for the CLI (seconds).
    ///
    /// Scales with task length so long tasks have proportional cleanup time,
    /// but bounded to prevent runaway buffers on pathological values.
    /// Formula: 5% of agentTimeout, with a 30s floor and 300s ceiling.
    ///
    /// Examples:
    ///   agentTimeout =  600s (10m)  → 30s   (floor)
    ///   agentTimeout = 1200s (20m)  → 60s
    ///   agentTimeout = 3600s (60m)  → 180s
    ///   agentTimeout = 7200s (2h)   → 300s  (ceiling)
    var gracefulBufferSeconds: Int {
        let proportional = Int(Double(agentTimeout) * 0.05)
        return min(max(30, proportional), 300)
    }

    /// Process-level timeout with buffer beyond agent timeout for graceful shutdown.
    /// CLI's own --timeout fires at agentTimeout; this is the safety net before SIGTERM.
    var processTimeout: TimeInterval {
        TimeInterval(agentTimeout + gracefulBufferSeconds)
    }

    /// Display string for timeout
    var timeoutDisplay: String {
        if agentTimeout >= 3600 {
            let hours = Double(agentTimeout) / 3600.0
            if hours == hours.rounded() {
                return "\(Int(hours))h"
            }
            return String(format: "%.1fh", hours)
        }
        let minutes = agentTimeout / 60
        let seconds = agentTimeout % 60
        if seconds == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(seconds)s"
    }
}
