import PhotorCore

// A small, synchronous front cache makes a warm arrow-key navigation possible in the same UI turn.
// These are references to existing textures, with the original memory lease, never pixel copies.
@MainActor
public final class PresentationCache {
    private var frames: [PhotoID: TextureFrame] = [:]
    private var order: [PhotoID] = []
    public init() {}
    public func frame(for asset: PhotoAsset) -> TextureFrame? {
        guard let value = frames[asset.id], value.key.revision == asset.revision else { return nil }
        touch(asset.id); return value
    }
    public func insert(_ frame: TextureFrame) {
        if frames[frame.key.photo]?.key.representation.isFull == true && !frame.key.representation.isFull { return }
        frames[frame.key.photo] = frame; touch(frame.key.photo)
        while order.count > 6 { frames.removeValue(forKey: order.removeFirst()) }
    }
    public func clear(keeping id: PhotoID? = nil) {
        frames = frames.filter { $0.key == id }; order = order.filter { $0 == id }
    }
    private func touch(_ id: PhotoID) { order.removeAll { $0 == id }; order.append(id) }
}
