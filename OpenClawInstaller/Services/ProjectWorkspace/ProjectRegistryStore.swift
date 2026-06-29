import Foundation

final class ProjectRegistryStore {
    struct Snapshot: Codable {
        var projects: [ProjectRecord]
        var bindings: [AgentProjectBinding]
    }

    private let registryURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.registryURL = appSupport
            .appendingPathComponent("GetClowHub", isDirectory: true)
            .appendingPathComponent("ProjectRegistry", isDirectory: true)
            .appendingPathComponent("projects.json")
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: registryURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    func save(projects: [ProjectRecord], bindings: [AgentProjectBinding]) throws {
        let snapshot = Snapshot(
            projects: projects.sorted { $0.sortKey < $1.sortKey },
            bindings: bindings
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: registryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: registryURL, options: .atomic)
    }
}
