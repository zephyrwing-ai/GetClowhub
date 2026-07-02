import SwiftUI

enum MarketplacePageLayout {
    static let contentMaxWidth: CGFloat = 760
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 34
    static let bottomPadding: CGFloat = 44
}

struct MarketplaceOverviewView: View {
    let selectedAgent: MarketplaceAgent?
    let installRefreshID: Int
    let onSelect: (MarketplaceAgent) -> Void

    @EnvironmentObject var languageManager: LanguageManager
    @State private var searchText = ""

    private static let divisionEmoji: [String: String] = [
        "Academic": "🎓",
        "Design": "🎨",
        "Engineering": "⚙️",
        "Game Development": "🎮",
        "Marketing": "📣",
        "Paid Media": "💰",
        "Product": "📦",
        "Project Management": "📋",
        "Sales": "🤝",
        "Spatial Computing": "🥽",
        "Specialized": "⭐",
        "Support": "🛟",
        "Testing": "🧪",
    ]

    private var groupedAgents: [(division: String, agents: [MarketplaceAgent])] {
        let catalog = MarketplaceCatalog.shared
        let localeID = languageManager.currentLocale.identifier
        if searchText.isEmpty {
            return catalog.divisions.compactMap { div in
                let agents = catalog.search(query: "", division: div, localeID: localeID)
                guard !agents.isEmpty else { return nil }
                return (division: div, agents: agents)
            }
        } else {
            let filtered = catalog.search(query: searchText, localeID: localeID)
            guard !filtered.isEmpty else { return [] }
            // Group search results by division
            let grouped = Dictionary(grouping: filtered) { $0.division }
            return catalog.divisions.compactMap { div in
                guard let agents = grouped[div], !agents.isEmpty else { return nil }
                return (division: div, agents: agents)
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            UnifiedSearchField(
                placeholder: I18n.t("agents.search.placeholder"),
                text: $searchText
            )

            // Content
            SmoothScrollView {
                if groupedAgents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(I18n.t("agents.empty.noMatching"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(60)
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedAgents, id: \.division) { group in
                            divisionSection(group)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: MarketplacePageLayout.contentMaxWidth, alignment: .leading)
        .padding(.horizontal, MarketplacePageLayout.horizontalPadding)
        .padding(.top, MarketplacePageLayout.topPadding)
        .padding(.bottom, MarketplacePageLayout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Division Section

    private func divisionSection(_ group: (division: String, agents: [MarketplaceAgent])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Text(Self.divisionEmoji[group.division] ?? "📁")
                    .font(.system(size: 16))
                Text(MarketplaceCatalog.shared.localizedDivisionName(group.division, localeID: languageManager.currentLocale.identifier))
                    .font(.system(size: 15, weight: .semibold))
                Text("(\(group.agents.count))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.leading, 4)

            // Agent cards grid
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.agents) { agent in
                    AgentCard(
                        agent: agent,
                        isSelected: selectedAgent?.id == agent.id,
                        installRefreshID: installRefreshID,
                        onSelect: onSelect
                    )
                }
            }
        }
    }
}

// MARK: - Agent Card

private struct AgentCard: View {
    let agent: MarketplaceAgent
    let isSelected: Bool
    let installRefreshID: Int
    let onSelect: (MarketplaceAgent) -> Void

    @State private var isHovering = false
    @State private var isInstalled = false
    @EnvironmentObject var languageManager: LanguageManager

    private var display: MarketplaceAgentDisplay {
        agent.localizedDisplay(localeID: languageManager.currentLocale.identifier)
    }

    var body: some View {
        Button {
            onSelect(agent)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Top: avatar + name + status
                HStack(spacing: 8) {
                    AgentAvatarImage(size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(display.division)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    if isInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                }

                // Description
                Text(display.description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected || isHovering
                          ? Color(nsColor: .controlBackgroundColor)
                          : Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectionStrokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            checkInstalled()
        }
        .onChange(of: installRefreshID) { _ in
            checkInstalled()
        }
    }

    private var selectionStrokeColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.72)
        }
        if isHovering {
            return Color.accentColor.opacity(0.5)
        }
        return Color.gray.opacity(0.2)
    }

    private func checkInstalled() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let agentId = agent.id
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let agentDir = "\(homeDir)/.openclaw/agents/\(agentId)/agent"
        isInstalled = FileManager.default.fileExists(atPath: agentDir)
    }
}
