import Combine
import Foundation

@MainActor
class InstallationViewModel: ObservableObject {
    @Published var installationState: InstallationState
    @Published var systemEnvironment: SystemEnvironment
    @Published var nodeInstaller: NodeInstaller
    @Published var openclawInstaller: OpenClawInstaller
    let openclawService: OpenClawService

    // Configuration
    @Published var gatewayAuthToken: String = ""

    // Gateway auto-start state
    @Published var gatewayStarting: Bool = false
    @Published var gatewayStarted: Bool = false
    @Published var gatewayError: String?

    private let commandExecutor: CommandExecutor
    private var cancellables = Set<AnyCancellable>()

    init(
        installationState: InstallationState,
        systemEnvironment: SystemEnvironment,
        commandExecutor: CommandExecutor,
        openclawService: OpenClawService
    ) {
        self.installationState = installationState
        self.systemEnvironment = systemEnvironment
        self.commandExecutor = commandExecutor
        self.openclawService = openclawService
        self.nodeInstaller = NodeInstaller(commandExecutor: commandExecutor)
        self.openclawInstaller = OpenClawInstaller(commandExecutor: commandExecutor)

        // Forward child objectWillChange so SwiftUI re-renders
        installationState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        systemEnvironment.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        nodeInstaller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        openclawInstaller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Start installation wizard
    func startWizard() {
        installationState.reset()
        installationState.goToStep(.welcome)
    }

    /// Perform environment check
    func performEnvironmentCheck() async {
        installationState.isInstalling = true
        installationState.updateProgress(0.1, message: "Checking system environment...")

        await systemEnvironment.performFullCheck()

        installationState.updateProgress(0.5, message: "Analyzing requirements...")

        // Check requirements
        let (passed, issues) = systemEnvironment.checkRequirements()

        if !passed {
            let errorMessage = "System requirements not met:\n" + issues.joined(separator: "\n")
            installationState.setError(errorMessage)
            installationState.isInstalling = false
            return
        }

        // Determine what needs to be installed
        if systemEnvironment.nodeInfo == nil {
            installationState.nodeInstallationRequired = true
            installationState.updateProgress(0.7, message: "Node.js installation required")
        } else if let nodeInfo = systemEnvironment.nodeInfo, !nodeInfo.isCompatible {
            installationState.nodeInstallationRequired = true
            installationState.updateProgress(0.7, message: "Node.js upgrade required")
        } else {
            installationState.nodeInstallationRequired = false
            installationState.nodeInstallationComplete = true
            installationState.updateProgress(0.7, message: "Node.js already installed")
        }

        // Check if OpenClaw is already installed
        if systemEnvironment.openclawInfo != nil {
            installationState.openclawInstallationRequired = false
            installationState.openclawInstallationComplete = true
            installationState.updateProgress(1.0, message: "OpenClaw already installed")
        } else {
            installationState.openclawInstallationRequired = true
            installationState.updateProgress(1.0, message: "OpenClaw installation required")
        }

        installationState.isInstalling = false

        // Move to next step
        if installationState.nodeInstallationRequired {
            installationState.goToStep(.nodeInstallation)
        } else if installationState.openclawInstallationRequired {
            installationState.goToStep(.openclawInstallation)
        } else {
            installationState.goToStep(.configuration)
        }
    }

    /// Install Node.js
    func installNodeJS() async {
        installationState.isInstalling = true
        installationState.updateProgress(0.0, message: "Starting Node.js installation...")

        do {
            try await nodeInstaller.installNodeJS()

            installationState.nodeInstallationComplete = true
            installationState.updateProgress(1.0, message: "Node.js installed successfully")

            // Refresh environment
            await systemEnvironment.detectNode()

            // Move to next step after a short delay
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            installationState.isInstalling = false

            if installationState.openclawInstallationRequired {
                installationState.goToStep(.openclawInstallation)
            } else {
                installationState.goToStep(.configuration)
            }

        } catch {
            installationState.setError("Node.js installation failed: \(error.localizedDescription)")
        }
    }

    /// Install OpenClaw
    func installOpenClaw() async {
        installationState.isInstalling = true
        installationState.updateProgress(0.0, message: "Starting OpenClaw installation...")

        do {
            try await openclawInstaller.installOpenClaw()

            installationState.openclawInstallationComplete = true
            installationState.updateProgress(1.0, message: "OpenClaw installed successfully")

            // Refresh environment
            await systemEnvironment.detectOpenClaw()

            // Move to configuration
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            installationState.isInstalling = false
            installationState.goToStep(.configuration)

        } catch {
            installationState.setError("OpenClaw installation failed: \(error.localizedDescription)")
        }
    }

    /// Save gateway auth token to config and proceed
    func saveTokenAndContinue() async {
        installationState.isInstalling = true
        installationState.updateProgress(0.0, message: "Saving gateway configuration...")

        let configPath = NSString("~/.openclaw/openclaw.json").expandingTildeInPath
        let fm = FileManager.default

        // Ensure ~/.openclaw/ directory exists
        let dir = (configPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Read existing config or start fresh
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        // Write gateway.auth.token and gateway.mode
        var gateway = dict["gateway"] as? [String: Any] ?? [:]
        var auth = gateway["auth"] as? [String: Any] ?? [:]
        auth["token"] = gatewayAuthToken
        gateway["auth"] = auth
        gateway["mode"] = "local"
        dict["gateway"] = gateway

        // Write tools.profile: "full"
        var tools = dict["tools"] as? [String: Any] ?? [:]
        tools["profile"] = "full"
        dict["tools"] = tools

        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath), options: .atomic)

            installationState.configurationComplete = true
            installationState.updateProgress(1.0, message: "Configuration saved")

            try await Task.sleep(nanoseconds: 1_000_000_000)
            installationState.isInstalling = false
            installationState.goToStep(.complete)
        } catch {
            installationState.setError("Failed to save configuration: \(error.localizedDescription)")
        }
    }

    /// Generate a random auth token
    func generateRandomToken() {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        gatewayAuthToken = String((0..<32).map { _ in chars.randomElement()! })
    }

    /// Retry current step
    func retryCurrentStep() async {
        installationState.clearError()

        switch installationState.currentStep {
        case .environmentCheck:
            await performEnvironmentCheck()
        case .nodeInstallation:
            await installNodeJS()
        case .openclawInstallation:
            await installOpenClaw()
        case .configuration:
            await saveTokenAndContinue()
        default:
            break
        }
    }

    /// Cancel installation
    func cancelInstallation() {
        if nodeInstaller.isInstalling {
            nodeInstaller.cancelDownload()
        }

        installationState.reset()
    }

    /// Auto-start the openclaw gateway service
    func startGateway() async {
        guard !gatewayStarting && !gatewayStarted else { return }
        gatewayStarting = true
        gatewayError = nil

        // Pass the verified openclaw path from installer to service
        // so it doesn't need to resolve it again
        if let path = openclawInstaller.verifiedOpenclawPath {
            openclawService.resolvedOpenclawPath = path
        }

        do {
            try await openclawService.start()
            gatewayStarted = true
        } catch let err as ServiceError {
            gatewayError = err.localizedDescription
            startRecoveryWatcher()
        } catch {
            gatewayError = error.localizedDescription
            startRecoveryWatcher()
        }

        gatewayStarting = false
    }

    /// Even after start() throws, the gateway often is still spinning up
    /// — on first installs we routinely see the launchctl PID + port
    /// become healthy 30-60s after the install command returned. Watch
    /// for up to 60s; if the service comes up, flip gatewayStarted = true
    /// and clear the error. This is the safety net that turns the
    /// "网关启动失败" toast into silent success when the boot was just
    /// slow.
    private func startRecoveryWatcher() {
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s cadence
                // User retried and it worked, or moved on — stop polling.
                if gatewayStarted { return }
                await openclawService.checkStatus()
                if openclawService.status == .running {
                    gatewayStarted = true
                    gatewayError = nil
                    return
                }
            }
        }
    }

    /// Get overall progress
    func getOverallProgress() -> Double {
        let totalSteps = 4.0 // Environment check, Node install, OpenClaw install, Configuration
        var completedSteps = 0.0

        if systemEnvironment.nodeInfo != nil || installationState.nodeInstallationComplete {
            completedSteps += 1.0
        }

        if systemEnvironment.openclawInfo != nil || installationState.openclawInstallationComplete {
            completedSteps += 1.0
        }

        if installationState.configurationComplete {
            completedSteps += 1.0
        }

        // Add current step progress
        let currentStepProgress: Double
        switch installationState.currentStep {
        case .environmentCheck:
            currentStepProgress = 0.5
        case .nodeInstallation:
            currentStepProgress = nodeInstaller.downloadProgress
        case .openclawInstallation:
            currentStepProgress = openclawInstaller.installationProgress
        case .configuration:
            currentStepProgress = 0.5
        case .complete:
            currentStepProgress = 1.0
            completedSteps = totalSteps
        default:
            currentStepProgress = 0.0
        }

        if installationState.currentStep != .complete {
            completedSteps += currentStepProgress
        }

        return completedSteps / totalSteps
    }
}
