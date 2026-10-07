import Foundation

public struct PhotoID: Hashable, Sendable {
    public let path: String
    public init(url: URL) { path = url.standardizedFileURL.path }
}

public struct FileRevision: Hashable, Sendable {
    public let byteCount: Int64
    public let modifiedAt: Date
    public init(byteCount: Int64, modifiedAt: Date) {
        self.byteCount = byteCount; self.modifiedAt = modifiedAt
    }
}

public struct PhotoAsset: Identifiable, Hashable, Sendable {
    public let id: PhotoID
    public let url: URL
    public let revision: FileRevision
    public var name: String { url.lastPathComponent }
    public var isRAW: Bool { url.pathExtension.lowercased() == "raf" }
    public init(url: URL, revision: FileRevision) {
        id = PhotoID(url: url); self.url = url; self.revision = revision
    }
}

public struct PixelSize: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var longestEdge: Int { max(width, height) }
}
