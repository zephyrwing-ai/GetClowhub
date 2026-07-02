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
                SidebarProjectFolderIcon(isExpanded: !group.binding.isCollapsed, size: 18)
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

private struct SidebarProjectFolderIcon: View {
    let isExpanded: Bool
    var size: CGFloat = 18

    private var strokeWidth: CGFloat {
        max(1.35, size * 0.08)
    }

    var body: some View {
        Group {
            if isExpanded {
                SidebarOpenProjectFolderShape()
                    .stroke(style: strokeStyle)
            } else {
                SidebarClosedProjectFolderShape()
                    .stroke(style: strokeStyle)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth,
            lineCap: .round,
            lineJoin: .round
        )
    }
}

private struct SidebarClosedProjectFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            drawClosedFace(in: faceDrawingRect(in: rect), into: &path)
        }
    }

    private func drawClosedFace(in rect: CGRect, into path: inout Path) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        drawClosedEye(in: rect, centerX: x + w * 0.37, into: &path)
        drawClosedEye(in: rect, centerX: x + w * 0.63, into: &path)

        path.move(to: CGPoint(x: x + w * 0.42, y: y + h * 0.57))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.58, y: y + h * 0.57),
            control: CGPoint(x: x + w * 0.50, y: y + h * 0.68)
        )
    }

    private func drawClosedEye(in rect: CGRect, centerX: CGFloat, into path: inout Path) {
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: centerX - w * 0.06, y: y + h * 0.48))
        path.addQuadCurve(
            to: CGPoint(x: centerX + w * 0.06, y: y + h * 0.48),
            control: CGPoint(x: centerX, y: y + h * 0.35)
        )
    }
}

private struct SidebarOpenProjectFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            drawOpenFace(in: faceDrawingRect(in: rect), into: &path)
        }
    }

    private func drawOpenFace(in rect: CGRect, into path: inout Path) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: x + w * 0.31, y: y + h * 0.48))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.43, y: y + h * 0.48),
            control: CGPoint(x: x + w * 0.37, y: y + h * 0.34)
        )

        path.move(to: CGPoint(x: x + w * 0.63, y: y + h * 0.37))
        path.addLine(to: CGPoint(x: x + w * 0.63, y: y + h * 0.49))

        path.move(to: CGPoint(x: x + w * 0.43, y: y + h * 0.55))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.57, y: y + h * 0.55),
            control: CGPoint(x: x + w * 0.50, y: y + h * 0.50)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.72),
            control: CGPoint(x: x + w * 0.58, y: y + h * 0.72)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.43, y: y + h * 0.55),
            control: CGPoint(x: x + w * 0.42, y: y + h * 0.72)
        )
        path.closeSubpath()
    }
}

private func faceDrawingRect(in rect: CGRect) -> CGRect {
    rect.insetBy(dx: -rect.width * 0.42, dy: -rect.height * 0.34)
}
