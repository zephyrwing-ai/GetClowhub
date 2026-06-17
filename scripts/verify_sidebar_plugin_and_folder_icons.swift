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

let assetBase = "OpenClawInstaller/Assets.xcassets"
let pluginBase = "\(assetBase)/PluginIcon.imageset"
let closedFolderBase = "\(assetBase)/WorkspaceFolderClosedIcon.imageset"
let openFolderBase = "\(assetBase)/WorkspaceFolderOpenIcon.imageset"

for path in [
    "\(pluginBase)/Contents.json",
    "\(pluginBase)/plugin-day.svg",
    "\(pluginBase)/plugin-night.svg",
    "\(closedFolderBase)/Contents.json",
    "\(closedFolderBase)/folder-closed-day.svg",
    "\(closedFolderBase)/folder-closed-night.svg",
    "\(openFolderBase)/Contents.json",
    "\(openFolderBase)/folder-open-day.svg",
    "\(openFolderBase)/folder-open-night.svg"
] {
    expect(exists(path), "\(path) is missing")
}

let pluginContents = read("\(pluginBase)/Contents.json")
expect(pluginContents.contains("plugin-day.svg"), "PluginIcon should reference the light SVG")
expect(pluginContents.contains("plugin-night.svg"), "PluginIcon should reference the dark SVG")
expect(pluginContents.contains(#""appearance" : "luminosity""#), "PluginIcon should switch by luminosity")

let pluginDay = read("\(pluginBase)/plugin-day.svg")
let pluginNight = read("\(pluginBase)/plugin-night.svg")
expect(pluginDay.contains(#"viewBox="0 0 24 24""#), "PluginIcon light SVG should use a crisp 24pt viewBox")
expect(pluginNight.contains(#"viewBox="0 0 24 24""#), "PluginIcon dark SVG should use a crisp 24pt viewBox")
expect(pluginDay.contains(##"fill="#151515""##), "PluginIcon light SVG should render dark")
expect(pluginNight.contains(##"fill="#ffffff""##), "PluginIcon dark SVG should render light")
expect(pluginDay.contains("C7.1 18.2 4.5 15.6 4.5 12.4"), "PluginIcon should use the custom plug body path")

for (base, dayName, nightName) in [
    (closedFolderBase, "folder-closed-day.svg", "folder-closed-night.svg"),
    (openFolderBase, "folder-open-day.svg", "folder-open-night.svg")
] {
    let contents = read("\(base)/Contents.json")
    expect(contents.contains(dayName), "\(base) should reference the light SVG")
    expect(contents.contains(nightName), "\(base) should reference the dark SVG")
    expect(contents.contains(#""appearance" : "luminosity""#), "\(base) should switch by luminosity")
}

let closedDay = read("\(closedFolderBase)/folder-closed-day.svg")
let closedNight = read("\(closedFolderBase)/folder-closed-night.svg")
let openDay = read("\(openFolderBase)/folder-open-day.svg")
let openNight = read("\(openFolderBase)/folder-open-night.svg")
expect(closedDay.contains(##"stroke="#4f5750""##), "closed folder light SVG should use a dark outline")
expect(closedNight.contains(##"stroke="#f2f2f2""##), "closed folder dark SVG should use a light outline")
expect(openDay.contains(##"stroke="#4f5750""##), "open folder light SVG should use a dark outline")
expect(openNight.contains(##"stroke="#f2f2f2""##), "open folder dark SVG should use a light outline")
expect(closedDay.contains(#"d="M4 8.2"#), "closed folder should use the custom closed-folder outline")
expect(openDay.contains(#"d="M3.6 10.2"#), "open folder should use the custom open-folder front outline")

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
expect(
    dashboard.contains(#"navRow(.plugins, title: String(localized: "Plugins", bundle: languageManager.localizedBundle), systemImage: "puzzlepiece.fill", assetImage: "PluginIcon")"#),
    "Plugins nav row should use PluginIcon"
)
expect(dashboard.contains("private func workspaceItemIcon(item: FileItem, isExpanded: Bool) -> some View"), "WorkspaceFilePanel should render custom folder assets through a helper")
expect(dashboard.contains(#"Image(isExpanded ? "WorkspaceFolderOpenIcon" : "WorkspaceFolderClosedIcon")"#), "expanded folders should use the open-folder asset")
expect(dashboard.contains("workspaceItemIcon(item: item, isExpanded: false)"), "search result directory rows should use the closed-folder asset")

let workspacePanel = slice(dashboard, from: "private struct WorkspaceFilePanel: View", to: "private struct CommitTextField")
expect(
    !workspacePanel.contains(#"Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))"#),
    "WorkspaceFilePanel should not use the old filled SF Symbol folder"
)

print("Sidebar plugin and folder icon verification passed")
