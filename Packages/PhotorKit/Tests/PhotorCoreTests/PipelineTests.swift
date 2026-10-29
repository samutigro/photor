import Foundation
import CoreGraphics
@testable import PhotorCore

struct PipelineTests {
    func folderSwitchRejectsOldResultsAndLimitsWorkers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("first"), second = root.appendingPathComponent("second")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["1.jpg", "2.jpg"] { try Data([1]).write(to: folder.appendingPathComponent(name)) }
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let decoder = SlowDecoder()
        let config = ViewerConfiguration(memoryLimit: 2 * 1_073_741_824, prefetchRadius: 2, fullResolutionRadius: 1, screenMaxPixel: 64)
        let pipeline = PhotoPipeline(decoder: decoder, configuration: config, budget: MemoryBudget(limit: config.memoryLimit))
        let observer = Task { () -> (wrong: Int, shown: Int) in
            var newFolder = false, wrong = 0, shown = 0
            for await event in pipeline.events {
                switch event {
                case .catalog(_, let folder): if folder == second { newFolder = true }
                case .display(let frame, _):
                    if newFolder {
                        shown += 1
                        if !frame.key.photo.path.hasPrefix(second.path + "/") { wrong += 1 }
                    }
                case .status(let status): if newFolder && status.running == 0 && status.pending == 0 { return (wrong, shown) }
                default: break
                }
            }
            return (wrong, shown)
        }
        await pipeline.open(first)
        try await Task.sleep(for: .milliseconds(10))
        await pipeline.select(1)
        await pipeline.open(second)
        let result = await observer.value
        try expect(result.wrong == 0)
        try expect(result.shown > 0)
        try expect(decoder.maximumConcurrent <= 2)
        try expect(decoder.maximumConcurrent > 0)
        let status = await pipeline.snapshot()
        try expect(status.cachedPhotos == 2)
        try expect(status.running == 0)
    }
}

final class SlowDecoder: PhotoDecoder, @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0
    var maximumConcurrent: Int { lock.withLock { maximum } }
    func decode(_ request: DecodeRequest) throws -> DecodedImage {
        lock.withLock { active += 1; maximum = max(maximum, active) }
        defer { lock.withLock { active -= 1 } }
        Thread.sleep(forTimeInterval: 0.04)
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return DecodedImage(image: context.makeImage()!, sourceSize: PixelSize(width: 4, height: 4),
            isEmbeddedPreview: false, decodeMilliseconds: 40)
    }
}
