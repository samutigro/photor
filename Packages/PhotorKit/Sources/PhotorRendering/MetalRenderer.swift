import AppKit
import MetalKit
import PhotorCore

@MainActor
public final class MetalRenderer: NSObject, MTKViewDelegate {
    public let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    public var frame: TextureFrame?
    public var viewport = ViewportState()
    public var onZoomChanged: ((Double) -> Void)?
    public private(set) var lastPresentedKey: CacheKey?
    private struct Vertex { var position: SIMD2<Float>; var uv: SIMD2<Float> }

    public init(device: any MTLDevice) throws {
        self.device = device
        let packagedResources = Bundle.main.resourceURL?.appendingPathComponent("PhotorKit_PhotorRendering.bundle")
        let resources = packagedResources.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let queue = device.makeCommandQueue(),
              let url = resources.url(forResource: "PhotoShaders", withExtension: "metal") else { throw RenderingError.shader }
        self.queue = queue
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "photoVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "photoFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.needsDisplay = true }
    public func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        if let frame {
            encode(frame, size: view.drawableSize, bounds: view.bounds.size, using: encoder)
            // Retain the texture and its memory lease until the GPU has finished reading it.
            buffer.addCompletedHandler { [weak self] command in
                if command.status == .completed {
                    Task { @MainActor [weak self] in self?.lastPresentedKey = frame.key }
                }
                withExtendedLifetime(frame) {}
            }
        }
        encoder.endEncoding(); buffer.present(drawable); buffer.commit()
    }

    private func encode(_ frame: TextureFrame, size: CGSize, bounds: CGSize, using encoder: any MTLRenderCommandEncoder) {
        let fit = min(size.width / CGFloat(frame.texture.width), size.height / CGFloat(frame.texture.height))
        let sx = Float(CGFloat(frame.texture.width) * fit * viewport.zoom / max(1, size.width))
        let sy = Float(CGFloat(frame.texture.height) * fit * viewport.zoom / max(1, size.height))
        let ox = Float(viewport.offset.x * 2 / max(1, bounds.width))
        let oy = Float(viewport.offset.y * 2 / max(1, bounds.height))
        let vertices: [Vertex] = [
            Vertex(position: [-sx + ox, sy + oy], uv: [0, 0]),
            Vertex(position: [-sx + ox, -sy + oy], uv: [0, 1]),
            Vertex(position: [sx + ox, -sy + oy], uv: [1, 1]),
            Vertex(position: [-sx + ox, sy + oy], uv: [0, 0]),
            Vertex(position: [sx + ox, -sy + oy], uv: [1, 1]),
            Vertex(position: [sx + ox, sy + oy], uv: [1, 0])
        ]
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(vertices, length: MemoryLayout<Vertex>.stride * vertices.count, index: 0)
        encoder.setFragmentTexture(frame.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    // Diagnostic rendering uses exactly the same shader and vertices as the onscreen view.
    public func snapshot(width: Int = 1200, height: Int = 800) throws -> CGImage {
        guard let frame else { throw RenderingError.pixels }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { throw RenderingError.pixels }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.008, 0.008, 0.01, 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { throw RenderingError.pixels }
        encode(frame, size: CGSize(width: width, height: height), bounds: CGSize(width: width, height: height), using: encoder)
        encoder.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
        guard buffer.status == .completed else { throw RenderingError.pixels }
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { storage in
            texture.getBytes(storage.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: pixels as CFData), let image = CGImage(width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw RenderingError.pixels }
        return image
    }

    public func actualPixelScale(in view: MTKView) -> Double {
        guard let frame else { return 1 }
        let fit = min(view.drawableSize.width / CGFloat(max(1, frame.sourceSize.width)),
                      view.drawableSize.height / CGFloat(max(1, frame.sourceSize.height)))
        return Double(fit * viewport.zoom)
    }
    public func fit(in view: MTKView) { viewport.reset(); changed(in: view) }
    public func actualSize(in view: MTKView) {
        guard let frame else { return }
        let fit = min(view.drawableSize.width / CGFloat(max(1, frame.sourceSize.width)),
                      view.drawableSize.height / CGFloat(max(1, frame.sourceSize.height)))
        viewport.zoom = max(1, 1 / max(0.001, fit)); viewport.offset = .zero; changed(in: view)
    }
    public func changed(in view: MTKView) {
        guard let frame else { return }
        let fit = min(view.bounds.width / CGFloat(frame.texture.width), view.bounds.height / CGFloat(frame.texture.height))
        let maxX = max(0, (CGFloat(frame.texture.width) * fit * viewport.zoom - view.bounds.width) / 2)
        let maxY = max(0, (CGFloat(frame.texture.height) * fit * viewport.zoom - view.bounds.height) / 2)
        viewport.offset.x = min(maxX, max(-maxX, viewport.offset.x))
        viewport.offset.y = min(maxY, max(-maxY, viewport.offset.y))
        view.needsDisplay = true
        onZoomChanged?(actualPixelScale(in: view))
    }
}
