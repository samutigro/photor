import Foundation
import Metal
import PhotorCore

public enum RenderingError: Error, LocalizedError {
    case unavailable, pixels, shader
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Metal non è disponibile. Avvia Photor sul desktop del Mac."
        case .pixels: "Impossibile preparare i pixel per lo schermo."
        case .shader: "Impossibile inizializzare il renderer Metal."
        }
    }
}

// Texture contents are immutable after upload; only Metal reads them thereafter.
public final class TextureFrame: @unchecked Sendable {
    public let key: CacheKey
    public let texture: any MTLTexture
    public let sourceSize: PixelSize
    public let embeddedPreview: Bool
    private let lease: MemoryLease
    init(key: CacheKey, texture: any MTLTexture, sourceSize: PixelSize, embeddedPreview: Bool, lease: MemoryLease) {
        self.key = key; self.texture = texture; self.sourceSize = sourceSize
        self.embeddedPreview = embeddedPreview; self.lease = lease
    }
}

public actor TextureCache {
    private let device: any MTLDevice
    private let budget: MemoryBudget
    private let uploads: OperationQueue
    private var entries: [CacheKey: (TextureFrame, UInt64)] = [:]
    private var pending: [CacheKey: Task<TextureFrame, Error>] = [:]
    private var tick: UInt64 = 0
    private var epoch: UInt64 = 0
    private var focus: PhotoID?

    public init(device: any MTLDevice, budget: MemoryBudget) {
        self.device = device; self.budget = budget
        uploads = OperationQueue(); uploads.name = "Photor.texture-upload"
        uploads.maxConcurrentOperationCount = 1; uploads.qualityOfService = .userInitiated
    }

    public func setFocus(_ id: PhotoID?) { focus = id }
    public func clear(keeping id: PhotoID? = nil) {
        epoch &+= 1
        entries = entries.filter { $0.key.photo == id }
    }
    public func frame(for image: CachedImage) async throws -> TextureFrame {
        tick &+= 1
        if let existing = entries[image.key]?.0 {
            entries[image.key] = (existing, tick); return existing
        }
        if let work = pending[image.key] { return try await work.value }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: image.decoded.image.width, height: image.decoded.image.height, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        let estimated = max(image.decoded.byteCount, device.heapTextureSizeAndAlign(descriptor: descriptor).size)
        while budget.snapshot.limit - budget.snapshot.used < estimated * 2, evictOne() {}
        guard let lease = budget.reserve(estimated, category: "Texture"),
              let staging = budget.reserve(image.decoded.byteCount, category: "Upload") else { throw PhotoError.memory }
        let device = self.device, uploads = self.uploads, requestEpoch = epoch
        let work = Task<TextureFrame, Error> {
            defer { staging.release() }
            return try await withCheckedThrowingContinuation { continuation in
                uploads.addOperation {
                    let result: Result<TextureFrame, Error> = autoreleasepool {
                        do {
                            let bitmap = image.decoded.image
                            guard let data = bitmap.dataProvider?.data,
                                  let pointer = CFDataGetBytePtr(data) else { throw RenderingError.pixels }
                            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                                width: bitmap.width, height: bitmap.height, mipmapped: false)
                            descriptor.usage = .shaderRead; descriptor.storageMode = .shared
                            guard let texture = device.makeTexture(descriptor: descriptor), texture.allocatedSize <= lease.bytes else {
                                throw PhotoError.memory
                            }
                            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                                withBytes: pointer, bytesPerRow: bitmap.bytesPerRow)
                            return .success(TextureFrame(key: image.key, texture: texture, sourceSize: image.decoded.sourceSize,
                                embeddedPreview: image.decoded.isEmbeddedPreview, lease: lease))
                        } catch { return .failure(error) }
                    }
                    continuation.resume(with: result)
                }
            }
        }
        pending[image.key] = work
        do {
            let result = try await work.value
            pending.removeValue(forKey: image.key)
            if requestEpoch == epoch {
                tick &+= 1; entries[image.key] = (result, tick)
                while entries.count > 8, evictOne() {}
            }
            return result
        } catch { pending.removeValue(forKey: image.key); throw error }
    }
    private func evictOne() -> Bool {
        guard let key = entries.filter({ $0.key.photo != focus }).min(by: { $0.value.1 < $1.value.1 })?.key else { return false }
        entries.removeValue(forKey: key); return true
    }
}
