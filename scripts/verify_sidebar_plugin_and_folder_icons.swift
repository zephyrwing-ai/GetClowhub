import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ haystack: String, from start: String, to end: String) -> String {
    guard let startRange = haystack.range(of: start),
          let endRange = haystack[startRange.upperBound...].range(of: end) else {
        fatalError("Could not slice source between \(start) and \(end)")
    }
    return String(haystack[startRange.lowerBound..<endRange.lowerBound])
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let dashboardViewModel = read("OpenClawInstaller/ViewModels/DashboardViewModel.swift")
let config = read("OpenClawInstaller/Views/Dashboard/ConfigTabView.swift")
let plugins = read("OpenClawInstaller/Views/Dashboard/Plugins/PluginsTabView.swift")
let workspaceInspector = read("OpenClawInstaller/Views/Dashboard/Inspector/WorkspaceInspectorPane.swift")
let agentProjectFolderRow = read("OpenClawInstaller/Views/Dashboard/ProjectWorkspace/AgentProjectFolderRow.swift")
let workspaceFolderIcon = read("OpenClawInstaller/Views/Shared/WorkspaceFolderIcon.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")
let assetBase = "OpenClawInstaller/Assets.xcassets"
expect(dashboard.contains(#"navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "powerplug.portrait")"#), "Dashboard sidebar Plugins row should use the system powerplug.portrait icon")
expect(dashboardViewModel.contains(#"case .plugins: return "powerplug.portrait""#), "Dashboard view model should use the system powerplug.portrait icon for Plugins")
expect(config.contains(#"previewSidebarRow(icon: "powerplug.portrait", title: localizedString("Plugins"), active: false)"#), "settings preview sidebar should use the system powerplug.portrait icon for Plugins")
expect(plugins.contains(#"Image(systemName: defaultSystemIconName)"#), "plugin catalog fallback should render a system icon instead of an asset")
expect(plugins.contains(#"private let defaultSystemIconName = "powerplug.portrait""#), "plugin catalog fallback should use the system powerplug.portrait icon")
expect(!plugins.contains(#"Image("PluginIcon")"#), "plugin catalog fallback should not use the PluginIcon asset")
expect(!dashboard.contains("puzzlepiece.fill"), "Dashboard sidebar should not use the old puzzlepiece Plugins icon")
expect(!dashboardViewModel.contains("puzzlepiece.fill"), "Dashboard view model should not use the old puzzlepiece Plugins icon")
expect(!config.contains("puzzlepiece.fill"), "settings preview sidebar should not use the old puzzlepiece Plugins icon")
expect(workspaceFolderIcon.contains("struct WorkspaceFolderIcon: View"), "shared folder icon component should exist")
expect(workspaceFolderIcon.contains("struct ClosedWorkspaceFolderShape: Shape"), "closed folder icon should be drawn as a SwiftUI Shape")
expect(workspaceFolderIcon.contains("struct OpenWorkspaceFolderShape: Shape"), "open folder icon should be drawn as a SwiftUI Shape")
expect(workspaceFolderIcon.contains("func path(in rect: CGRect) -> Path"), "folder icon shapes should render with Path")
expect(workspaceFolderIcon.contains("Path { path in"), "folder icon should draw explicit vector paths")
expect(!workspaceFolderIcon.contains("drawClosedFace"), "shared folder icon should not render the sidebar-only face glyph")
expect(!workspaceFolderIcon.contains("drawOpenFace"), "shared folder icon should not render the sidebar-only face glyph")
expect(!workspaceFolderIcon.contains("faceDrawingRect"), "shared folder icon should not use the sidebar-only enlarged face glyph")
expect(agentProjectFolderRow.contains("struct SidebarProjectFolderIcon: View"), "sidebar project folder should own the face glyph icon")
expect(agentProjectFolderRow.contains("drawClosedFace"), "sidebar closed project folder icon should render the face glyph")
expect(agentProjectFolderRow.contains("drawOpenFace"), "sidebar open project folder icon should render the face glyph")
expect(agentProjectFolderRow.contains("faceDrawingRect"), "sidebar project folder face glyph should be enlarged inside the existing icon frame")
expect(agentProjectFolderRow.contains("dx: -rect.width * 0.42"), "sidebar project folder face glyph should be visibly enlarged horizontally")
expect(agentProjectFolderRow.contains("dy: -rect.height * 0.34"), "sidebar project folder face glyph should be visibly enlarged vertically")
expect(workspaceFolderIcon.contains("StrokeStyle("), "folder icon should use stroked SF-like line art")
expect(workspaceFolderIcon.contains("lineCap: .round"), "folder icon strokes should use rounded caps")
expect(workspaceFolderIcon.contains("lineJoin: .round"), "folder icon strokes should use rounded joins")
expect(!workspaceFolderIcon.contains("Image(systemName:"), "shared folder icon should not render unavailable SF Symbols")
expect(!workspaceFolderIcon.contains("WorkspaceFolderOpenIcon") && !workspaceFolderIcon.contains("WorkspaceFolderClosedIcon"), "shared folder icon should not depend on asset catalog folder icons")
expect(!exists("\(assetBase)/WorkspaceFolderClosedIcon.imageset/folder-closed.png"), "closed folder icon should not depend on a PNG asset")
expect(!exists("\(assetBase)/WorkspaceFolderOpenIcon.imageset/folder-open.png"), "open folder icon should not depend on a PNG asset")
expect(workspaceFolderIcon.contains(".foregroundStyle(.secondary)"), "shared folder icon should use semantic color for light/dark mode")
expect(!workspaceFolderIcon.contains(".foregroundColor(.black)") && !workspaceFolderIcon.contains(".foregroundColor(.white)"), "shared folder icon should not hardcode light/dark colors")
expect(workspaceFolderIcon.contains(".frame(width: size, height: size)"), "shared folder icon should expose a reusable size")
expect(project.contains("WorkspaceFolderIcon.swift in Sources"), "WorkspaceFolderIcon should be part of the app target sources")
expect(workspaceInspector.contains("private func workspaceItemIcon(item: FileItem, isExpanded: Bool) -> some View"), "WorkspaceFilePanel should render folders through a shared helper")
expect(workspaceInspector.contains("WorkspaceFolderIcon(isExpanded: isExpanded, size: 20)"), "expanded workspace folders should use the shared folder icon component")
expect(workspaceInspector.contains("projectItemIcon(item: item, isExpanded: false)"), "search result directory rows should use the closed shared folder icon")
expect(agentProjectFolderRow.contains("SidebarProjectFolderIcon(isExpanded: !group.binding.isCollapsed, size: 18)"), "agent project folder rows should use the sidebar-only folder icon component")
expect(dashboard.contains("WorkspaceFolderIcon(isExpanded: false, size: 20)"), "attachment directory previews should use the shared closed folder icon at 20pt")

let workspacePanel = slice(workspaceInspector, from: "private struct WorkspaceFilePanel: View", to: "private struct ProjectFilesPanel: View")
expect(
    !workspacePanel.contains(#"Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))"#),
    "WorkspaceFilePanel should not use the old filled SF Symbol folder"
)

let attachmentPreview = slice(dashboard, from: "struct AttachmentPreview: View", to: "// MARK: - Success Toast")
expect(
    !attachmentPreview.contains(#""folder.fill""#),
    "AttachmentPreview should not use the old filled SF Symbol folder"
)

print("Sidebar plugin and folder icon verification passed")
