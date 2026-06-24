import Foundation
import Combine

struct DesignSystemIndexEntry: Identifiable, Hashable {
    let id: String
    let displayName: String
    let category: String
    let aliases: [String]
    let keywords: [String]
    let relativePath: String
    let summary: String
}

struct DesignSystemWorkspaceSelection {
    let selectedBrands: [DesignSystemIndexEntry]
    let workspacePath: String
}

@MainActor
final class DesignSystemManager: ObservableObject {
    static let shared = DesignSystemManager()

    @Published private(set) var designSystems: [String: String] = [:]
    @Published private(set) var index: [DesignSystemIndexEntry] = []
    @Published private(set) var allBrands: [String] = []
    @Published var isLoading = false

    private let fileManager = FileManager.default
    private let maxInjectedBrands = 5

    private let categories: [String: [String]] = [
        "AI & LLM Platforms": [
            "claude", "cohere", "elevenLabs", "minimax", "mistralai", "ollama",
            "opencode-ai", "replicate", "runwayml", "together-ai", "voltagent", "xai"
        ],
        "Developer Tools": [
            "cursor", "expo", "lovable", "raycast", "superhuman", "vercel", "warp"
        ],
        "Backend & Database": [
            "clickhouse", "composio", "hashicorp", "mongodb", "posthog", "sanity", "sentry", "supabase"
        ],
        "Productivity & SaaS": [
            "cal-com", "intercom", "linear", "mintlify", "notion", "resend", "zapier"
        ],
        "Design Tools": [
            "airtable", "clay", "figma", "framer", "miro", "webflow"
        ],
        "Fintech & Crypto": [
            "binance", "coinbase", "kraken", "revolut", "stripe", "wise"
        ],
        "E-commerce": [
            "airbnb", "meta", "nike", "shopify"
        ],
        "Media & Tech": [
            "apple", "ibm", "nvidia", "pinterest", "playstation", "spacex", "spotify",
            "the-verge", "uber", "wired", "verge", "dribbble"
        ],
        "Automotive": [
            "bmw", "bugatti", "ferrari", "lamborghini", "renault", "tesla"
        ]
    ]

    private let displayNameMap: [String: String] = [
        "elevenLabs": "ElevenLabs",
        "mistralai": "Mistral AI",
        "opencode-ai": "OpenCode AI",
        "runwayml": "RunwayML",
        "together-ai": "Together AI",
        "voltagent": "VoltAgent",
        "xai": "xAI",
        "posthog": "PostHog",
        "cal-com": "Cal.com",
        "the-verge": "The Verge"
    ]

    private init() {
        loadDesignSystems()
    }

    /// Loads only a lightweight index. Full DESIGN.md bodies are read on demand.
    func loadDesignSystems() {
        isLoading = true
        defer { isLoading = false }

        guard let rootPath = designSystemsRootPath() else {
            NSLog("[DesignSystemManager] DesignSystems folder not found")
            index = []
            allBrands = []
            designSystems = [:]
            return
        }

        do {
            let brands = try fileManager.contentsOfDirectory(atPath: rootPath).filter { brand in
                var isDir: ObjCBool = false
                let brandPath = (rootPath as NSString).appendingPathComponent(brand)
                let designPath = (brandPath as NSString).appendingPathComponent("DESIGN.md")
                return fileManager.fileExists(atPath: brandPath, isDirectory: &isDir)
                    && isDir.boolValue
                    && fileManager.fileExists(atPath: designPath)
            }

            index = brands.sorted().map { brand in
                DesignSystemIndexEntry(
                    id: brand,
                    displayName: getBrandDisplayName(brand),
                    category: category(for: brand),
                    aliases: aliases(for: brand),
                    keywords: keywords(for: brand),
                    relativePath: "\(brand)/DESIGN.md",
                    summary: "\(getBrandDisplayName(brand)) design system reference"
                )
            }
            allBrands = index.map(\.id)
            designSystems = [:]
            NSLog("[DesignSystemManager] Indexed %d design systems", index.count)
        } catch {
            NSLog("[DesignSystemManager] Failed to index DesignSystems: %@", error.localizedDescription)
            index = []
            allBrands = []
            designSystems = [:]
        }
    }

    func getDesignSystem(forBrand brand: String) -> String? {
        if let cached = designSystems[brand] {
            return cached
        }
        return readDesignSystem(forBrand: brand)
    }

    func getAllBrands() -> [String] {
        allBrands
    }

    func getBrandDisplayName(_ brand: String) -> String {
        if let displayName = displayNameMap[brand] {
            return displayName
        }
        return brand
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    func getBrandsByCategory() -> [String: [String]] {
        var result: [String: [String]] = [:]
        let available = Set(allBrands)
        for (category, brands) in categories {
            let filtered = brands.filter { available.contains($0) }
            if !filtered.isEmpty {
                result[category] = filtered
            }
        }
        return result
    }

    @discardableResult
    func prepareWorkspace(at workspace: String, taskContext: String? = nil) -> DesignSystemWorkspaceSelection {
        loadDesignSystemsIfNeeded()

        let selected = selectBrands(for: taskContext).prefix(maxInjectedBrands)
        let selectedEntries = Array(selected)
        let legacyFullCopyDir = (workspace as NSString).appendingPathComponent("DesignSystems")
        let referencesDir = (workspace as NSString).appendingPathComponent("DesignSystemReferences")
        try? fileManager.removeItem(atPath: legacyFullCopyDir)
        try? fileManager.removeItem(atPath: referencesDir)
        try? fileManager.createDirectory(atPath: referencesDir, withIntermediateDirectories: true)

        for entry in selectedEntries {
            guard let content = readDesignSystem(forBrand: entry.id) else { continue }
            let filePath = (referencesDir as NSString).appendingPathComponent("\(entry.id)-DESIGN.md")
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
        }

        writeIndexFile(to: workspace)
        writeSelectionFile(to: workspace, selected: selectedEntries, taskContext: taskContext)

        NSLog("[DesignSystemManager] Prepared workspace with %d selected design systems", selectedEntries.count)
        return DesignSystemWorkspaceSelection(selectedBrands: selectedEntries, workspacePath: workspace)
    }

    private func loadDesignSystemsIfNeeded() {
        if index.isEmpty {
            loadDesignSystems()
        }
    }

    private func designSystemsRootPath() -> String? {
        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append((resourcePath as NSString).appendingPathComponent("DesignSystems"))
        }

        let bundlePath = Bundle.main.bundlePath
        candidates.append((bundlePath as NSString).appendingPathComponent("Contents/Resources/DesignSystems"))

        if let exePath = Bundle.main.executablePath {
            let macosDir = (exePath as NSString).deletingLastPathComponent
            let contentsDir = (macosDir as NSString).deletingLastPathComponent
            candidates.append(((contentsDir as NSString).appendingPathComponent("Resources") as NSString).appendingPathComponent("DesignSystems"))
        }

        candidates.append((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("DesignSystems"))

        return candidates.first { path in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private func readDesignSystem(forBrand brand: String) -> String? {
        guard let rootPath = designSystemsRootPath() else { return nil }
        let path = ((rootPath as NSString).appendingPathComponent(brand) as NSString).appendingPathComponent("DESIGN.md")
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        designSystems[brand] = content
        return content
    }

    private func selectBrands(for taskContext: String?) -> [DesignSystemIndexEntry] {
        let text = (taskContext ?? "").lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let scored = index.compactMap { entry -> (DesignSystemIndexEntry, Int)? in
            let score = score(entry: entry, text: text)
            return score > 0 ? (entry, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.displayName < rhs.0.displayName }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    private func score(entry: DesignSystemIndexEntry, text: String) -> Int {
        var score = 0
        for alias in entry.aliases {
            let normalized = alias.lowercased()
            if text.contains(normalized) {
                score += normalized == entry.id.lowercased() ? 10 : 6
            }
        }
        for keyword in entry.keywords where text.contains(keyword.lowercased()) {
            score += 2
        }
        return score
    }

    private func writeIndexFile(to workspace: String) {
        let grouped = Dictionary(grouping: index, by: \.category)
        var lines = [
            "# DESIGN_SYSTEMS_INDEX.md",
            "",
            "Design system references are available on demand. Do not assume every full document is present in the workspace.",
            "Use files in DesignSystemReferences/ when they exist; otherwise ask for or infer the most relevant brand before applying a design system.",
            ""
        ]

        for category in grouped.keys.sorted() {
            lines.append("## \(category)")
            for entry in (grouped[category] ?? []).sorted(by: { $0.displayName < $1.displayName }) {
                lines.append("- \(entry.displayName) (`\(entry.id)`) - \(entry.relativePath)")
            }
            lines.append("")
        }

        let path = (workspace as NSString).appendingPathComponent("DESIGN_SYSTEMS_INDEX.md")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func writeSelectionFile(to workspace: String, selected: [DesignSystemIndexEntry], taskContext: String?) {
        var lines = [
            "# DESIGN_SYSTEMS_SELECTION.md",
            "",
            "Selected references are intentionally limited to reduce context noise.",
            ""
        ]

        if selected.isEmpty {
            lines.append("No specific brand was selected from the task text. Use DESIGN_SYSTEMS_INDEX.md to identify relevant brands before requesting or applying detailed references.")
        } else {
            lines.append("## Selected Brands")
            for entry in selected {
                lines.append("- \(entry.displayName) (`\(entry.id)`) -> DesignSystemReferences/\(entry.id)-DESIGN.md")
            }
        }

        if let taskContext, !taskContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("## Selection Context")
            lines.append(String(taskContext.prefix(2000)))
        }

        let path = (workspace as NSString).appendingPathComponent("DESIGN_SYSTEMS_SELECTION.md")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func category(for brand: String) -> String {
        categories.first { $0.value.contains(brand) }?.key ?? "Other"
    }

    private func aliases(for brand: String) -> [String] {
        let display = getBrandDisplayName(brand)
        let normalizedDisplay = display.lowercased()
        let base = brand.replacingOccurrences(of: "-", with: " ")
        return Array(Set([brand, base, display, normalizedDisplay]))
    }

    private func keywords(for brand: String) -> [String] {
        [brand, getBrandDisplayName(brand), category(for: brand)]
    }
}
