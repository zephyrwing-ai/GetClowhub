import SwiftUI
import Combine

// MARK: - PersonaTabView

struct PersonaTabView: View {
    // Resolve the main agent's *real* workspace (e.g. workspace-main when main
    // isn't the default agent) so persona edits land where the runtime reads
    // them — not the stale bare ~/.openclaw/workspace.
    @StateObject private var viewModel = PersonaViewModel(
        basePath: DashboardViewModel.resolveAgentWorkspace("main")
    )
    @State private var showSaveSuccess = false
    @State private var saveSuccessMessage = ""

    @State private var expandedFile: PersonaViewModel.FileType?

    fileprivate struct FileCardInfo: Identifiable {
        let id: PersonaViewModel.FileType
        let title: String
        let icon: String
        let emoji: String
        let description: String
    }

    private let fileCards: [FileCardInfo] = [
        FileCardInfo(id: .identity, title: "IDENTITY.md", icon: "person.crop.circle", emoji: "🪪", description: "Name, creature, vibe, emoji"),
        FileCardInfo(id: .soul, title: "SOUL.md", icon: "heart.fill", emoji: "💜", description: "Personality and behavior"),
        FileCardInfo(id: .user, title: "USER.md", icon: "person.fill", emoji: "👤", description: "User preferences"),
        FileCardInfo(id: .memory, title: "MEMORY.md", icon: "brain.head.profile", emoji: "🧠", description: "Long-term memory"),
    ]

    private var fileRows: [[FileCardInfo]] {
        stride(from: 0, to: fileCards.count, by: 2).map { i in
            Array(fileCards[i..<min(i + 2, fileCards.count)])
        }
    }

    private func contentBinding(for file: PersonaViewModel.FileType) -> Binding<String> {
        switch file {
        case .identity: return $viewModel.identityContent
        case .soul: return $viewModel.soulContent
        case .user: return $viewModel.userContent
        case .memory: return $viewModel.memoryContent
        }
    }

    private func isDirty(for file: PersonaViewModel.FileType) -> Bool {
        switch file {
        case .identity: return viewModel.identityDirty
        case .soul: return viewModel.soulDirty
        case .user: return viewModel.userDirty
        case .memory: return viewModel.memoryDirty
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 24) {
                    // Identity Card
                    if let identity = viewModel.parsedIdentity {
                        IdentityCardView(identity: identity)
                    }

                    // File card grid (2 columns)
                    VStack(spacing: 12) {
                        ForEach(Array(fileRows.enumerated()), id: \.offset) { _, row in
                            // Card row
                            HStack(spacing: 12) {
                                ForEach(row) { card in
                                    PersonaFileCard(
                                        card: card,
                                        isSelected: expandedFile == card.id,
                                        isDirty: isDirty(for: card.id),
                                        onTap: {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                expandedFile = (expandedFile == card.id) ? nil : card.id
                                            }
                                        }
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                                if row.count < 2 {
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }

                            // Expanded editor below the row
                            if let expanded = expandedFile,
                               row.contains(where: { $0.id == expanded }),
                               let card = row.first(where: { $0.id == expanded }) {
                                PersonaFilePanel(
                                    card: card,
                                    content: contentBinding(for: expanded),
                                    isDirty: isDirty(for: expanded),
                                    onClose: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            expandedFile = nil
                                        }
                                    },
                                    onSave: {
                                        viewModel.save(file: expanded)
                                        showSaveToast(String(format: String(localized: "%@ saved"), card.title))
                                    }
                                )
                                .id("persona-detail-\(card.title)")
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: expandedFile)
                }
                .padding(24)
            }
            .onChange(of: expandedFile) { newValue in
                if let file = newValue, let card = fileCards.first(where: { $0.id == file }) {
                    withAnimation {
                        scrollProxy.scrollTo("persona-detail-\(card.title)", anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if showSaveSuccess {
                SuccessToast(message: saveSuccessMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showSaveSuccess)
        .onAppear { viewModel.loadAll() }
    }

    private func showSaveToast(_ message: String) {
        saveSuccessMessage = message
        showSaveSuccess = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSaveSuccess = false
        }
    }
}

// MARK: - Persona File Card (summary)

private struct PersonaFileCard: View {
    let card: PersonaTabView.FileCardInfo
    let isSelected: Bool
    let isDirty: Bool
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Text(card.emoji)
                    .font(.system(size: 32))

                HStack(spacing: 4) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(1)
                    if isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(isHovering ? 0.15 : 0.05), radius: isHovering ? 6 : 2, y: isHovering ? 3 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Persona File Panel (expanded editor)

private struct PersonaFilePanel: View {
    let card: PersonaTabView.FileCardInfo
    @Binding var content: String
    let isDirty: Bool
    let onClose: () -> Void
    let onSave: () -> Void

    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: card.icon)
                    .foregroundColor(.accentColor)
                    .font(.title3)

                Text(card.title)
                    .font(.headline)

                if isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                HStack(spacing: 8) {
                    if isDirty {
                        Button("Save") { onSave() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }

                    Button(action: {
                        withAnimation { isEditing.toggle() }
                    }) {
                        Label(isEditing ? "Preview" : "Edit",
                              systemImage: isEditing ? "eye" : "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Divider()

            // Content
            if isEditing {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200, maxHeight: 400)
                    .padding(8)
                    .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    MarkdownRendererView(markdown: content)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 400)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
        )
    }
}

// MARK: - Identity Card

struct IdentityCardView: View {
    let identity: ParsedIdentity

    var body: some View {
        HStack(spacing: 16) {
            Text(identity.emoji)
                .font(.system(size: 48))

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text(identity.creature)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !identity.vibe.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(identity.vibe)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Markdown File Editor

struct MarkdownFileEditor: View {
    let title: String
    let icon: String
    @Binding var content: String
    let isDirty: Bool
    let onSave: () -> Void
    var initiallyExpanded: Bool = true

    @State private var isExpanded: Bool = true
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Image(systemName: icon)
                        .foregroundColor(.accentColor)

                    Text(title)
                        .font(.headline)

                    if isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }

                    Spacer()

                    if isExpanded {
                        HStack(spacing: 8) {
                            if isDirty {
                                Button("Save") {
                                    onSave()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(action: {
                                withAnimation { isEditing.toggle() }
                            }) {
                                Label(isEditing ? "Preview" : "Edit",
                                      systemImage: isEditing ? "eye" : "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .onTapGesture {} // prevent header toggle
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Content area
            if isExpanded {
                Divider()

                if isEditing {
                    // Edit mode
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200, maxHeight: 400)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                } else {
                    // Preview mode - render markdown
                    ScrollView {
                        MarkdownRendererView(markdown: content)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 400)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .onAppear {
            isExpanded = initiallyExpanded
        }
    }
}

struct MarkdownRendererView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, element in
                element
            }
        }
    }

    private func parseLines() -> [AnyView] {
        guard !markdown.isEmpty else {
            return [AnyView(Text("(empty)").foregroundColor(.secondary).italic())]
        }

        var views: [AnyView] = []
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    let code = codeLines.joined(separator: "\n")
                    views.append(AnyView(
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    ))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                views.append(AnyView(Spacer().frame(height: 4)))
            } else if trimmed.hasPrefix("# ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(2))))
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 4)
                ))
            } else if trimmed.hasPrefix("## ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(3))))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 2)
                ))
            } else if trimmed.hasPrefix("### ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(4))))
                        .font(.headline)
                        .padding(.top, 2)
                ))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                views.append(AnyView(
                    Divider().padding(.vertical, 4)
                ))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletText = String(trimmed.dropFirst(2))
                views.append(AnyView(
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(renderInline(bulletText))
                    }
                    .padding(.leading, 8)
                ))
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let numberPart = String(trimmed[match])
                let rest = String(trimmed[match.upperBound...])
                views.append(AnyView(
                    HStack(alignment: .top, spacing: 4) {
                        Text(numberPart)
                            .foregroundColor(.secondary)
                        Text(renderInline(rest))
                    }
                    .padding(.leading, 8)
                ))
            } else if trimmed.hasPrefix("> ") {
                let quoteText = String(trimmed.dropFirst(2))
                views.append(AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 3)
                        Text(renderInline(quoteText))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.leading, 10)
                            .padding(.vertical, 4)
                    }
                ))
            } else {
                views.append(AnyView(
                    Text(renderInline(trimmed))
                ))
            }
        }

        // Handle unclosed code block
        if inCodeBlock && !codeLines.isEmpty {
            let code = codeLines.joined(separator: "\n")
            views.append(AnyView(
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            ))
        }

        return views
    }

    /// Render inline markdown: **bold**, *italic*, _italic_, `code`, ~~strike~~
    private func renderInline(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Bold: **text**
        applyInlinePattern(&result, pattern: #"\*\*(.+?)\*\*"#) { sub in
            sub.font = .body.bold()
        }

        // Bold: __text__
        applyInlinePattern(&result, pattern: #"__(.+?)__"#) { sub in
            sub.font = .body.bold()
        }

        // Italic: *text* (single asterisk, not preceded/followed by *)
        applyInlinePattern(&result, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#) { sub in
            sub.font = .body.italic()
        }

        // Italic: _text_
        applyInlinePattern(&result, pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#) { sub in
            sub.font = .body.italic()
        }

        // Code: `text`
        applyInlinePattern(&result, pattern: #"`(.+?)`"#) { sub in
            sub.font = .system(.body, design: .monospaced)
            sub.backgroundColor = Color(NSColor.textBackgroundColor).opacity(0.5)
        }

        return result
    }

    private func applyInlinePattern(_ attrStr: inout AttributedString,
                                     pattern: String,
                                     apply: (inout AttributeContainer) -> Void) {
        let plainText = String(attrStr.characters)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: plainText, range: NSRange(plainText.startIndex..., in: plainText))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: plainText),
                  let groupRange = Range(match.range(at: 1), in: plainText) else { continue }
            let innerText = String(plainText[groupRange])

            guard let attrFullRange = attrStr.range(of: String(plainText[fullRange])) else { continue }

            var container = AttributeContainer()
            apply(&container)
            let replacement = AttributedString(innerText, attributes: container)
            attrStr.replaceSubrange(attrFullRange, with: replacement)
        }
    }
}

// MARK: - ParsedIdentity

struct ParsedIdentity {
    var name: String = ""
    var creature: String = ""
    var vibe: String = ""
    var emoji: String = "🤖"
    var division: String = ""
}

// MARK: - PersonaViewModel

class PersonaViewModel: ObservableObject {
    enum FileType {
        case identity, soul, user, memory
    }

    let basePath: String

    @Published var identityContent = ""
    @Published var soulContent = ""
    @Published var userContent = ""
    @Published var memoryContent = ""

    // Track original content to detect changes
    private var identityOriginal = ""
    private var soulOriginal = ""
    private var userOriginal = ""
    private var memoryOriginal = ""

    var identityDirty: Bool { identityContent != identityOriginal }
    var soulDirty: Bool { soulContent != soulOriginal }
    var userDirty: Bool { userContent != userOriginal }
    var memoryDirty: Bool { memoryContent != memoryOriginal }

    var parsedIdentity: ParsedIdentity? {
        guard !identityContent.isEmpty else { return nil }
        return Self.parseIdentity(identityContent)
    }

    init(basePath: String) {
        self.basePath = basePath
    }

    func loadAll() {
        identityContent = readFile("IDENTITY.md")
        soulContent = readFile("SOUL.md")
        userContent = readFile("USER.md")
        memoryContent = readFile("MEMORY.md")
        identityOriginal = identityContent
        soulOriginal = soulContent
        userOriginal = userContent
        memoryOriginal = memoryContent
    }

    func save(file: FileType) {
        switch file {
        case .identity:
            writeFile("IDENTITY.md", content: identityContent)
            identityOriginal = identityContent
        case .soul:
            writeFile("SOUL.md", content: soulContent)
            soulOriginal = soulContent
        case .user:
            writeFile("USER.md", content: userContent)
            userOriginal = userContent
        case .memory:
            writeFile("MEMORY.md", content: memoryContent)
            memoryOriginal = memoryContent
        }
    }

    private func readFile(_ name: String) -> String {
        let path = (basePath as NSString).appendingPathComponent(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeFile(_ name: String, content: String) {
        let path = (basePath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func parseIdentity(_ content: String) -> ParsedIdentity {
        var identity = ParsedIdentity()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- **Name:**") {
                identity.name = trimmed.replacingOccurrences(of: "- **Name:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Creature:**") {
                identity.creature = trimmed.replacingOccurrences(of: "- **Creature:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Vibe:**") {
                identity.vibe = trimmed.replacingOccurrences(of: "- **Vibe:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Emoji:**") {
                let emoji = trimmed.replacingOccurrences(of: "- **Emoji:**", with: "").trimmingCharacters(in: .whitespaces)
                if !emoji.isEmpty { identity.emoji = emoji }
            } else if trimmed.hasPrefix("- **Division:**") {
                identity.division = trimmed.replacingOccurrences(of: "- **Division:**", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return identity
    }
}
