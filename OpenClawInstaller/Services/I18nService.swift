import Foundation

struct I18nAgentDisplay: Hashable {
    let name: String
    let division: String
    let description: String
    let vibe: String
    let specialty: String?
    let whenToUse: String?
    let content: String
}

struct I18nSkillDisplay: Hashable {
    let displayName: String
    let description: String
    let content: String
}

struct I18nPluginDisplay: Hashable {
    let displayName: String
    let description: String
    let longDescription: String
    let category: String
    let capabilities: [String]
}

enum I18n {
    private static let namespaces = ["common", "settings", "agents", "skills", "plugins"]
    private static let resourceCache = I18nResourceCache()

    @MainActor
    static func t(_ key: String, fallback: String? = nil) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: [])
    }

    @MainActor
    static func format(_ key: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: arguments)
    }

    @MainActor
    static func markdown(_ key: String, fallback: String) -> String {
        localizedString(key, localeID: LanguageManager.shared.currentLocale.identifier, fallback: fallback, arguments: [])
    }

    static func string(_ key: String, localeID: String, fallback: String? = nil, _ arguments: CVarArg...) -> String {
        localizedString(key, localeID: localeID, fallback: fallback, arguments: arguments)
    }

    static func markdown(_ key: String, localeID: String, fallback: String) -> String {
        localizedString(key, localeID: localeID, fallback: fallback, arguments: [])
    }

    static func agentDisplay(for agent: MarketplaceAgent, localeID: String) -> I18nAgentDisplay {
        let prefix = "agents.\(slug(agent.id))"
        return I18nAgentDisplay(
            name: string("\(prefix).name", localeID: localeID, fallback: agent.name),
            division: string("\(prefix).division", localeID: localeID, fallback: agent.division),
            description: string("\(prefix).description", localeID: localeID, fallback: agent.description),
            vibe: string("\(prefix).vibe", localeID: localeID, fallback: agent.vibe),
            specialty: optionalString("\(prefix).specialty", localeID: localeID, fallback: agent.specialty),
            whenToUse: optionalString("\(prefix).whenToUse", localeID: localeID, fallback: agent.whenToUse),
            content: markdown("\(prefix).content", localeID: localeID, fallback: agent.content)
        )
    }

    @MainActor
    static func skillDisplay(for item: SkillCatalogItem) -> I18nSkillDisplay {
        skillDisplay(for: item, localeID: LanguageManager.shared.currentLocale.identifier)
    }

    static func skillDisplay(for item: SkillCatalogItem, localeID: String) -> I18nSkillDisplay {
        let prefix = "skills.catalog.\(slug(item.name))"
        return I18nSkillDisplay(
            displayName: string("\(prefix).displayName", localeID: localeID, fallback: item.displayName),
            description: string("\(prefix).description", localeID: localeID, fallback: item.description),
            content: markdown("\(prefix).content", localeID: localeID, fallback: item.documentationMarkdown)
        )
    }

    @MainActor
    static func pluginDisplay(for item: PluginCatalogItem) -> I18nPluginDisplay {
        pluginDisplay(for: item, localeID: LanguageManager.shared.currentLocale.identifier)
    }

    static func pluginDisplay(for item: PluginCatalogItem, localeID: String) -> I18nPluginDisplay {
        let prefix = "plugins.catalog.\(slug(item.name))"
        let capabilities = item.capabilities.enumerated().map { index, capability in
            string("\(prefix).capabilities.\(index)", localeID: localeID, fallback: capability)
        }
        return I18nPluginDisplay(
            displayName: string("\(prefix).displayName", localeID: localeID, fallback: item.displayName),
            description: string("\(prefix).description", localeID: localeID, fallback: item.description),
            longDescription: markdown("\(prefix).longDescription", localeID: localeID, fallback: item.longDescription),
            category: string("\(prefix).category", localeID: localeID, fallback: item.category),
            capabilities: capabilities
        )
    }

    static func localizedSearchFields(_ localized: [String], originals: [String]) -> [String] {
        var seen = Set<String>()
        return (localized + originals).filter { value in
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    static func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var result = ""
        var previousWasSeparator = true

        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append(".")
                previousWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: ".")).nilIfBlank ?? "item"
    }

    static func localeCandidates(for localeID: String) -> [String] {
        let normalized = localeID.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return ["en"] }

        var candidates: [String] = [normalized]
        if parts.count >= 2 {
            candidates.append("\(parts[0])-\(parts[1])")
        }
        if language == "zh" {
            let tags = Set(parts.dropFirst().map { $0.lowercased() })
            candidates.append(tags.contains("hant") || tags.contains("tw") || tags.contains("hk") || tags.contains("mo") ? "zh-Hant" : "zh-Hans")
        }
        if language == "pt" {
            candidates.append("pt-BR")
        }
        candidates.append(language)
        candidates.append("en")

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func optionalString(_ key: String, localeID: String, fallback: String?) -> String? {
        let value = localizedString(key, localeID: localeID, fallback: fallback, arguments: [])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func localizedString(_ key: String, localeID: String, fallback: String?, arguments: [CVarArg]) -> String {
        let template = resourceCache.value(for: key, localeID: localeID, namespaces: namespaces) ?? fallback ?? key
        guard !arguments.isEmpty else { return template }
        return String(format: template, arguments: arguments)
    }
}

private final class I18nResourceCache {
    private var cache: [String: [String: String]] = [:]
    private let lock = NSLock()

    func value(for key: String, localeID: String, namespaces: [String]) -> String? {
        for locale in I18n.localeCandidates(for: localeID) {
            for namespace in namespaces {
                if let value = resources(languageID: locale, namespace: namespace)[key],
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func resources(languageID: String, namespace: String) -> [String: String] {
        let cacheKey = "\(languageID)/\(namespace)"
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let loaded = loadResources(languageID: languageID, namespace: namespace)

        lock.lock()
        cache[cacheKey] = loaded
        lock.unlock()
        return loaded
    }

    private func loadResources(languageID: String, namespace: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: namespace, withExtension: "json", subdirectory: "I18n/\(languageID)"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
