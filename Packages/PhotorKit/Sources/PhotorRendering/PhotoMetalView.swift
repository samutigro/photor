import AppKit
import MetalKit

@MainActor
public final class PhotoMetalView: MTKView {
    public var renderer: MetalRenderer?
    public var onNavigate: ((Int) -> Void)?
    public var onPixelSizeChanged: ((Int) -> Void)?
    private var previousDrag: CGPoint?
    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
    public override func layout() {
        super.layout()
        onPixelSizeChanged?(Int(max(drawableSize.width, drawableSize.height)))
        if let renderer { renderer.changed(in: self) }
    }
    public override func magnify(with event: NSEvent) {
        renderer?.viewport.magnify(by: max(0.1, 1 + event.magnification),
            anchor: convert(event.locationInWindow, from: nil), bounds: bounds.size)
        renderer?.changed(in: self)
    }
    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            renderer?.viewport.magnify(by: exp(event.scrollingDeltaY * 0.01),
                anchor: convert(event.locationInWindow, from: nil), bounds: bounds.size)
        } else {
            renderer?.viewport.offset.x += event.scrollingDeltaX
            renderer?.viewport.offset.y -= event.scrollingDeltaY
        }
        renderer?.changed(in: self)
    }
    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            if (renderer?.viewport.zoom ?? 1) > 1 { renderer?.fit(in: self) }
            else { renderer?.actualSize(in: self) }
        } else { previousDrag = convert(event.locationInWindow, from: nil) }
    }
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let old = previousDrag {
            renderer?.viewport.offset.x += point.x - old.x
            renderer?.viewport.offset.y += point.y - old.y
            renderer?.changed(in: self)
        }
        previousDrag = point
    }
    public override func mouseUp(with event: NSEvent) { previousDrag = nil }
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: onNavigate?(-1)
        case 124: onNavigate?(1)
        case 49: renderer?.fit(in: self)
        case 18: renderer?.actualSize(in: self)
        case 24, 69:
            renderer?.viewport.magnify(by: 1.25, anchor: CGPoint(x: bounds.midX, y: bounds.midY), bounds: bounds.size)
            renderer?.changed(in: self)
        case 27, 78:
            renderer?.viewport.magnify(by: 0.8, anchor: CGPoint(x: bounds.midX, y: bounds.midY), bounds: bounds.size)
            renderer?.changed(in: self)
        default: super.keyDown(with: event)
        }
    }
}
