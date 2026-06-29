import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AttachmentInlineBudget {
    var maxSingleImageBytes: Int64 = 2 * 1024 * 1024
    var maxTotalInlineImageBytes: Int64 = 8 * 1024 * 1024
    var maxSingleImagePixels: Int64 = 12_000_000
    var maxTotalInlineImagePixels: Int64 = 24_000_000
    var maxEstimatedJSONBytes: Int64 = 12 * 1024 * 1024
    var estimatedJSONOverheadPerInlineImage: Int64 = 768
}

struct AttachmentProcessor {
    struct ImageMetadata {
        let width: Int
        let height: Int

        var pixels: Int64 {
            Int64(width) * Int64(height)
        }
    }

    struct Result {
        let inlineAttachments: [[String: Any]]
        let manifestText: String
    }

    typealias ImageMetadataReader = (URL) -> ImageMetadata?

    private struct ManifestItem {
        let kind: String
        let url: URL
        let fileName: String
        let fileExtension: String
        let uti: String
        let size: Int64?
        let isDirectory: Bool
        let handling: String
        let reason: String?
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp"]

    private let budget: AttachmentInlineBudget
    private let fileManager: FileManager
    private let imageMetadataReader: ImageMetadataReader

    init(
        budget: AttachmentInlineBudget = AttachmentInlineBudget(),
        fileManager: FileManager = .default,
        imageMetadataReader: @escaping ImageMetadataReader = AttachmentProcessor.readImageMetadata
    ) {
        self.budget = budget
        self.fileManager = fileManager
        self.imageMetadataReader = imageMetadataReader
    }

    func process(_ urls: [URL]) -> Result {
        var inlineAttachments: [[String: Any]] = []
        var manifestItems: [ManifestItem] = []
        var totalInlineImageBytes: Int64 = 0
        var totalInlineImagePixels: Int64 = 0
        var totalEstimatedJSONBytes: Int64 = 0

        for url in urls {
            let isDirectory = isDirectory(url)
            let ext = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent
            let uti = contentTypeIdentifier(for: url, isDirectory: isDirectory)
            let size = fileSize(at: url)

            if isDirectory {
                manifestItems.append(
                    manifestItem(
                        kind: "folder",
                        url: url,
                        fileName: fileName,
                        ext: ext,
                        uti: uti,
                        size: size,
                        isDirectory: true,
                        handling: "list/glob first; do not recurse or read recursively wholesale",
                        reason: nil
                    )
                )
                continue
            }

            if Self.imageExtensions.contains(ext) {
                let metadata = imageMetadataReader(url)
                let decision = inlineDecision(
                    size: size,
                    metadata: metadata,
                    currentTotalBytes: totalInlineImageBytes,
                    currentTotalPixels: totalInlineImagePixels,
                    currentEstimatedJSONBytes: totalEstimatedJSONBytes
                )

                if decision.canInline,
                   let size,
                   let metadata,
                   let data = try? Data(contentsOf: url) {
                    let base64 = data.base64EncodedString()
                    inlineAttachments.append([
                        "type": "image",
                        "mimeType": mimeType(forImageExtension: ext),
                        "content": base64
                    ])
                    totalInlineImageBytes += size
                    totalInlineImagePixels += metadata.pixels
                    totalEstimatedJSONBytes += estimatedJSONBytes(forRawBytes: size)
                    manifestItems.append(
                        manifestItem(
                            kind: "inline-image",
                            url: url,
                            fileName: fileName,
                            ext: ext,
                            uti: uti,
                            size: size,
                            isDirectory: false,
                            handling: "small image inlined for the current request; keep path for later reference",
                            reason: nil
                        )
                    )
                } else {
                    manifestItems.append(
                        manifestItem(
                            kind: "image-path",
                            url: url,
                            fileName: fileName,
                            ext: ext,
                            uti: uti,
                            size: size,
                            isDirectory: false,
                            handling: "inspect image metadata or read the local image only if needed",
                            reason: decision.reason ?? "read failed; using path mode"
                        )
                    )
                }
                continue
            }

            manifestItems.append(
                manifestItem(
                    kind: "file",
                    url: url,
                    fileName: fileName,
                    ext: ext,
                    uti: uti,
                    size: size,
                    isDirectory: false,
                    handling: suggestedHandling(forExtension: ext, uti: uti),
                    reason: nil
                )
            )
        }

        return Result(
            inlineAttachments: inlineAttachments,
            manifestText: Self.renderManifest(manifestItems)
        )
    }

    private func inlineDecision(
        size: Int64?,
        metadata: ImageMetadata?,
        currentTotalBytes: Int64,
        currentTotalPixels: Int64,
        currentEstimatedJSONBytes: Int64
    ) -> (canInline: Bool, reason: String?) {
        guard let size else {
            return (false, "file size unavailable")
        }
        guard size <= budget.maxSingleImageBytes else {
            return (false, "single image byte budget exceeded")
        }
        guard let metadata else {
            return (false, "image metadata unavailable")
        }
        guard metadata.pixels <= budget.maxSingleImagePixels else {
            return (false, "single image pixel budget exceeded")
        }
        guard currentTotalBytes + size <= budget.maxTotalInlineImageBytes else {
            return (false, "total inline byte budget exceeded")
        }
        guard currentTotalPixels + metadata.pixels <= budget.maxTotalInlineImagePixels else {
            return (false, "total inline pixel budget exceeded")
        }
        let nextEstimatedJSONBytes = currentEstimatedJSONBytes + estimatedJSONBytes(forRawBytes: size)
        guard nextEstimatedJSONBytes <= budget.maxEstimatedJSONBytes else {
            return (false, "estimated WebSocket JSON budget exceeded")
        }
        return (true, nil)
    }

    private func estimatedJSONBytes(forRawBytes bytes: Int64) -> Int64 {
        let base64Bytes = ((bytes + 2) / 3) * 4
        return base64Bytes + budget.estimatedJSONOverheadPerInlineImage
    }

    private func manifestItem(
        kind: String,
        url: URL,
        fileName: String,
        ext: String,
        uti: String,
        size: Int64?,
        isDirectory: Bool,
        handling: String,
        reason: String?
    ) -> ManifestItem {
        ManifestItem(
            kind: kind,
            url: url,
            fileName: fileName,
            fileExtension: ext.isEmpty ? "(none)" : ext,
            uti: uti,
            size: size,
            isDirectory: isDirectory,
            handling: handling,
            reason: reason
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    private func contentTypeIdentifier(for url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            return UTType.folder.identifier
        }
        if let resourceType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return resourceType.identifier
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.identifier
        }
        return "public.data"
    }

    private func mimeType(forImageExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }

    private func suggestedHandling(forExtension ext: String, uti: String) -> String {
        switch ext {
        case "pdf":
            return "inspect page count/metadata first; read selected pages only"
        case "doc", "docx", "ppt", "pptx", "xls", "xlsx":
            return "inspect document structure first; read selected sections, slides, or sheets only"
        case "csv", "json", "log", "txt", "md":
            return "inspect size/head/schema first; read selected ranges only"
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "mp4", "mov", "m4v", "avi", "mkv", "webm":
            return "transcribe/extract only if needed; do not process media eagerly"
        default:
            if uti.hasPrefix("public.audio") || uti.hasPrefix("public.movie") || uti.hasPrefix("public.video") {
                return "transcribe/extract only if needed; do not process media eagerly"
            }
            return "inspect metadata first; read selectively only if needed"
        }
    }

    nonisolated private static func renderManifest(_ items: [ManifestItem]) -> String {
        guard !items.isEmpty else { return "" }

        var lines: [String] = [
            "Attachment manifest:",
            "These local attachments are provided by path/metadata. Do not read large files or folders wholesale; inspect metadata, list directories, or read selected pages/sections/ranges only.",
            "Small images may be inlined only for the current request. Persisted context should keep paths/placeholders instead of replaying base64."
        ]

        for item in items {
            lines.append("- kind: \(item.kind)")
            lines.append("  path: \(item.url.path)")
            lines.append("  filename: \(item.fileName)")
            lines.append("  extension: \(item.fileExtension)")
            lines.append("  uti: \(item.uti)")
            lines.append("  size_bytes: \(item.size.map(String.init) ?? "unknown")")
            lines.append("  is_directory: \(item.isDirectory)")
            lines.append("  suggested_handling: \(item.handling)")
            if let reason = item.reason {
                lines.append("  path_mode_reason: \(reason)")
            }
        }

        return "\n\n" + lines.joined(separator: "\n")
    }

    nonisolated private static func readImageMetadata(_ url: URL) -> ImageMetadata? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            return nil
        }

        guard let width = numericProperty(properties[kCGImagePropertyPixelWidth]),
              let height = numericProperty(properties[kCGImagePropertyPixelHeight]),
              width > 0,
              height > 0 else {
            return nil
        }

        return ImageMetadata(width: width, height: height)
    }

    nonisolated private static func numericProperty(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let int as Int:
            return int
        case let double as Double:
            return Int(double)
        default:
            return nil
        }
    }
}
