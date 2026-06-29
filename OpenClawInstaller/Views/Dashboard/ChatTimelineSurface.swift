import SwiftUI

struct ChatTimelineSurface: View {
    let messages: [ChatMessage]
    @ObservedObject var viewModel: DashboardViewModel
    let proxy: ScrollViewProxy
    let columnMaxWidth: CGFloat
    let highlightedMessageId: UUID?
    let highlightedMessageFlashOn: Bool
    let onConfirmEditResend: (ChatMessage, String) -> Void
    let onCancel: (ChatMessage) -> Void

    var body: some View {
        let richMarkdownMessageIds = MarkdownRenderPolicy.recentRichMessageIds(in: messages)

        ScrollView(showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)

                LazyVStack(spacing: 16) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatTop")

                    ForEach(messages, id: \.id) { message in
                        let isLoadingPlaceholder = message.role == .assistant
                            && message.content.isEmpty
                            && message.attachments.isEmpty
                            && message.taskStatus == .loading
                        if !isLoadingPlaceholder {
                            if message.scrollTargetId != nil {
                                BackgroundTaskNotification(message: message, scrollProxy: proxy)
                                    .id(message.id)
                            } else {
                                ChatBubble(
                                    message: message,
                                    allowsRichMarkdown: richMarkdownMessageIds.contains(message.id),
                                    isJumpHighlighted: highlightedMessageId == message.id && highlightedMessageFlashOn,
                                    onConfirmEditResend: onConfirmEditResend,
                                    onCancel: onCancel
                                )
                                .id(message.id)
                            }
                        }
                    }

                    ForEach(messages.filter { $0.taskStatus == .loading && $0.content.isEmpty }, id: \.id) { loadingMsg in
                        ThinkingIndicator(
                            message: loadingMsg,
                            viewModel: viewModel
                        )
                        .id("loading-\(loadingMsg.id)")
                    }

                    Color.clear
                        .frame(width: 0, height: 0)
                        .id("chatBottom")
                }
                .frame(maxWidth: columnMaxWidth)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}
