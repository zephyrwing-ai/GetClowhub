import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let dashboardViewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")

expect(
    dashboard.contains(#"navRow(.tasksLogs, title: String(localized: "Automation", bundle: languageManager.localizedBundle), systemImage: "clock.badge")"#),
    "Automation nav row must use the SF Symbol clock.badge so it renders crisply at sidebar size."
)
expect(
    !dashboard.contains(#"assetImage: "AutomationIcon""#),
    "Automation nav row must not use the custom AutomationIcon asset; SVG asset scaling blurs at 18pt."
)
expect(
    dashboard.contains("sidebarIcon(systemImage: systemImage, assetImage: assetImage)"),
    "sidebar rows must still route through the shared icon renderer."
)
expect(
    dashboard.contains("Image(systemName: systemImage)"),
    "DashboardView must render SF Symbol sidebar icons through Image(systemName:)."
)
expect(
    dashboard.contains(".frame(width: 18, height: 18)"),
    "Automation SF Symbol should remain constrained to the sidebar icon slot."
)
expect(
    dashboardViewModel.contains(#"case .tasksLogs: return "clock.badge""#),
    "DashboardTab.tasksLogs should expose the same crisp SF Symbol fallback."
)

print("Automation icon usage verification passed")
