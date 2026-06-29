import Foundation
import os.log

/// Low-cost project index bootstrap.
///
/// This MVP intentionally writes only a manifest under Application Support.
/// It does not start file watchers, parser workers, language servers, ctags,
/// or a recursive file scan. Those can be layered behind this API later with
/// throttling and explicit performance guards.
final class SemanticRepoMapService {
    private let log = Logger(subsystem: "com.openclaw.installer", category: "SemanticRepoMapService")
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        self.baseDirectory = appSupport
            .appendingPathComponent("GetClowHub", isDirectory: true)
            .appendingPathComponent("ProjectIndexes", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func bootstrapProject(_ project: ProjectRecord) async {
        await Task.detached(priority: .utility) { [baseDirectory, encoder, log] in
            let manifestURL = Self.manifestURL(baseDirectory: baseDirectory, projectId: project.id)
            do {
                try FileManager.default.createDirectory(
                    at: manifestURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let manifest = RepoMapManifest(
                    projectId: project.id,
                    rootPath: project.rootPath,
                    displayName: project.displayName,
                    indexVersion: project.indexVersion,
                    status: .ready,
                    updatedAt: Date(),
                    note: "Application Support manifest only; semantic indexing is lazy and tool-driven."
                )
                let data = try encoder.encode(manifest)
                try data.write(to: manifestURL, options: .atomic)
            } catch {
                log.error("Failed to bootstrap project map \(project.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }

    func manifest(for projectId: String) -> RepoMapManifest? {
        let url = Self.manifestURL(baseDirectory: baseDirectory, projectId: projectId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RepoMapManifest.self, from: data)
    }

    private static func manifestURL(baseDirectory: URL, projectId: String) -> URL {
        baseDirectory
            .appendingPathComponent(projectId, isDirectory: true)
            .appendingPathComponent("manifest.json")
    }
}

struct RepoMapManifest: Codable, Equatable {
    let projectId: String
    let rootPath: String
    let displayName: String
    let indexVersion: Int
    let status: ProjectIndexStatus
    let updatedAt: Date
    let note: String
}
