import Foundation
import Metal
import PhotorCore
import PhotorDecoders
import PhotorRendering

enum SmokeCheck {
    @MainActor static func run(folder: URL) async -> Bool {
        do {
            let assets = try FolderCatalog().scan(folder)
            guard !assets.isEmpty else { throw PhotoError.unreadable(folder.lastPathComponent) }
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.unavailable }
            print("GPU: \(device.name)")
            let budget = MemoryBudget(limit: 4 * 1_073_741_824)
            let textures = TextureCache(device: device, budget: budget)
            let renderer = try MetalRenderer(device: device)
            _ = renderer
            let decoder = DecoderRegistry()
            let executor = DecodeExecutor()
            for asset in assets {
                for representation: ImageRepresentation in [.screen(maxPixel: 3072), .full] {
                    let request = DecodeRequest(asset: asset, representation: representation)
                    let decoded = try await executor.decode(request, using: decoder, cancellation: CancellationFlag())
                    guard let lease = budget.reserve(decoded.byteCount, category: "Immagini") else { throw PhotoError.memory }
                    let cached = CachedImage(key: request.key, decoded: decoded, lease: lease)
                    let texture = try await textures.frame(for: cached)
                    guard texture.texture.width == decoded.image.width, texture.texture.height == decoded.image.height,
                          let data = decoded.image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { throw RenderingError.pixels }
                    let count = CFDataGetLength(data)
                    let hasPixel = stride(from: 0, to: count - 4, by: max(4, (count / 100 / 4) * 4)).contains {
                        bytes[$0] != 0 || bytes[$0 + 1] != 0 || bytes[$0 + 2] != 0
                    }
                    guard hasPixel else { throw PhotoError.decoding("Bitmap vuota: \(asset.name)") }
                    print("PASS \(asset.name) \(representation): \(decoded.image.width)x\(decoded.image.height), \(decoded.byteCount) bytes, \(Int(decoded.decodeMilliseconds)) ms, Metal texture ready")
                    await textures.clear()
                }
            }
            print("PASS decoder, pixel non vuoti, shader e upload Metal per \(assets.count) file")
            return true
        } catch { print("FAIL: \(error)"); return false }
    }
}
