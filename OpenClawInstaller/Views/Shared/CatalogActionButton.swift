import SwiftUI

struct CatalogActionButton: View {
    enum Tone {
        case install
        case neutral
        case destructive
    }

    enum State {
        case normal
        case loading
        case completed
        case disabled
    }

    let title: String
    let loadingTitle: String
    let completedTitle: String
    let systemImage: String?
    let completedSystemImage: String?
    let tone: Tone
    let state: State
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        loadingTitle: String,
        completedTitle: String,
        systemImage: String? = nil,
        completedSystemImage: String? = "checkmark.circle.fill",
        tone: Tone = .install,
        state: State,
        width: CGFloat = 92,
        height: CGFloat = 30,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.completedTitle = completedTitle
        self.systemImage = systemImage
        self.completedSystemImage = completedSystemImage
        self.tone = tone
        self.state = state
        self.width = width
        self.height = height
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            content
                .font(.system(size: 13, weight: .medium))
                .frame(width: width, height: height)
        }
        .buttonStyle(
            CatalogActionButtonStyle(
                tone: tone,
                isDisabled: isDisabled
            )
        )
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingTitle)
            }
        case .completed:
            label(title: completedTitle, systemImage: completedSystemImage)
        case .normal, .disabled:
            label(title: title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func label(title: String, systemImage: String?) -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        } else {
            Text(title)
        }
    }

    private var isDisabled: Bool {
        switch state {
        case .normal:
            return false
        case .loading, .completed, .disabled:
            return true
        }
    }
}

private struct CatalogActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let tone: CatalogActionButton.Tone
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor.opacity(configuration.isPressed ? 1 : 0.82), lineWidth: borderWidth)
            )
            .opacity(isDisabled ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tone {
        case .install:
            return CatalogActionPalette.amber
        case .neutral:
            return .primary
        case .destructive:
            return Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .install:
            return CatalogActionPalette.amber.opacity(colorScheme == .dark ? 0.18 : 0.12)
        case .neutral:
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.08)
        case .destructive:
            return Color(red: 1.0, green: 0.18, blue: 0.20)
                .opacity(colorScheme == .dark ? 0.20 : 0.14)
        }
    }

    private var borderColor: Color {
        switch tone {
        case .install:
            return CatalogActionPalette.copper.opacity(colorScheme == .dark ? 0.44 : 0.30)
        case .neutral, .destructive:
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        switch tone {
        case .install:
            return 1
        case .neutral, .destructive:
            return 0
        }
    }
}

private enum CatalogActionPalette {
    static let amber = Color(red: 0.72, green: 0.47, blue: 0.12)
    static let copper = Color(red: 0.66, green: 0.40, blue: 0.23)
}
