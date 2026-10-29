import Foundation
import PhotorCore

struct FileTests {
    func transferCollisionCancellationAndFailure() async throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        for folder in [source, target] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }
        for name in ["1.JPG", "2.RAF", "3.JPG"] { try Data(name.utf8).write(to: source.appendingPathComponent(name)) }
        let assets = try FolderCatalog().scan(source), service = PhotoFileService()
        try Data("preserve".utf8).write(to: target.appendingPathComponent("1.JPG"))
        let copy = try await service.transfer(assets, to: target, mode: .copy)
        try expect(copy.successes.count == 3 && copy.failures.isEmpty)
        try expect(copy.successes[0].destination.lastPathComponent == "1 (2).JPG")
        let unchanged = try Data(contentsOf: target.appendingPathComponent("1.JPG"))
        try expect(unchanged == Data("preserve".utf8))
        for item in copy.successes {
            let a = try Data(contentsOf: item.source), b = try Data(contentsOf: item.destination)
            try expect(a == b)
        }
        let cancellation = CancellationFlag()
        let partial = try await service.transfer(assets, to: target, mode: .move, cancellation: cancellation) { _ in cancellation.cancel() }
        try expect(partial.successes.count == 1 && partial.cancelled)
        try expect(!fm.fileExists(atPath: assets[0].url.path))
        try expect(fm.fileExists(atPath: assets[1].url.path))
        let failure = try await service.transfer(assets, to: target, mode: .move)
        try expect(failure.successes.count == 2 && failure.failures.count == 1)
        let moved = try FolderCatalog().scan(target)
        let same = try await service.transfer([moved[0]], to: target, mode: .move)
        try expect(same.successes.isEmpty && same.failures.count == 1)
        let changed = moved[0]
        try Data("changed size".utf8).write(to: changed.url)
        do { _ = try service.trash(changed); throw CheckFailure(description: "Cestinamento di una versione cambiata") }
        catch PhotoFileError.changed {}
        try expect(fm.fileExists(atPath: changed.url.path))
    }
}
