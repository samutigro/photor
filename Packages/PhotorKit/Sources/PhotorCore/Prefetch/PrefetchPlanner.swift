import Foundation

public struct PlannedDecode: Sendable {
    public let request: DecodeRequest
    public let priority: Int
    public let opportunistic: Bool
}

public struct PrefetchPlanner: Sendable {
    public init() {}
    public func plan(assets: [PhotoAsset], current: Int, direction: Int,
                     configuration: ViewerConfiguration) -> [PlannedDecode] {
        guard assets.indices.contains(current) else { return [] }
        return assets.indices.flatMap { index -> [PlannedDecode] in
            let distance = abs(index - current)
            let outside = distance > configuration.prefetchRadius
            guard !outside || configuration.fillFolder else { return [] }
            let directionBonus = (index - current) * direction >= 0 ? 0 : 1
            var items = [PlannedDecode(request: DecodeRequest(asset: assets[index],
                representation: .screen(maxPixel: configuration.screenMaxPixel)),
                priority: outside ? 100_000 + distance : distance * 10 + directionBonus,
                opportunistic: outside)]
            let fullRadius = assets[index].isRAW ? min(1, configuration.fullResolutionRadius) : configuration.fullResolutionRadius
            if distance <= fullRadius {
                items.append(PlannedDecode(request: DecodeRequest(asset: assets[index], representation: .full),
                    priority: distance == 0 ? 3 : (assets[index].isRAW ? 2000 : 20) + distance * 20 + directionBonus,
                    opportunistic: false))
            }
            return items
        }.sorted { $0.priority < $1.priority }
    }
}
