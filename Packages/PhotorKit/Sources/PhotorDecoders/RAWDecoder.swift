import Foundation
import CoreImage
import CoreGraphics
import ImageIO
import PhotorCore

// CIContext is documented as shareable across threads; each mutable CIRAWFilter is local to one job.
public final class RAWDecoder: PhotoDecoder, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}
    public func decode(_ request: DecodeRequest) throws -> DecodedImage {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let source = CGImageSourceCreateWithURL(request.asset.url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { throw PhotoError.unreadable(request.asset.name) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let native = PixelSize(width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height)
        if case .screen(let maxPixel) = request.representation,
           let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
           ] as CFDictionary) {
            return DecodedImage(image: try PixelNormalizer.bgra(preview), sourceSize: native,
                isEmbeddedPreview: true, decodeMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        guard let filter = CIRAWFilter(imageURL: request.asset.url) else { throw PhotoError.decoding(request.asset.name) }
        if case .screen(let maxPixel) = request.representation {
            filter.scaleFactor = min(1, Float(maxPixel) / Float(max(filter.nativeSize.width, filter.nativeSize.height)))
        }
        guard let output = filter.outputImage,
              let image = context.createCGImage(output, from: output.extent, format: .RGBA8,
                colorSpace: PixelNormalizer.colorSpace) else { throw PhotoError.decoding(request.asset.name) }
        return DecodedImage(image: try PixelNormalizer.bgra(image), sourceSize: native,
            isEmbeddedPreview: false, decodeMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
