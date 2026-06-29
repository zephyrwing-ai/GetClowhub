import Foundation

@main
struct VerifyAttachmentProcessorBudget {
    static func main() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("attachment-processor-budget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func makeFile(_ name: String, bytes: Int) throws -> URL {
            let url = root.appendingPathComponent(name)
            let data = Data(repeating: 0x2A, count: bytes)
            try data.write(to: url)
            return url
        }

        func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() {
                fputs("FAIL: \(message)\n", stderr)
                exit(1)
            }
        }

        let processor = AttachmentProcessor(
            imageMetadataReader: { url in
                switch url.lastPathComponent {
                case "huge-pixels.png":
                    return AttachmentProcessor.ImageMetadata(width: 5_000, height: 4_000)
                case let name where name.hasSuffix(".png") || name.hasSuffix(".jpg"):
                    return AttachmentProcessor.ImageMetadata(width: 1_000, height: 1_000)
                default:
                    return nil
                }
            }
        )

        let tinyImages = try (0..<5).map { try makeFile("tiny-\($0).png", bytes: 100 * 1024) }
        let tinyResult = processor.process(tinyImages)
        assert(tinyResult.inlineAttachments.count == 5, "five 100KB images should all be inline")
        assert(tinyResult.manifestText.contains("inline-image"), "manifest should label inline images")

        let oversizedImages = try (0..<5).map { try makeFile("oversized-\($0).png", bytes: 3 * 1024 * 1024) }
        let oversizedResult = processor.process(oversizedImages)
        assert(oversizedResult.inlineAttachments.isEmpty, "3MB images should exceed the per-image inline budget")
        assert(oversizedResult.manifestText.contains("image-path"), "oversized images should remain in manifest path mode")

        let partialImages = try (0..<6).map { try makeFile("partial-\($0).jpg", bytes: 1_500_000) }
        let partialResult = processor.process(partialImages)
        assert(partialResult.inlineAttachments.count > 0, "budget selection should inline eligible images before budget is exhausted")
        assert(partialResult.inlineAttachments.count < partialImages.count, "budget selection should leave remaining images in manifest")

        let hugePixels = try makeFile("huge-pixels.png", bytes: 1024 * 1024)
        let hugePixelsResult = processor.process([hugePixels])
        assert(hugePixelsResult.inlineAttachments.isEmpty, "20MP image should exceed the pixel budget")
        assert(hugePixelsResult.manifestText.contains("pixel budget"), "manifest should explain pixel-budget path mode")

        let pdf = try makeFile("large.pdf", bytes: 4 * 1024 * 1024)
        let txt = try makeFile("large.log", bytes: 4 * 1024 * 1024)
        let audio = try makeFile("clip.mp3", bytes: 512 * 1024)
        let video = try makeFile("clip.mp4", bytes: 512 * 1024)
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try makeFile("folder/hidden-child.txt", bytes: 16)

        let nonImageResult = processor.process([pdf, txt, audio, video, folder])
        assert(nonImageResult.inlineAttachments.isEmpty, "non-images and folders should never inline content")
        assert(nonImageResult.manifestText.contains("read selected pages"), "PDF manifest should suggest page-selective reading")
        assert(nonImageResult.manifestText.contains("read selected ranges"), "log/text manifest should suggest range-selective reading")
        assert(nonImageResult.manifestText.contains("transcribe/extract only if needed"), "media manifest should not eagerly transcribe")
        assert(nonImageResult.manifestText.contains("list/glob first"), "folder manifest should not recurse")
        assert(!nonImageResult.manifestText.contains("hidden-child.txt"), "folder manifest should not recursively enumerate children")

        let dashboardSource = try String(contentsOfFile: "OpenClawInstaller/ViewModels/DashboardViewModel.swift", encoding: .utf8)
        assert(dashboardSource.contains("AttachmentProcessor"), "DashboardViewModel should delegate attachment processing")
        assert(!dashboardSource.contains("maxInlineImageAttachmentCount"), "old count-based inline threshold should be removed")

        print("attachment processor budget checks passed")
    }
}
