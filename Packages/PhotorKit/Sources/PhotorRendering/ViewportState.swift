import Foundation
import CoreGraphics

public struct ViewportState {
    public var zoom: CGFloat = 1
    public var offset: CGPoint = .zero
    public init() {}
    public mutating func reset() { zoom = 1; offset = .zero }
    public mutating func magnify(by factor: CGFloat, anchor: CGPoint, bounds: CGSize) {
        let old = zoom
        zoom = min(32, max(1, zoom * factor))
        let ratio = zoom / old
        let point = CGPoint(x: anchor.x - bounds.width / 2, y: anchor.y - bounds.height / 2)
        offset = CGPoint(x: point.x - (point.x - offset.x) * ratio,
                         y: point.y - (point.y - offset.y) * ratio)
        if zoom == 1 { offset = .zero }
    }
}
