import Foundation

public struct MemorySnapshot: Sendable {
    public let used: Int
    public let limit: Int
    public let byCategory: [String: Int]
}

// The lock protects only counters; no decoding, allocations or GPU calls occur under it.
public final class MemoryBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var limit: Int
    private var used = 0
    private var categories: [String: Int] = [:]
    public init(limit: Int) { self.limit = max(0, limit) }
    public var snapshot: MemorySnapshot {
        lock.withLock { MemorySnapshot(used: used, limit: limit, byCategory: categories) }
    }
    public func setLimit(_ bytes: Int) { lock.withLock { limit = max(0, bytes) } }
    public func reserve(_ bytes: Int, category: String) -> MemoryLease? {
        guard bytes >= 0 else { return nil }
        return lock.withLock {
            guard bytes <= max(0, limit - used) else { return nil }
            used += bytes; categories[category, default: 0] += bytes
            return MemoryLease(bytes: bytes, category: category, budget: self)
        }
    }
    fileprivate func release(_ bytes: Int, category: String) {
        lock.withLock { used -= bytes; categories[category, default: 0] -= bytes }
    }
}

public final class MemoryLease: @unchecked Sendable {
    public let bytes: Int
    private let category: String
    private let budget: MemoryBudget
    private let lock = NSLock()
    private var released = false
    fileprivate init(bytes: Int, category: String, budget: MemoryBudget) {
        self.bytes = bytes; self.category = category; self.budget = budget
    }
    public func release() {
        lock.withLock {
            guard !released else { return }
            released = true
            budget.release(bytes, category: category)
        }
    }
    deinit { release() }
}
