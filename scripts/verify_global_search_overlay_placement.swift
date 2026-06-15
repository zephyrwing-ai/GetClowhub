import Foundation

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let path = "OpenClawInstaller/Views/Dashboard/DashboardView.swift"
let source = try String(contentsOfFile: path, encoding: .utf8)

guard let dashboardStart = source.range(of: "struct DashboardView: View")?.lowerBound,
      let sidebarStart = source.range(of: "struct SidebarView: View")?.lowerBound else {
    fail("could not find DashboardView and SidebarView declarations")
}

let dashboardSection = String(source[dashboardStart..<sidebarStart])
let sidebarSection = String(source[sidebarStart...])

guard dashboardSection.contains("isGlobalSessionSearchPresented"),
      dashboardSection.contains("globalSessionSearchOverlay") else {
    fail("global search overlay must be owned by DashboardView so it can cover the full split view")
}

guard !sidebarSection.contains("globalSessionSearchOverlay") else {
    fail("global search overlay is still attached to SidebarView and will be clipped to the sidebar column")
}

print("Global search overlay placement verification passed")
