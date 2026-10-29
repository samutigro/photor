import Foundation

public enum PhotoFileError: Error, LocalizedError {
    case changed(String), notFile(String), invalidDestination, sameFolder
    public var errorDescription: String? {
        switch self {
        case .changed(let name): "\(name) è stato modificato. Riapri la cartella prima di procedere."
        case .notFile(let name): "\(name) non è più un file disponibile."
        case .invalidDestination: "La destinazione deve essere una cartella esistente."
        case .sameFolder: "Il file si trova già nella cartella di destinazione."
        }
    }
}

public struct TrashResult: Sendable {
    public let original: URL
    public let trashed: URL?
}

public enum PhotoTransferMode: String, Sendable, CaseIterable { case copy, move }
public struct TransferredPhoto: Sendable {
    public let source: URL
    public let destination: URL
}
public struct TransferFailure: Sendable {
    public let source: URL
    public let message: String
}
public struct TransferUpdate: Sendable {
    public let processed: Int
    public let total: Int
    public let success: TransferredPhoto?
    public let failure: TransferFailure?
}
public struct TransferReport: Sendable {
    public var successes: [TransferredPhoto] = []
    public var failures: [TransferFailure] = []
    public var cancelled = false
    public init() {}
}

public struct PhotoFileService: Sendable {
    public init() {}
    public func trash(_ asset: PhotoAsset) throws -> TrashResult {
        try validate(asset)
        var destination: NSURL?
        try FileManager.default.trashItem(at: asset.url, resultingItemURL: &destination)
        return TrashResult(original: asset.url, trashed: destination as URL?)
    }
    public func transfer(_ assets: [PhotoAsset], to directory: URL, mode: PhotoTransferMode,
                         cancellation: CancellationFlag = CancellationFlag(),
                         progress: @Sendable (TransferUpdate) async -> Void = { _ in }) async throws -> TransferReport {
        let destination = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw PhotoFileError.invalidDestination }
        var report = TransferReport()
        for (index, asset) in assets.enumerated() {
            if cancellation.isCancelled { report.cancelled = true; break }
            var success: TransferredPhoto?, failure: TransferFailure?
            do {
                try validate(asset)
                if mode == .move, asset.url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == destination.path {
                    throw PhotoFileError.sameFolder
                }
                let target = availableURL(named: asset.name, in: destination)
                // FileManager refuses to overwrite; a concurrent filename collision is reported as a failure.
                if mode == .copy { try FileManager.default.copyItem(at: asset.url, to: target) }
                else { try FileManager.default.moveItem(at: asset.url, to: target) }
                let moved = TransferredPhoto(source: asset.url, destination: target)
                success = moved; report.successes.append(moved)
            } catch {
                let failed = TransferFailure(source: asset.url, message: error.localizedDescription)
                failure = failed; report.failures.append(failed)
            }
            await progress(TransferUpdate(processed: index + 1, total: assets.count, success: success, failure: failure))
        }
        return report
    }
    private func availableURL(named name: String, in directory: URL) -> URL {
        var result = directory.appendingPathComponent(name)
        let original = URL(fileURLWithPath: name), ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var suffix = 2
        while FileManager.default.fileExists(atPath: result.path) {
            result = directory.appendingPathComponent("\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)"))
            suffix += 1
        }
        return result
    }
    func validate(_ asset: PhotoAsset) throws {
        var freshURL = asset.url
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw PhotoFileError.notFile(asset.name) }
        let revision = FileRevision(byteCount: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate ?? .distantPast)
        guard revision == asset.revision else { throw PhotoFileError.changed(asset.name) }
    }
}
