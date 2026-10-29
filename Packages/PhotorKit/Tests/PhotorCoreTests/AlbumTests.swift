import Foundation
import PhotorCore

struct AlbumTests {
    func persistenceMembershipAndLimits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AlbumStore(url: directory.appendingPathComponent("albums.json"))
        var library = try await store.load()
        try expect(library.customAlbums.count == 1)
        let photo = PhotoAsset(url: URL(fileURLWithPath: "/photos/a.jpg"), revision: FileRevision(byteCount: 12, modifiedAt: .distantPast))
        try library.toggle(photo, in: PhotoAlbum.favoritesID)
        try library.toggle(photo, in: library.customAlbums[0].id)
        for name in ["Viaggio", "Stampa", "Famiglia"] { try library.add(name: name) }
        try expect(library.customAlbums.count == 4)
        try expect(Set(library.customAlbums.map(\.symbol)).count == 4)
        do { try library.add(name: "Quinto"); throw CheckFailure(description: "Limite album non applicato") }
        catch is AlbumError {}
        let id = library.customAlbums[0].id
        try library.rename(id, to: "Da stampare")
        try await store.save(library, revision: 2)
        try await store.save(AlbumLibrary(), revision: 1)
        let loaded = try await AlbumStore(url: store.url).load()
        try expect(loaded == library)
        library.relocatePhoto(from: photo.id.path, to: "/moved/a.jpg")
        try expect(library.album(id)!.paths.contains("/moved/a.jpg"))
        try expect(library.album(PhotoAlbum.favoritesID)!.paths.contains("/moved/a.jpg"))
        library.removePhoto(at: "/moved/a.jpg")
        try expect(library.albums.allSatisfy { $0.paths.isEmpty })
        library.removeAlbum(PhotoAlbum.favoritesID)
        try expect(library.album(PhotoAlbum.favoritesID) != nil)
        try Data("broken".utf8).write(to: store.url)
        do { _ = try await store.load(); throw CheckFailure(description: "Archivio corrotto accettato") }
        catch is AlbumError {}
    }
}
