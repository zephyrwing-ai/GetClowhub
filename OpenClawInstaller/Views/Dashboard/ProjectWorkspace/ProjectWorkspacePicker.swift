import AppKit

struct ProjectWorkspacePicker {
    static func makePanel(agentName: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Choose Work Folder for \(agentName)"
        panel.message = "Select the local folder this agent should work in. GetClowHub will remember it under this agent. Files stay local and are only read when needed."
        panel.prompt = "Use as Work Folder"
        panel.nameFieldLabel = "Work Folder:"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel
    }
}
