import Foundation
import PhotorCore

enum ViewerSettings {
    static func load() -> ViewerConfiguration {
        let defaults = UserDefaults.standard
        let physicalGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let saved = defaults.integer(forKey: "memoryGiB")
        let memory = saved > 0 ? saved : min(16, max(4, physicalGiB / 4))
        let radius = defaults.object(forKey: "prefetchRadius") as? Int ?? 100
        return ViewerConfiguration(memoryLimit: memory * 1_073_741_824, prefetchRadius: radius,
            fillFolder: defaults.object(forKey: "fillFolder") as? Bool ?? true)
    }
    static func save(_ value: ViewerConfiguration) {
        UserDefaults.standard.set(value.memoryLimit / 1_073_741_824, forKey: "memoryGiB")
        UserDefaults.standard.set(value.prefetchRadius, forKey: "prefetchRadius")
        UserDefaults.standard.set(value.fillFolder, forKey: "fillFolder")
    }
}
