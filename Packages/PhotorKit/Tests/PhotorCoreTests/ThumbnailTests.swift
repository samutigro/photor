import Foundation
import PhotorCore

struct ThumbnailTests {
    func boundedWorkersAndCancellation() async throws {
        let decoder = SlowDecoder(), budget = MemoryBudget(limit: 512 * 1_048_576)
        let cache = ThumbnailCache(decoder: decoder, budget: budget)
        let tasks = (0..<100).map { number in
            Task {
                let photo = PhotoAsset(url: URL(fileURLWithPath: "/tmp/thumb-\(number).jpg"), revision: FileRevision(byteCount: 1, modifiedAt: .distantPast))
                _ = try? await cache.image(for: photo)
            }
        }
        try await Task.sleep(for: .milliseconds(15))
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
        await cache.clear()
        let counts = await cache.counts()
        try expect(counts.active == 0 && counts.pending == 0 && counts.cached == 0)
        try expect(decoder.maximumConcurrent > 0 && decoder.maximumConcurrent <= 2)
        try expect(budget.snapshot.used == 0)
    }
}
