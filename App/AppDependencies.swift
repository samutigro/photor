import Foundation
import Metal
import PhotorCore
import PhotorDecoders
import PhotorRendering

@MainActor
final class AppDependencies {
    let budget: MemoryBudget
    let pipeline: PhotoPipeline
    let textures: TextureCache
    let renderer: MetalRenderer
    let presentations = PresentationCache()
    init(configuration: ViewerConfiguration) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderingError.unavailable }
        budget = MemoryBudget(limit: configuration.memoryLimit)
        pipeline = PhotoPipeline(decoder: DecoderRegistry(), configuration: configuration, budget: budget)
        textures = TextureCache(device: device, budget: budget)
        renderer = try MetalRenderer(device: device)
    }
}
