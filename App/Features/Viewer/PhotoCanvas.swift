import SwiftUI
import MetalKit
import PhotorRendering

struct PhotoCanvas: NSViewRepresentable {
    @ObservedObject var model: ViewerModel
    func makeNSView(context: Context) -> PhotoMetalView {
        let view = PhotoMetalView(frame: .zero, device: model.dependencies?.renderer.device)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColorMake(0.008, 0.008, 0.01, 1)
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.renderer = model.dependencies?.renderer
        view.delegate = view.renderer
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.onNavigate = { [weak model] delta in model?.move(delta) }
        view.onPixelSizeChanged = { [weak model] size in
            Task { @MainActor in model?.updatePixelSize(size) }
        }
        view.renderer?.onZoomChanged = { [weak model] zoom in
            Task { @MainActor in if model?.zoom != zoom { model?.zoom = zoom } }
        }
        model.canvas = view
        return view
    }
    func updateNSView(_ view: PhotoMetalView, context: Context) {
        guard let renderer = view.renderer else { return }
        let old = renderer.frame
        if old?.key.photo != model.frame?.key.photo, model.frame != nil { renderer.viewport.reset() }
        renderer.frame = model.frame
        if old !== model.frame {
            view.needsDisplay = true
            if model.frame != nil { renderer.changed(in: view) }
        }
    }
}
