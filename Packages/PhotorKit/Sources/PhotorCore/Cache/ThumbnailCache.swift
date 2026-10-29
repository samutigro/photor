import Foundation

/// Visible cells enqueue small previews; cancelled offscreen cells leave the queue immediately.
public actor ThumbnailCache {
    private let decoder: any PhotoDecoder
    private let budget: MemoryBudget
    private let executor = DecodeExecutor(concurrency: 2, qualityOfService: .utility)
    private var entries: [CacheKey: (CachedImage, UInt64)] = [:]
    private var tick: UInt64 = 0
    private struct Request {
        let asset: PhotoAsset
        let continuation: CheckedContinuation<CachedImage, Error>
        let flag: CancellationFlag
    }
    private var pending: [UUID: Request] = [:]
    private var order: [UUID] = []
    private var active: [UUID: Request] = [:]
    public init(decoder: any PhotoDecoder, budget: MemoryBudget) { self.decoder = decoder; self.budget = budget }

    public func image(for asset: PhotoAsset) async throws -> CachedImage {
        try Task.checkCancellation()
        let key = CacheKey(asset: asset, representation: .screen(maxPixel: 512))
        tick &+= 1
        if let entry = entries[key] { entries[key] = (entry.0, tick); return entry.0 }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = Request(asset: asset, continuation: continuation, flag: CancellationFlag())
                order.append(id); pump()
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    public func clear() {
        entries.removeAll()
        for request in pending.values { request.continuation.resume(throwing: CancellationError()) }
        pending.removeAll(); order.removeAll()
        for request in active.values { request.flag.cancel() }
    }
    public func counts() -> (active: Int, pending: Int, cached: Int) { (active.count, pending.count, entries.count) }
    private func cancel(_ id: UUID) {
        if let request = pending.removeValue(forKey: id) { request.continuation.resume(throwing: CancellationError()) }
        active[id]?.flag.cancel()
    }
    private func evict() -> Bool {
        guard let key = entries.min(by: { $0.value.1 < $1.value.1 })?.key else { return false }
        entries.removeValue(forKey: key); return true
    }
    private func pump() {
        while active.count < 2, let id = order.popLast() {
            guard let request = pending.removeValue(forKey: id) else { continue }
            while budget.snapshot.limit - budget.snapshot.used < 64 * 1_048_576, evict() {}
            guard let scratch = budget.reserve(64 * 1_048_576, category: "Lavori miniature") else {
                request.continuation.resume(throwing: PhotoError.memory); continue
            }
            active[id] = request
            let executor = self.executor, decoder = self.decoder
            Task {
                let result: Result<DecodedImage, Error>
                do { result = .success(try await executor.decode(DecodeRequest(asset: request.asset, representation: .screen(maxPixel: 512)), using: decoder, cancellation: request.flag)) }
                catch { result = .failure(error) }
                finish(id, result: result, scratch: scratch)
            }
        }
    }
    private func finish(_ id: UUID, result: Result<DecodedImage, Error>, scratch: MemoryLease) {
        guard let request = active.removeValue(forKey: id) else { scratch.release(); return }
        switch result {
        case .success(let image) where !request.flag.isCancelled:
            let limit = min(256 * 1_048_576, budget.snapshot.limit / 16)
            while budget.snapshot.byCategory["Miniature", default: 0] + image.byteCount > limit, evict() {}
            while budget.snapshot.limit - budget.snapshot.used < image.byteCount, evict() {}
            if let lease = budget.reserve(image.byteCount, category: "Miniature") {
                let key = CacheKey(asset: request.asset, representation: .screen(maxPixel: 512))
                let frame = CachedImage(key: key, decoded: image, lease: lease)
                tick &+= 1; entries[key] = (frame, tick)
                request.continuation.resume(returning: frame)
            } else { request.continuation.resume(throwing: PhotoError.memory) }
        case .success: request.continuation.resume(throwing: CancellationError())
        case .failure(let error): request.continuation.resume(throwing: error)
        }
        scratch.release(); pump()
    }
}
