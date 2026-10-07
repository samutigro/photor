import Foundation
import CoreGraphics
import ImageIO
import PhotorCore

public struct ImageIODecoder: PhotoDecoder {
    public init() {}
    public func decode(_ request: DecodeRequest) throws -> DecodedImage {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let source = CGImageSourceCreateWithURL(request.asset.url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { throw PhotoError.unreadable(request.asset.name) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard width > 0, height > 0 else { throw PhotoError.decoding(request.asset.name) }
        let sourceSize = PixelSize(width: orientation >= 5 ? height : width, height: orientation >= 5 ? width : height)
        let maxPixel: Int
        switch request.representation {
        case .screen(let size): maxPixel = min(size, max(width, height))
        case .full: maxPixel = max(width, height)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw PhotoError.decoding(request.asset.name) }
        let pixels = try PixelNormalizer.bgra(image)
        return DecodedImage(image: pixels, sourceSize: sourceSize, isEmbeddedPreview: false,
            decodeMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}

enum PixelNormalizer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static func bgra(_ image: CGImage) throws -> CGImage {
        let flags = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: flags) else { throw PhotoError.memory }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = context.makeImage() else { throw PhotoError.memory }
        return result
    }
}
