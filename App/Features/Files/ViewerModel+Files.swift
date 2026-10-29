import Foundation
import PhotorCore

struct AlbumTransferRequest: Identifiable {
    let id = UUID()
    let name: String
    let photos: [PhotoAsset]
}

extension ViewerModel {
    func requestTrash(_ photo: PhotoAsset? = nil) {
        guard libraryReady, !isFileOperationRunning, !isOpening else { return }
        pendingTrash = photo ?? selected
    }
    @discardableResult func trash(_ photo: PhotoAsset) async -> TrashResult? {
        guard libraryReady, !isFileOperationRunning else { return nil }
        isFileOperationRunning = true; pendingTrash = nil; notice = nil
        defer { isFileOperationRunning = false }
        await dependencies?.pipeline.pauseBackground(true)
        do {
            let result = try await Task.detached(priority: .userInitiated) { try PhotoFileService().trash(photo) }.value
            library.removePhoto(at: photo.id.path)
            albumsChanged(); _ = await flushAlbums()
            await dependencies?.pipeline.invalidate(photo.id)
            dependencies?.presentations.clear()
            await dependencies?.textures.clear()
            await dependencies?.thumbnails.clear()
            folderAssets.removeAll { $0.id == photo.id }
            notice = "\(photo.name) spostata nel Cestino."
            if let album = activeAlbumID { showAlbum(album) } else { showFolder() }
            return result
        } catch {
            notice = "Cestino: \(error.localizedDescription)"
            await dependencies?.pipeline.pauseBackground(false)
            return nil
        }
    }
    func requestTransfer() {
        guard let album = activeAlbum, !assets.isEmpty, !isOpening, !isFileOperationRunning else { return }
        transferReport = nil; transferProgress = 0; transferTotal = assets.count
        transferDraft = AlbumTransferRequest(name: album.name, photos: assets)
    }
    @discardableResult func transfer(_ photos: [PhotoAsset], to folder: URL, mode: PhotoTransferMode) async -> TransferReport? {
        guard libraryReady, !isFileOperationRunning else { return nil }
        isFileOperationRunning = true; transferReport = nil; notice = nil
        transferProgress = 0; transferTotal = photos.count
        let cancellation = CancellationFlag(); transferCancellation = cancellation
        let accessed = folder.startAccessingSecurityScopedResource()
        defer {
            if accessed { folder.stopAccessingSecurityScopedResource() }
            isFileOperationRunning = false; transferCancellation = nil
        }
        await dependencies?.pipeline.pauseBackground(true)
        await dependencies?.thumbnails.clear()
        do {
            let report = try await Task.detached(priority: .userInitiated) { [self] in
                try await PhotoFileService().transfer(photos, to: folder, mode: mode, cancellation: cancellation) { update in
                    await self.acceptTransfer(update, mode: mode)
                }
            }.value
            transferReport = report
            let verb = mode == .copy ? "copiate" : "spostate"
            notice = "\(report.successes.count) foto \(verb)" + (report.failures.isEmpty ? "." : ", \(report.failures.count) non trasferite.")
            dependencies?.presentations.clear()
            await dependencies?.textures.clear()
            if let album = activeAlbumID { showAlbum(album) } else { showFolder() }
            return report
        } catch {
            notice = error.localizedDescription
            await dependencies?.pipeline.pauseBackground(false)
            return nil
        }
    }
    private func acceptTransfer(_ update: TransferUpdate, mode: PhotoTransferMode) async {
        if mode == .move, let item = update.success {
            library.relocatePhoto(from: item.source.standardizedFileURL.path, to: item.destination.standardizedFileURL.path)
            albumRevision &+= 1; hasUnsavedAlbums = true
            if !(await flushAlbums()) { transferCancellation?.cancel() }
            folderAssets.removeAll { $0.id.path == item.source.standardizedFileURL.path }
            await dependencies?.pipeline.invalidate(PhotoID(url: item.source))
        }
        transferProgress = update.processed
    }
}
