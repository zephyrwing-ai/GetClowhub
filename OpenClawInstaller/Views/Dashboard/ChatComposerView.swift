import SwiftUI
import UniformTypeIdentifiers

struct ChatComposerView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var inputText: String
    @Binding var attachedFiles: [URL]
    @Binding var showComposerSelector: Bool
    let isInputFocused: FocusState<Bool>.Binding
    let isInputLocked: Bool
    let shouldShowStopButton: Bool
    let currentForegroundTaskMessageId: UUID?
    let canSend: Bool
    let sendButtonFillColor: SwiftUI.Color
    let sendButtonIconColor: SwiftUI.Color
    let composerEditorHeight: CGFloat
    let onOpenFilePicker: () -> Void
    let onSendMessage: () -> Void
    let onCancelMessage: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            attachmentStrip
            editor
            toolbar
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: -2)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !attachedFiles.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachedFiles, id: \.absoluteString) { url in
                        AttachmentPreview(url: url) {
                            attachedFiles.removeAll { $0 == url }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty && !isInputFocused.wrappedValue {
                Text(String(localized: "Ask Anything", bundle: LanguageManager.shared.localizedBundle))
                    .font(DashboardTypography.composerPlaceholder)
                    .foregroundColor(Color(NSColor.placeholderTextColor).opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            TextEditor(text: $inputText)
                .font(DashboardTypography.composer)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .scrollContentBackground(.hidden)
                .tint(Color(NSColor.labelColor))
                .disabled(isInputLocked)
                .focused(isInputFocused)
                .frame(height: composerEditorHeight)
        }
        .frame(height: composerEditorHeight)
        .padding(.horizontal, 8)
        .padding(.top, attachedFiles.isEmpty ? 8 : 2)
        .padding(.bottom, 2)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button(action: onOpenFilePicker) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Attach File", bundle: LanguageManager.shared.localizedBundle))
            .disabled(isInputLocked)

            Spacer(minLength: 8)

            ComposerModelSelector(
                viewModel: viewModel,
                isOpen: $showComposerSelector
            )

            Button(action: handlePrimaryAction) {
                Image(systemName: shouldShowStopButton ? "square.fill" : "arrow.up")
                    .font(.system(size: shouldShowStopButton ? 9 : 13, weight: .semibold))
                    .foregroundColor(sendButtonIconColor)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(sendButtonFillColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend && !shouldShowStopButton)
            .animation(.easeInOut(duration: 0.15), value: canSend)
            .animation(.easeInOut(duration: 0.15), value: shouldShowStopButton)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func handlePrimaryAction() {
        if shouldShowStopButton, let messageId = currentForegroundTaskMessageId {
            onCancelMessage(messageId)
        } else {
            onSendMessage()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                guard let urlData = data as? Data,
                      let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    if !attachedFiles.contains(url) {
                        attachedFiles.append(url)
                    }
                }
            }
        }
        return true
    }
}
