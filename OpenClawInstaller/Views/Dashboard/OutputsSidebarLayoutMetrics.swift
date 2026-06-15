import CoreGraphics

struct OutputsSidebarLayoutMetrics {
    let collapsedWidth: CGFloat
    let browserWidth: CGFloat
    let editorWidth: CGFloat
    let minimumChatStageWidth: CGFloat
    let chatColumnMaxWidth: CGFloat

    init(
        collapsedWidth: CGFloat = 0,
        browserWidth: CGFloat = 280,
        editorWidth: CGFloat = 480,
        minimumChatStageWidth: CGFloat = 640,
        chatColumnMaxWidth: CGFloat = 820
    ) {
        self.collapsedWidth = collapsedWidth
        self.browserWidth = browserWidth
        self.editorWidth = editorWidth
        self.minimumChatStageWidth = minimumChatStageWidth
        self.chatColumnMaxWidth = chatColumnMaxWidth
    }

    func sidebarWidth(isExpanded: Bool, hasEditor: Bool, availableWidth: CGFloat) -> CGFloat {
        guard isExpanded else { return collapsedWidth }

        let desiredWidth = browserWidth + (hasEditor ? editorWidth : 0)
        let maximumSidebarWidth = max(0, availableWidth - minimumChatStageWidth)
        guard maximumSidebarWidth >= browserWidth else {
            return collapsedWidth
        }

        return min(desiredWidth, maximumSidebarWidth)
    }

    func chatColumnWidth(for availableStageWidth: CGFloat) -> CGFloat {
        min(chatColumnMaxWidth, max(0, availableStageWidth))
    }
}
