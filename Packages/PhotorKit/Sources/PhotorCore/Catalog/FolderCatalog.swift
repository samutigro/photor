import Foundation

public struct FolderCatalog: Sendable {
    public init() {}
    public func scan(_ folder: URL) throws -> [PhotoAsset] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let supported: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "raf"]
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        return urls.compactMap { url -> PhotoAsset? in
            guard supported.contains(url.pathExtension.lowercased()),
                  let info = try? url.resourceValues(forKeys: keys), info.isRegularFile == true else { return nil }
            return PhotoAsset(url: url, revision: FileRevision(byteCount: Int64(info.fileSize ?? 0),
                modifiedAt: info.contentModificationDate ?? .distantPast))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
