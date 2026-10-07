import Foundation

public struct PipelineStatus: Sendable {
    public let cachedPhotos: Int
    public let fullPhotos: Int
    public let running: Int
    public let pending: Int
    public let memory: MemorySnapshot
    public let lastDecodeMilliseconds: Double
}

public enum PipelineEvent: Sendable {
    case catalog([PhotoAsset], folder: URL)
    case selected(index: Int, navigation: UInt64)
    case display(CachedImage, navigation: UInt64)
    case warm(CachedImage)
    case status(PipelineStatus)
    case failure(PhotoID?, String)
    case memoryPressure
}

public actor PhotoPipeline {
    public nonisolated let events: AsyncStream<PipelineEvent>
    public nonisolated let budget: MemoryBudget
    private let continuation: AsyncStream<PipelineEvent>.Continuation
    private let decoder: any PhotoDecoder
    private let executor = DecodeExecutor(concurrency: 2)
    private let planner = PrefetchPlanner()
    private var configuration: ViewerConfiguration
    private var assets: [PhotoAsset] = []
    private var index = 0
    private var direction = 1
    private var generation: UInt64 = 0
    private var navigation: UInt64 = 0
    private var cache = ImageCache()
    private var queue = PriorityWorkQueue()
    private var failed: Set<CacheKey> = []
    private var deferred: Set<CacheKey> = []
    private var priorities: [CacheKey: Int] = [:]
    private struct Job {
        let request: DecodeRequest
        let generation: UInt64
        let cancellation: CancellationFlag
        let opportunistic: Bool
    }
    private var jobs: [UUID: Job] = [:]
    private var lastStatus = Date.distantPast
    private var lastDecode = 0.0
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    public init(decoder: any PhotoDecoder, configuration: ViewerConfiguration, budget: MemoryBudget) {
        self.decoder = decoder; self.configuration = configuration; self.budget = budget
        let stream = AsyncStream<PipelineEvent>.makeStream()
        events = stream.stream; continuation = stream.continuation
    }

    public func startMemoryMonitoring() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self, weak source] in
            let critical = source?.data.contains(.critical) == true
            Task { await self?.handleMemoryPressure(critical: critical) }
        }
        pressureSource = source; source.resume()
    }

    public func open(_ folder: URL) async {
        generation &+= 1; navigation &+= 1
        let requestedGeneration = generation
        for job in jobs.values { job.cancellation.cancel() }
        assets = []; cache.removeAll(); failed.removeAll(); deferred.removeAll()
        queue.replace(with: []); publishStatus(force: true)
        do {
            let scanned = try await Task.detached(priority: .userInitiated) { try FolderCatalog().scan(folder) }.value
            guard generation == requestedGeneration else { return }
            assets = scanned; index = 0
            continuation.yield(.catalog(scanned, folder: folder))
            continuation.yield(.selected(index: 0, navigation: navigation))
            rebuild()
        } catch {
            guard generation == requestedGeneration else { return }
            continuation.yield(.failure(nil, error.localizedDescription))
        }
    }

    public func select(_ newIndex: Int) {
        guard assets.indices.contains(newIndex) else { return }
        direction = newIndex >= index ? 1 : -1
        index = newIndex; navigation &+= 1; deferred.removeAll()
        continuation.yield(.selected(index: index, navigation: navigation))
        showCurrent()
        rebuild()
    }

    public func configure(_ value: ViewerConfiguration) {
        configuration = value; budget.setLimit(value.memoryLimit); deferred.removeAll()
        while budget.snapshot.used > value.memoryLimit && cache.evictOne(protected: currentIDs, preferred: []) {}
        showCurrent(); rebuild()
    }

    public func retry() {
        failed.removeAll(); deferred.removeAll(); rebuild()
    }

    public func setScreenMaxPixel(_ size: Int) {
        guard size > 0, size != configuration.screenMaxPixel else { return }
        configuration.screenMaxPixel = size
        deferred.removeAll(); showCurrent(); rebuild()
    }

    public func snapshot() -> PipelineStatus { makeStatus() }

    private var currentIDs: Set<PhotoID> {
        assets.indices.contains(index) ? [assets[index].id] : []
    }
    private var preferredIDs: Set<PhotoID> {
        guard !assets.isEmpty else { return [] }
        let lo = max(0, index - configuration.prefetchRadius)
        let hi = min(assets.count - 1, index + configuration.prefetchRadius)
        return Set(assets[lo...hi].map(\.id))
    }

    private func rebuild() {
        guard !assets.isEmpty else { publishStatus(force: true); return }
        let plan = planner.plan(assets: assets, current: index, direction: direction, configuration: configuration)
        priorities = Dictionary(uniqueKeysWithValues: plan.map { ($0.request.key, $0.priority) })
        let desired = Set(plan.filter { !$0.opportunistic }.map { $0.request.key })
        let allKeys = Set(plan.map { $0.request.key })
        let urgentWork = plan.contains { !$0.opportunistic && !cache.contains($0.request.key) && !failed.contains($0.request.key) }
        for job in jobs.values where job.generation == generation {
            if !allKeys.contains(job.request.key) || (!desired.contains(job.request.key) && urgentWork) { job.cancellation.cancel() }
        }
        queue.replace(with: plan)
        for nearby in max(0, index - 2)...min(assets.count - 1, index + 2) where nearby != index {
            let asset = assets[nearby]
            let full = CacheKey(asset: asset, representation: .full)
            let screen = CacheKey(asset: asset, representation: .screen(maxPixel: configuration.screenMaxPixel))
            if let frame = cache.get(full) ?? cache.get(screen) { continuation.yield(.warm(frame)) }
        }
        pump(); publishStatus(force: true)
    }

    private func showCurrent() {
        guard assets.indices.contains(index) else { return }
        let asset = assets[index]
        let full = CacheKey(asset: asset, representation: .full)
        let screen = CacheKey(asset: asset, representation: .screen(maxPixel: configuration.screenMaxPixel))
        if let frame = cache.get(full) ?? cache.get(screen) {
            continuation.yield(.display(frame, navigation: navigation))
        }
    }

    private func reserve(_ bytes: Int, category: String, mayEvict: Bool, incomingPriority: Int? = nil) -> MemoryLease? {
        while true {
            let snapshot = budget.snapshot
            let withinImageAllowance = category != "Immagini" || snapshot.byCategory["Immagini", default: 0] + bytes <= snapshot.limit * 3 / 5
            if withinImageAllowance, let lease = budget.reserve(bytes, category: category) { return lease }
            guard mayEvict, cache.evictOne(protected: currentIDs, preferred: preferredIDs,
                priorities: priorities, incomingPriority: incomingPriority) else { return nil }
        }
    }

    private func pump() {
        while jobs.count < 2, let planned = queue.pop() {
            let request = planned.request, key = request.key
            if planned.opportunistic, budget.snapshot.byCategory["Immagini", default: 0] >= budget.snapshot.limit * 11 / 20 {
                deferred.insert(key); continue
            }
            guard !cache.contains(key), !failed.contains(key), !deferred.contains(key),
                  !jobs.values.contains(where: { $0.generation == generation && $0.request.key == key }) else { continue }
            // Conservative scratch reservations, not a claim about exact framework-internal allocations.
            let scratchBytes = request.asset.isRAW && request.representation.isFull ? 1_073_741_824 : 536_870_912
            guard let scratch = reserve(scratchBytes, category: "Lavori", mayEvict: !planned.opportunistic, incomingPriority: planned.priority) else {
                deferred.insert(key)
                if currentIDs.contains(key.photo), !cache.entries.keys.contains(where: { $0.photo == key.photo }) {
                    continuation.yield(.failure(key.photo, PhotoError.memory.localizedDescription))
                }
                continue
            }
            let id = UUID(), flag = CancellationFlag()
            jobs[id] = Job(request: request, generation: generation, cancellation: flag, opportunistic: planned.opportunistic)
            let executor = self.executor, decoder = self.decoder
            Task { [weak self] in
                let result: Result<DecodedImage, Error>
                do { result = .success(try await executor.decode(request, using: decoder, cancellation: flag)) }
                catch { result = .failure(error) }
                await self?.finish(id: id, result: result, scratch: scratch)
            }
        }
    }

    private func finish(id: UUID, result: Result<DecodedImage, Error>, scratch: MemoryLease) {
        guard let job = jobs.removeValue(forKey: id) else { scratch.release(); return }
        var needsReplan = false
        if job.generation == generation {
            switch result {
            case .success(let decoded):
                if let lease = reserve(decoded.byteCount, category: "Immagini", mayEvict: !job.opportunistic,
                    incomingPriority: priorities[job.request.key]) {
                    let frame = CachedImage(key: job.request.key, decoded: decoded, lease: lease)
                    cache.insert(frame); lastDecode = decoded.decodeMilliseconds
                    if currentIDs.contains(frame.key.photo) { showCurrent() }
                    else if let position = assets.firstIndex(where: { $0.id == frame.key.photo }), abs(position - index) <= 2 {
                        continuation.yield(.warm(frame))
                    }
                } else { deferred.insert(job.request.key) }
            case .failure(let error):
                if !(error is CancellationError), (error as? PhotoError) != .cancelled {
                    failed.insert(job.request.key)
                    if currentIDs.contains(job.request.key.photo) { continuation.yield(.failure(job.request.key.photo, error.localizedDescription)) }
                } else { needsReplan = true }
            }
        }
        scratch.release()
        if needsReplan { rebuild() } else { pump() }
        publishStatus(force: jobs.isEmpty)
    }

    private func handleMemoryPressure(critical: Bool) {
        for job in jobs.values { job.cancellation.cancel() }
        configuration.fillFolder = false
        configuration.prefetchRadius = critical ? 2 : 20
        configuration.fullResolutionRadius = 0
        budget.setLimit(max(536_870_912, configuration.memoryLimit / (critical ? 4 : 2)))
        while cache.evictOne(protected: currentIDs, preferred: []) {}
        continuation.yield(.memoryPressure)
        deferred.removeAll(); rebuild()
    }

    private func makeStatus() -> PipelineStatus {
        PipelineStatus(cachedPhotos: Set(cache.entries.keys.map(\.photo)).count,
            fullPhotos: cache.entries.keys.filter { $0.representation.isFull }.count,
            running: jobs.count, pending: queue.remaining, memory: budget.snapshot, lastDecodeMilliseconds: lastDecode)
    }
    private func publishStatus(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastStatus) > 0.15 else { return }
        lastStatus = Date(); continuation.yield(.status(makeStatus()))
    }
}
