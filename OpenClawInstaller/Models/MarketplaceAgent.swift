import Foundation

// MARK: - MarketplaceAgent Model

struct MarketplaceAgent: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let division: String
    let description: String
    let vibe: String
    let color: String
    let content: String
    let specialty: String?
    let whenToUse: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MarketplaceAgent, rhs: MarketplaceAgent) -> Bool {
        lhs.id == rhs.id
    }

    func localizedDisplay(localeID: String) -> MarketplaceAgentDisplay {
        MarketplaceCatalog.shared.localizedDisplay(for: self, localeID: localeID)
    }
}

struct MarketplaceAgentDisplay: Hashable {
    let name: String
    let division: String
    let description: String
    let vibe: String
    let specialty: String?
    let whenToUse: String?
    let content: String
}

// MARK: - MarketplaceCatalog

class MarketplaceCatalog {
    static let shared = MarketplaceCatalog()

    let agents: [MarketplaceAgent]
    let divisions: [String]

    private init() {
        guard let url = Bundle.main.url(forResource: "marketplace_agents", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MarketplaceAgent].self, from: data) else {
            NSLog("[MarketplaceCatalog] Failed to load marketplace_agents.json")
            self.agents = []
            self.divisions = []
            return
        }
        self.agents = decoded
        self.divisions = Array(Set(decoded.map { $0.division })).sorted()
        NSLog("[MarketplaceCatalog] Loaded %d agents in %d divisions", decoded.count, self.divisions.count)
    }

    func localizedDisplay(for agent: MarketplaceAgent, localeID: String) -> MarketplaceAgentDisplay {
        let localization = I18n.agentDisplay(for: agent, localeID: localeID)
        return MarketplaceAgentDisplay(
            name: localization.name,
            division: localization.division,
            description: localization.description,
            vibe: localization.vibe,
            specialty: localization.specialty,
            whenToUse: localization.whenToUse,
            content: localization.content
        )
    }

    func localizedDivisionName(_ division: String, localeID: String) -> String {
        guard let agent = agents.first(where: { $0.division == division }) else { return division }
        return localizedDisplay(for: agent, localeID: localeID).division
    }

    func search(query: String, division: String? = nil, localeID: String = "en") -> [MarketplaceAgent] {
        var results = agents

        if let division = division, !division.isEmpty {
            results = results.filter { $0.division == division }
        }

        if !query.isEmpty {
            results = results.filter { agent in
                let display = localizedDisplay(for: agent, localeID: localeID)
                let searchableFields = [
                    display.name,
                    display.description,
                    display.vibe,
                    display.division,
                    display.specialty ?? "",
                    display.whenToUse ?? "",
                    agent.name,
                    agent.description,
                    agent.vibe,
                    agent.division,
                    agent.specialty ?? "",
                    agent.whenToUse ?? ""
                ]
                return searchableFields.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }

        return results
    }
}

// MARK: - MarketplaceContentConverter

struct MarketplaceContentConverter {

    // SOUL keywords — sections about persona, tone, boundaries
    private static let soulKeywords = ["identity", "communication", "style", "critical rule", "rules you must follow"]

    /// Split content by ## headings into SOUL (persona) vs AGENTS (operations) sections,
    /// following the official openclaw convert.sh logic.
    private static func splitContent(_ content: String) -> (soul: String, agents: String) {
        let lines = content.components(separatedBy: "\n")
        var soulParts: [String] = []
        var agentsParts: [String] = []
        var currentSection: [String] = []
        var currentTarget = "agents" // default bucket

        for line in lines {
            if line.hasPrefix("## ") {
                // Flush previous section
                if !currentSection.isEmpty {
                    let block = currentSection.joined(separator: "\n")
                    if currentTarget == "soul" {
                        soulParts.append(block)
                    } else {
                        agentsParts.append(block)
                    }
                    currentSection = []
                }

                // Classify by keyword
                let headerLower = line.lowercased()
                if soulKeywords.contains(where: { headerLower.contains($0) }) {
                    currentTarget = "soul"
                } else {
                    currentTarget = "agents"
                }
            }

            currentSection.append(line)
        }

        // Flush final section
        if !currentSection.isEmpty {
            let block = currentSection.joined(separator: "\n")
            if currentTarget == "soul" {
                soulParts.append(block)
            } else {
                agentsParts.append(block)
            }
        }

        return (soulParts.joined(separator: "\n\n"), agentsParts.joined(separator: "\n\n"))
    }

    /// IDENTITY.md — structured identity + specialty and description after ---
    static func identityMarkdown(for agent: MarketplaceAgent, localeID: String = "en") -> String {
        let display = agent.localizedDisplay(localeID: localeID)
        var afterSeparator = display.description
        if let specialty = display.specialty, !specialty.isEmpty {
            afterSeparator = "**Specialty:** \(specialty)\n\n\(display.description)"
        }
        return """
        # IDENTITY.md - Who Am I?

        - **Name:** \(display.name)
        - **Creature:** \(display.division) Specialist
        - **Vibe:** \(display.vibe)
        - **Division:** \(display.division)

        ---

        \(afterSeparator)
        """
    }

    /// SOUL.md — persona, tone, boundaries (extracted from content)
    static func soulMarkdown(for agent: MarketplaceAgent, localeID: String = "en") -> String {
        let display = agent.localizedDisplay(localeID: localeID)
        let (soul, _) = splitContent(display.content)
        return soul.isEmpty ? display.content : soul
    }

    /// AGENTS.md — mission, deliverables, workflow (extracted from content) + structured metadata
    static func agentsMarkdown(for agent: MarketplaceAgent, localeID: String = "en") -> String {
        let display = agent.localizedDisplay(localeID: localeID)
        let (_, agentsContent) = splitContent(display.content)

        var parts: [String] = []

        if !agentsContent.isEmpty {
            parts.append(agentsContent)
        }

        // Append structured metadata from README
        if let whenToUse = display.whenToUse, !whenToUse.isEmpty {
            parts.append("## When to Use\n\n\(whenToUse)")
        }
        if let specialty = display.specialty, !specialty.isEmpty {
            parts.append("## Specialty\n\n\(specialty)")
        }

        return parts.joined(separator: "\n\n")
    }

    /// Empty MEMORY.md template
    static func memoryMarkdown() -> String {
        "# MEMORY.md\n\n_Long-term memory for this agent._\n"
    }
}
