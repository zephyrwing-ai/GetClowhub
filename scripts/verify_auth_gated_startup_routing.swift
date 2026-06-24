#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appPath = root
    .appendingPathComponent("OpenClawInstaller")
    .appendingPathComponent("OpenClawInstallerApp.swift")

guard let source = try? String(contentsOf: appPath, encoding: .utf8) else {
    fputs("FAIL: could not read \(appPath.path)\n", stderr)
    exit(1)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        fputs("FAIL: could not slice source between \(start) and \(end)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let mainContent = slice(
    from: "struct MainContentView: View",
    to: "private struct StartupCheckingView"
)

require(
    mainContent.contains("AuthGateView("),
    "MainContentView should render an auth gate before dashboard/installer content when login is required."
)
require(
    mainContent.contains("case .checking:") &&
        mainContent.contains("case .notLoggedIn:") &&
        mainContent.contains("case .polling") &&
        mainContent.contains("case .timeout:") &&
        mainContent.contains("case .error") &&
        mainContent.contains("case .loggedIn:"),
    "Auth gate should explicitly handle all AuthState cases."
)
require(
    mainContent.contains("guard isStartupRouteAllowed else"),
    "Startup environment routing should be blocked until auth has succeeded."
)
require(
    mainContent.contains("guard authManager.isLoggedIn else"),
    "determineInitialView should not run the environment check before login succeeds."
)
require(
    mainContent.contains(".task(id: startupRouteToken)") &&
        mainContent.contains(".onChange(of: authManager.isLoggedIn)"),
    "Startup routing should rerun when login state changes instead of only once on first render."
)
require(
    !mainContent.contains("if !authManager.isLoggedIn {\n                Color.black.opacity"),
    "Login should not be implemented as a black overlay on top of dashboard content."
)

print("Auth-gated startup routing verification passed")
