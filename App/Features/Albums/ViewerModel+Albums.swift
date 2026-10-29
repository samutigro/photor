import Foundation
import PhotorCore

extension ViewerModel {
    var activeAlbum: PhotoAlbum? { activeAlbumID.flatMap { library.album($0) } }
    var collectionTitle: String { activeAlbum?.name ?? folder?.lastPathComponent ?? "Cartella" }
    var albumButtons: [PhotoAlbum] { library.albums }
    func albumShortcut(_ album: PhotoAlbum) -> String {
        album.isFavorites ? "⌘S" : "⌘\((library.customAlbums.firstIndex { $0.id == album.id } ?? 0) + 1)"
    }
    func loadAlbums() async {
        do {
            library = try await albumStore.load()
            libraryReady = true
        } catch { albumSaveError = error.localizedDescription }
    }
    func toggleAlbum(_ id: UUID, photo: PhotoAsset? = nil) {
        guard libraryReady, !isFileOperationRunning, let photo = photo ?? selected else { return }
        do {
            try library.toggle(photo, in: id)
            albumsChanged()
            if activeAlbumID == id { showAlbum(id) }
        } catch { notice = error.localizedDescription }
    }
    func toggleCustomAlbum(_ position: Int) {
        guard library.customAlbums.indices.contains(position) else { return }
        toggleAlbum(library.customAlbums[position].id)
    }
    func addAlbum(_ name: String) {
        guard libraryReady, !isFileOperationRunning else { return }
        do { try library.add(name: name); notice = nil; albumsChanged() }
        catch { notice = error.localizedDescription }
    }
    func renameAlbum(_ id: UUID, to name: String) {
        guard libraryReady, !isFileOperationRunning else { return }
        do { try library.rename(id, to: name); notice = nil; albumsChanged() }
        catch { notice = error.localizedDescription }
    }
    func removeAlbum(_ id: UUID) {
        guard libraryReady, !isFileOperationRunning else { return }
        library.removeAlbum(id); albumsChanged()
        if activeAlbumID == id { showFolder() }
    }
    func albumsChanged() {
        albumRevision &+= 1; hasUnsavedAlbums = true
        Task { _ = await flushAlbums() }
    }
    @discardableResult func flushAlbums() async -> Bool {
        guard hasUnsavedAlbums, libraryReady else { return !hasUnsavedAlbums }
        while hasUnsavedAlbums {
            let snapshot = library, revision = albumRevision
            do {
                try await albumStore.save(snapshot, revision: revision)
                if revision == albumRevision { hasUnsavedAlbums = false; albumSaveError = nil }
            } catch { albumSaveError = "Album non salvati: \(error.localizedDescription)"; return false }
        }
        return true
    }
    func showAlbum(_ id: UUID) {
        guard let album = library.album(id), let dependencies else { return }
        let previous = selected?.id, previousIndex = activeAlbumID == id ? index : 0
        activeAlbumID = id; frame = nil; isOpening = true; error = nil
        folderRequest &+= 1
        let request = folderRequest
        let context = URL(string: "photor-album://\(UUID().uuidString)")!
        catalogContext = context
        Task {
            let resolved = await Task.detached(priority: .userInitiated) { AlbumLibrary.resolve(album) }.value
            guard request == folderRequest else { return }
            missingAlbumPhotos = resolved.missing
            let selection = resolved.photos.first(where: { $0.id == previous })?.id
                ?? (resolved.photos.isEmpty ? nil : resolved.photos[min(previousIndex, resolved.photos.count - 1)].id)
            pendingSelection = selection
            await dependencies.pipeline.setCatalog(resolved.photos, context: context, selected: selection)
        }
    }
    func showFolder() {
        guard let folder, let dependencies else {
            folderRequest &+= 1
            let context = URL(string: "photor-empty://\(UUID().uuidString)")!
            catalogContext = context; pendingSelection = nil
            activeAlbumID = nil; missingAlbumPhotos = 0; assets = []; index = 0; frame = nil; isLoading = false; isOpening = false
            Task { await self.dependencies?.pipeline.setCatalog([], context: context) }
            return
        }
        let selection = selected?.id, previousIndex = index
        activeAlbumID = nil; missingAlbumPhotos = 0; isOpening = true; frame = nil
        folderRequest &+= 1
        let request = folderRequest
        let context = URL(string: "photor-folder://\(UUID().uuidString)")!
        catalogContext = context
        Task {
            do {
                let photos = try await Task.detached(priority: .userInitiated) { try FolderCatalog().scan(folder) }.value
                guard request == folderRequest else { return }
                pendingSelection = photos.first(where: { $0.id == selection })?.id
                    ?? (photos.isEmpty ? nil : photos[min(previousIndex, photos.count - 1)].id)
                await dependencies.pipeline.setCatalog(photos, context: context, selected: pendingSelection)
            } catch {
                guard request == folderRequest else { return }
                self.error = error.localizedDescription; isOpening = false; isLoading = false
            }
        }
    }
}
