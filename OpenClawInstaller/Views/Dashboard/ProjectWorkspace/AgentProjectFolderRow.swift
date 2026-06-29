import SwiftUI

struct AgentProjectFolderRow<Sessions: View>: View {
    let group: ProjectSessionGroup
    let backgroundColor: (Bool) -> SwiftUI.Color
    let onToggle: () -> Void
    let onNewSession: () -> Void
    let onRevealInFinder: () -> Void
    let onRemoveFromAgent: () -> Void
    @ViewBuilder let sessions: () -> Sessions

    var body: some View {
        SidebarCollapsibleRow(
            title: group.project.displayName,
            titleFont: .system(size: 13.5, weight: .regular),
            isExpanded: !group.binding.isCollapsed,
            rowHeight: 24,
            verticalPadding: 5,
            backgroundColor: backgroundColor,
            onToggle: onToggle,
            icon: {
                WorkspaceFolderIcon(isExpanded: !group.binding.isCollapsed, size: 18)
            },
            actions: {
                Button(action: onNewSession) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("New chat in project")
            },
            children: sessions
        )
        .contextMenu {
            Button(action: onNewSession) {
                Label("New chat in project", systemImage: "plus")
            }
            Button(action: onRevealInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive, action: onRemoveFromAgent) {
                Label("Remove from Agent", systemImage: "minus.circle")
            }
        }
    }
}
