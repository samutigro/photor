// A sorted plan with a cursor: dequeue is O(1). Navigation replaces the plan atomically.
struct PriorityWorkQueue {
    private var items: [PlannedDecode] = []
    private var cursor = 0
    var remaining: Int { items.count - cursor }
    mutating func replace(with plan: [PlannedDecode]) { items = plan; cursor = 0 }
    mutating func pop() -> PlannedDecode? {
        guard cursor < items.count else { return nil }
        defer { cursor += 1 }
        return items[cursor]
    }
}
