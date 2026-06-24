import SwiftUI

struct DashboardModalOverlay<Content: View>: View {
    let isDismissDisabled: Bool
    let scrimOpacity: Double
    let verticalOffset: CGFloat
    let onDismiss: () -> Void
    private let content: Content

    init(
        isDismissDisabled: Bool,
        scrimOpacity: Double = 0.001,
        verticalOffset: CGFloat = 0,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isDismissDisabled = isDismissDisabled
        self.scrimOpacity = scrimOpacity
        self.verticalOffset = verticalOffset
        self.onDismiss = onDismiss
        self.content = content()
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                    .opacity(scrimOpacity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isDismissDisabled else { return }
                        onDismiss()
                    }

                content
                    .padding(28)
                    .offset(y: verticalOffset)
                    .onTapGesture {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .center))
        ))
    }
}
