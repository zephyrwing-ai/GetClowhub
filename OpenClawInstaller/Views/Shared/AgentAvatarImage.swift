import SwiftUI

struct AgentAvatarImage: View {
    let size: CGFloat
    var isExpanded: Bool = false

    var body: some View {
        Image(isExpanded ? "AgentAvatarExpanded" : "AgentAvatar")
            .resizable()
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
