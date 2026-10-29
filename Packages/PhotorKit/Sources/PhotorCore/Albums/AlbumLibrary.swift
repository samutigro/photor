import Foundation

public struct PhotoAlbum: Codable, Identifiable, Equatable, Sendable {
    public static let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public let id: UUID
    public var name: String
    public let symbol: String
    public var paths: Set<String>
    public var isFavorites: Bool { id == Self.favoritesID }
    public init(id: UUID = UUID(), name: String, symbol: String, paths: Set<String> = []) {
        self.id = id; self.name = name; self.symbol = symbol; self.paths = paths
    }
    public func contains(_ photo: PhotoAsset) -> Bool { paths.contains(photo.id.path) }
}

public enum AlbumError: Error, LocalizedError {
    case limit, invalidName, duplicateName, missing, invalidLibrary
    public var errorDescription: String? {
        switch self {
        case .limit: "Puoi creare al massimo quattro album personalizzati."
        case .invalidName: "Usa un nome da 1 a 64 caratteri."
        case .duplicateName: "Esiste già un album con questo nome."
        case .missing: "Album non disponibile."
        case .invalidLibrary: "Archivio degli album non valido. Il file esistente non è stato sovrascritto."
        }
    }
}

public struct AlbumLibrary: Codable, Equatable, Sendable {
    public private(set) var version = 1
    public private(set) var albums: [PhotoAlbum]
    public var customAlbums: [PhotoAlbum] { albums.filter { !$0.isFavorites } }
    public init() {
        albums = [PhotoAlbum(id: PhotoAlbum.favoritesID, name: "Preferiti", symbol: "star"),
                  PhotoAlbum(name: "Selezione", symbol: "bookmark")]
    }
    public func album(_ id: UUID) -> PhotoAlbum? { albums.first { $0.id == id } }
    public func validate() throws {
        guard version == 1, albums.count <= 5, albums.count >= 1,
              albums.first?.id == PhotoAlbum.favoritesID,
              Set(albums.map(\.id)).count == albums.count,
              albums.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 64 }),
              Set(albums.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }).count == albums.count,
              albums.allSatisfy({ ["star", "bookmark", "flag", "heart", "tag"].contains($0.symbol) && $0.paths.allSatisfy { $0.hasPrefix("/") } }) else {
            throw AlbumError.invalidLibrary
        }
    }
    @discardableResult public mutating func add(name: String) throws -> UUID {
        guard customAlbums.count < 4 else { throw AlbumError.limit }
        let name = try checkedName(name)
        let used = Set(customAlbums.map(\.symbol))
        let symbol = ["bookmark", "flag", "heart", "tag"].first { !used.contains($0) } ?? "tag"
        let album = PhotoAlbum(name: name, symbol: symbol)
        albums.append(album); return album.id
    }
    public mutating func rename(_ id: UUID, to name: String) throws {
        guard id != PhotoAlbum.favoritesID, let index = albums.firstIndex(where: { $0.id == id }) else { throw AlbumError.missing }
        albums[index].name = try checkedName(name, excluding: id)
    }
    public mutating func removeAlbum(_ id: UUID) {
        guard id != PhotoAlbum.favoritesID else { return }
        albums.removeAll { $0.id == id }
    }
    public mutating func toggle(_ photo: PhotoAsset, in id: UUID) throws {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { throw AlbumError.missing }
        if !albums[index].paths.insert(photo.id.path).inserted { albums[index].paths.remove(photo.id.path) }
    }
    public mutating func removePhoto(at path: String) {
        for index in albums.indices { albums[index].paths.remove(path) }
    }
    public mutating func relocatePhoto(from old: String, to new: String) {
        for index in albums.indices where albums[index].paths.remove(old) != nil { albums[index].paths.insert(new) }
    }
    private func checkedName(_ raw: String, excluding id: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64 else { throw AlbumError.invalidName }
        guard !albums.contains(where: { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { throw AlbumError.duplicateName }
        return name
    }
    public static func resolve(_ album: PhotoAlbum) -> (photos: [PhotoAsset], missing: Int) {
        let photos = album.paths.compactMap { path -> PhotoAsset? in
            let url = URL(fileURLWithPath: path)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { return nil }
            return PhotoAsset(url: url, revision: FileRevision(byteCount: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast))
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id.path < $1.id.path : comparison == .orderedAscending
        }
        return (photos, album.paths.count - photos.count)
    }
}

public actor AlbumStore {
    public nonisolated let url: URL
    private var lastRevision: UInt64 = 0
    public init(url: URL) { self.url = url }
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photor", isDirectory: true).appendingPathComponent("albums.json")
    }
    public func load() throws -> AlbumLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return AlbumLibrary() }
        do {
            let library = try JSONDecoder().decode(AlbumLibrary.self, from: Data(contentsOf: url))
            try library.validate(); return library
        } catch { throw AlbumError.invalidLibrary }
    }
    public func save(_ library: AlbumLibrary, revision: UInt64) throws {
        guard revision >= lastRevision else { return }
        try library.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
        lastRevision = revision
    }
}
