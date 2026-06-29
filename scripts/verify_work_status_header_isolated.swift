import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func read(_ path: String) -> String {
    let url = root.appendingPathComponent(path)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        fatalError("Could not read \(path)")
    }
    return text
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

let dashboard = read("OpenClawInstaller/Views/Dashboard/DashboardView.swift")
let timeline = read("OpenClawInstaller/Views/Dashboard/ChatTimelineSurface.swift")
let workStatus = read("OpenClawInstaller/Views/Dashboard/WorkStatusHeader.swift")
let project = read("OpenClawInstaller.xcodeproj/project.pbxproj")

require(
    workStatus.contains("struct WorkStatusHeader: View"),
    "WorkStatusHeader should live in its own Dashboard component file"
)
require(
    workStatus.contains("private struct ActivitySummaryRows: View"),
    "ActivitySummaryRows should stay colocated with the working-status header"
)
require(
    workStatus.contains("private enum WorkStatusDurationText"),
    "duration formatting should stay local to WorkStatusHeader.swift"
)
require(
    !workStatus.contains("PreferenceKey") &&
        !workStatus.contains("onPreferenceChange") &&
        !workStatus.contains("Color.clear.preference") &&
        !workStatus.contains("onExpansionHeightChange"),
    "working-status expansion should not measure height and publish layout changes"
)
require(
    !dashboard.contains("WorkStatusHeaderHeightKey") &&
        !dashboard.contains("ChatScrollCompensationApplier") &&
        !dashboard.contains("compensateWorkStatusExpansion") &&
        !dashboard.contains("pendingWorkStatusScrollCompensation") &&
        !dashboard.contains("workStatusExpansionCompensationRevision"),
    "DashboardView should not own working-status scroll compensation state"
)
require(
    !timeline.contains("ChatScrollCompensationApplier") &&
        !timeline.contains("onWorkStatusExpansionHeightChange") &&
        !timeline.contains("pendingWorkStatusScrollCompensation"),
    "ChatTimelineSurface should not wire working-status expansion into scroll compensation"
)
require(
    project.contains("WorkStatusHeader.swift in Sources"),
    "WorkStatusHeader.swift must be compiled by the app target"
)

print("WorkStatusHeader is isolated from chat scroll compensation")
