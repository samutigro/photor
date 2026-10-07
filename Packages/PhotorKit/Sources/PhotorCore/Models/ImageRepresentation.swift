import Foundation

public enum ImageRepresentation: Hashable, Sendable {
    case screen(maxPixel: Int)
    case full
    public var isFull: Bool { if case .full = self { return true }; return false }
}

public struct CacheKey: Hashable, Sendable {
    public let photo: PhotoID
    public let revision: FileRevision
    public let representation: ImageRepresentation
    public init(asset: PhotoAsset, representation: ImageRepresentation) {
        photo = asset.id; revision = asset.revision; self.representation = representation
    }
}

public struct ViewerConfiguration: Sendable, Equatable {
    public var memoryLimit: Int
    public var prefetchRadius: Int
    public var fullResolutionRadius: Int
    public var screenMaxPixel: Int
    public var fillFolder: Bool
    public init(memoryLimit: Int = 16 * 1_073_741_824, prefetchRadius: Int = 100,
                fullResolutionRadius: Int = 5, screenMaxPixel: Int = 4096, fillFolder: Bool = true) {
        self.memoryLimit = memoryLimit; self.prefetchRadius = prefetchRadius
        self.fullResolutionRadius = fullResolutionRadius; self.screenMaxPixel = screenMaxPixel
        self.fillFolder = fillFolder
    }
}
