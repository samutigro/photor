import Foundation
import CoreGraphics

public struct DecodeRequest: Sendable {
    public let asset: PhotoAsset
    public let representation: ImageRepresentation
    public init(asset: PhotoAsset, representation: ImageRepresentation) {
        self.asset = asset; self.representation = representation
    }
    public var key: CacheKey { CacheKey(asset: asset, representation: representation) }
}

// CGImage is immutable. No mutable pixel storage escapes a decoder.
public final class DecodedImage: @unchecked Sendable {
    public let image: CGImage
    public let sourceSize: PixelSize
    public let isEmbeddedPreview: Bool
    public let decodeMilliseconds: Double
    public var byteCount: Int { image.bytesPerRow * image.height }
    public init(image: CGImage, sourceSize: PixelSize, isEmbeddedPreview: Bool, decodeMilliseconds: Double) {
        self.image = image; self.sourceSize = sourceSize
        self.isEmbeddedPreview = isEmbeddedPreview; self.decodeMilliseconds = decodeMilliseconds
    }
}

public protocol PhotoDecoder: Sendable {
    func decode(_ request: DecodeRequest) throws -> DecodedImage
}

public enum PhotoError: Error, LocalizedError, Sendable, Equatable {
    case unreadable(String), decoding(String), memory, cancelled
    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Impossibile leggere \(name)."
        case .decoding(let name): "Impossibile decodificare \(name)."
        case .memory: "Memoria disponibile insufficiente: riduci la cache o chiudi altre applicazioni."
        case .cancelled: "Richiesta annullata."
        }
    }
}

public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.withLock { cancelled = true } }
    public var isCancelled: Bool { lock.withLock { cancelled } }
}
