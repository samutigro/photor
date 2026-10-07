import Foundation

public final class CachedImage: Sendable {
    public let key: CacheKey
    public let decoded: DecodedImage
    private let lease: MemoryLease
    public init(key: CacheKey, decoded: DecodedImage, lease: MemoryLease) {
        self.key = key; self.decoded = decoded; self.lease = lease
    }
}

// Confined to PhotoPipeline's actor. Lookup is O(1); eviction scans only on allocation pressure.
struct ImageCache {
    struct Entry { let frame: CachedImage; var touched: UInt64 }
    var entries: [CacheKey: Entry] = [:]
    private var tick: UInt64 = 0
    var count: Int { entries.count }
    func contains(_ key: CacheKey) -> Bool { entries[key] != nil }
    mutating func get(_ key: CacheKey) -> CachedImage? {
        tick &+= 1
        guard var entry = entries[key] else { return nil }
        entry.touched = tick; entries[key] = entry
        return entry.frame
    }
    mutating func insert(_ frame: CachedImage) {
        tick &+= 1; entries[frame.key] = Entry(frame: frame, touched: tick)
    }
    mutating func removeAll() { entries.removeAll() }
    mutating func evictOne(protected: Set<PhotoID>, preferred: Set<PhotoID>,
                          priorities: [CacheKey: Int] = [:], incomingPriority: Int? = nil) -> Bool {
        let candidates = entries.filter { !protected.contains($0.key.photo) }
        let victim = candidates.min {
            let lrank = priorities[$0.key] ?? 1_000_000, rrank = priorities[$1.key] ?? 1_000_000
            if lrank != rrank { return lrank > rrank }
            let lp = preferred.contains($0.key.photo), rp = preferred.contains($1.key.photo)
            return lp == rp ? $0.value.touched < $1.value.touched : !lp
        }
        guard let key = victim?.key else { return false }
        if let incomingPriority, incomingPriority > priorities[key, default: 1_000_000] { return false }
        entries.removeValue(forKey: key)
        return true
    }
}
