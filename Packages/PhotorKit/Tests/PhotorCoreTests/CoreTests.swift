import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PhotorCore
import PhotorDecoders

struct CoreTests {
    private func asset(_ n: Int, raw: Bool = false) -> PhotoAsset {
        PhotoAsset(url: URL(fileURLWithPath: "/photos/\(n).\(raw ? "RAF" : "JPG")"),
            revision: FileRevision(byteCount: 100, modifiedAt: .distantPast))
    }
    func memoryReservationsSurviveOwnerRemovalAndReleaseOnce() throws {
        let budget = MemoryBudget(limit: 100)
        var lease = budget.reserve(80, category: "test")
        try expect(lease != nil)
        try expect(budget.reserve(30, category: "test") == nil)
        let retained = lease
        lease = nil
        try expect(budget.snapshot.used == 80)
        retained?.release(); retained?.release()
        try expect(budget.snapshot.used == 0)
        try expect(budget.reserve(100, category: "test") != nil)
    }
    func plannerBoundsDirectionAndRAWLimit() throws {
        let photos = (0..<12).map { asset($0, raw: $0 == 9) }
        let config = ViewerConfiguration(prefetchRadius: 3, fullResolutionRadius: 5, fillFolder: false)
        let plan = PrefetchPlanner().plan(assets: photos, current: 6, direction: 1, configuration: config)
        try expect(plan.first?.request.asset.id == photos[6].id)
        try expect(!plan.first!.request.representation.isFull)
        let forward = plan.first { $0.request.asset.id == photos[7].id && !$0.request.representation.isFull }!
        let backward = plan.first { $0.request.asset.id == photos[5].id && !$0.request.representation.isFull }!
        try expect(forward.priority < backward.priority)
        try expect(!plan.contains { $0.request.asset.id == photos[9].id && $0.request.representation.isFull })
        try expect(!plan.contains { $0.request.asset.id == photos[0].id })
        try expect(PrefetchPlanner().plan(assets: [], current: 0, direction: 1, configuration: config).isEmpty)
    }
    func evictionPreservesCurrentAndNearerPhotos() throws {
        let budget = MemoryBudget(limit: 4096)
        let image = try sampleImage()
        var cache = ImageCache()
        let photos = (0..<3).map { asset($0) }
        let keys = photos.map { CacheKey(asset: $0, representation: .full) }
        for key in keys {
            let decoded = DecodedImage(image: image, sourceSize: PixelSize(width: 8, height: 4),
                isEmbeddedPreview: false, decodeMilliseconds: 0)
            cache.insert(CachedImage(key: key, decoded: decoded, lease: budget.reserve(decoded.byteCount, category: "test")!))
        }
        let evicted = cache.evictOne(protected: [photos[0].id], preferred: Set(photos.map(\.id)),
            priorities: [keys[0]: 0, keys[1]: 10, keys[2]: 100])
        try expect(evicted)
        try expect(cache.contains(keys[0])); try expect(cache.contains(keys[1])); try expect(!cache.contains(keys[2]))
        let displacedNearer = cache.evictOne(protected: [photos[0].id], preferred: [],
            priorities: [keys[1]: 10], incomingPriority: 500)
        try expect(!displacedNearer)
    }
    func catalogNaturalOrderAndOrientationAwareJPEGDecode() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try sampleImage()
        for name in ["image10.jpg", "image2.jpg", ".hidden.jpg"] {
            let url = directory.appendingPathComponent(name)
            let output = try require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(output, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
            try expect(CGImageDestinationFinalize(output))
        }
        try Data().write(to: directory.appendingPathComponent("ignored.txt"))
        let catalog = try FolderCatalog().scan(directory)
        try expect(catalog.map(\.name) == ["image2.jpg", "image10.jpg"])
        let decoded = try ImageIODecoder().decode(DecodeRequest(asset: catalog[0], representation: .full))
        try expect(decoded.image.width == 4); try expect(decoded.image.height == 8)
        try expect(decoded.sourceSize == PixelSize(width: 4, height: 8))
        try expect(decoded.image.bitsPerPixel == 32)
        try expect(decoded.image.colorSpace?.name == CGColorSpace.sRGB)
        let screen = try ImageIODecoder().decode(DecodeRequest(asset: catalog[0], representation: .screen(maxPixel: 4)))
        try expect(max(screen.image.width, screen.image.height) <= 4)
    }
    private func sampleImage() throws -> CGImage {
        let context = try require(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        return try require(context.makeImage())
    }
}
