import AppKit
import ImageIO
import UniformTypeIdentifiers
import PhotorCore

/// Destructive checks only ever operate on these freshly generated fixtures.
@MainActor enum FeatureSmokeCheck {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotorFeature-\(UUID().uuidString)")
    static func run(_ model: ViewerModel) async -> Bool {
        let fm = FileManager.default, source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        var trashed: TrashResult?
        defer {
            if let item = trashed, let location = item.trashed, fm.fileExists(atPath: location.path) { try? fm.moveItem(at: location, to: item.original) }
            try? fm.removeItem(at: root)
        }
        do {
            for folder in [source, target] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
            let image = try fixtureJPEG()
            for index in 1...1005 { try image.write(to: source.appendingPathComponent(String(format: "Photo%04d.JPG", index))) }
            try await wait("archivio album") { model.libraryReady }
            model.open(source, remember: false)
            try await wait("1005 foto") { !model.isOpening && model.assets.count == 1005 && model.frame != nil }
            let first = model.assets[0], second = model.assets[1], thousandth = model.assets[999]
            let customID = model.library.customAlbums[0].id
            for asset in [first, second, thousandth] { model.toggleAlbum(PhotoAlbum.favoritesID, photo: asset) }
            for asset in [first, thousandth] { model.toggleAlbum(customID, photo: asset) }
            for name in ["Viaggio", "Stampa", "Famiglia"] { model.addAlbum(name) }
            model.renameAlbum(customID, to: "Da stampare")
            try check(await model.flushAlbums(), "salvataggio")
            let loaded = try await AlbumStore(url: model.albumStore.url).load()
            try check(loaded == model.library && loaded.customAlbums.count == 4, "persistenza album")
            model.albumManagerPresented = true
            try await wait("gestione album visibile") { mainWindow?.attachedSheet != nil }
            try await Task.sleep(for: .milliseconds(200))
            try snapshot("photor-albums-check.png", sheet: true)
            model.albumManagerPresented = false
            try await wait("chiusura gestione album") { mainWindow?.attachedSheet == nil }
            model.showAlbum(PhotoAlbum.favoritesID)
            try await wait("apertura preferiti") { !model.isOpening && model.assets.count == 3 }
            model.select(2); model.toggleAlbum(PhotoAlbum.favoritesID)
            try await wait("rimozione dai preferiti") { !model.isOpening && model.assets.count == 2 }
            try check(model.selected?.id == second.id, "selezione successiva alla rimozione")
            print("PASS FUNZIONI: preferiti, quattro album, nomi, persistenza e selezione dopo rimozione")
            model.showFolder()
            try await wait("ritorno cartella") { !model.isOpening && model.assets.count == 1005 }
            let beforeShortcut = model.library.album(PhotoAlbum.favoritesID)!.paths.count
            for expected in [beforeShortcut - 1, beforeShortcut] {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                    windowNumber: mainWindow?.windowNumber ?? 0, context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1)!
                try check(NSApp.mainMenu?.performKeyEquivalent(with: event) == true, "scorciatoia ⌘S")
                try check(model.library.album(PhotoAlbum.favoritesID)!.paths.count == expected, "effetto scorciatoia ⌘S")
            }
            model.toggleGrid()
            try await Task.sleep(for: .milliseconds(300))
            try check(model.jump(to: 1000), "salto 1000")
            try check(model.counter == "1000 / 1005" && model.selected?.id == thousandth.id, "indice griglia")
            try check(!model.jump(to: 0) && !model.jump(to: 1006), "limiti salto")
            try await Task.sleep(for: .milliseconds(800))
            let counts = await model.dependencies!.thumbnails.counts()
            try check(counts.cached > 0 && counts.cached < 200 && counts.active <= 2, "miniature visibili e worker limitati")
            try snapshot("photor-grid-check.png")
            model.openPhoto(thousandth)
            try await wait("apertura dalla griglia") { !model.isGrid && model.frame?.key.photo == thousandth.id }
            print("PASS FUNZIONI: griglia 1005 elementi, miniature limitate, salto 1000 e apertura foto")
            model.showAlbum(customID)
            try await wait("album da esportare") { !model.isOpening && model.assets.count == 2 }
            let exports = model.assets
            model.requestTransfer()
            try await wait("trasferimento visibile") { mainWindow?.attachedSheet != nil }
            try await Task.sleep(for: .milliseconds(200))
            try snapshot("photor-transfer-check.png", sheet: true)
            let copied = await model.transfer(exports, to: target, mode: .copy)
            try check(copied?.successes.count == 2 && copied?.failures.isEmpty == true, "copia album")
            for asset in exports { try check(fm.fileExists(atPath: asset.url.path), "originale dopo copia") }
            try await wait("aggiornamento dopo copia") { !model.isOpening }
            let moved = await model.transfer(exports, to: target, mode: .move)
            try check(moved?.successes.count == 2 && moved?.failures.isEmpty == true, "spostamento album")
            for item in moved!.successes {
                try check(item.destination.lastPathComponent.contains("(2)"), "collisione nomi")
                try check(!fm.fileExists(atPath: item.source.path), "rimozione origine dopo spostamento")
                try check(model.library.album(customID)!.paths.contains(item.destination.path), "aggiornamento percorsi")
            }
            let updated = try await AlbumStore(url: model.albumStore.url).load()
            try check(updated == model.library, "persistenza dei nuovi percorsi")
            model.transferDraft = nil
            try await wait("aggiornamento dopo spostamento") { !model.isOpening && model.assets.allSatisfy { $0.url.deletingLastPathComponent().resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path } }
            print("PASS FUNZIONI: copia e spostamento album, omonimi preservati e percorsi salvati")
            model.showFolder()
            try await wait("cartella dopo spostamento") { !model.isOpening && model.assets.count == 1003 }
            model.select(0)
            try check(model.selected?.id == second.id, "selezione per cestino")
            trashed = await model.trash(second)
            try check(trashed?.trashed != nil && !fm.fileExists(atPath: second.url.path), "Cestino nativo")
            try await wait("cartella dopo cestino") { !model.isOpening && model.assets.count == 1002 }
            try check(model.library.albums.allSatisfy { !$0.paths.contains(second.id.path) }, "rimozione da tutti gli album")
            try check(model.counter == "1 / 1002", "contatore dopo cestino")
            print("PASS FUNZIONI: Cestino macOS, pulizia album e selezione della foto successiva")
            return true
        } catch {
            print("FAIL FUNZIONI: \(error) · foto=\(model.assets.count) apertura=\(model.isOpening) frame=\(model.frame != nil) errore=\(model.error ?? "nessuno")")
            if let budget = model.dependencies?.budget { print("BUDGET: \(budget.snapshot)") }
            return false
        }
    }
    private static func fixtureJPEG() throws -> Data {
        let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.13, green: 0.55, blue: 0.75, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        context.setFillColor(CGColor(red: 0.9, green: 0.65, blue: 0.2, alpha: 1)); context.fillEllipse(in: CGRect(x: 80, y: 90, width: 100, height: 100))
        let data = NSMutableData(), destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try check(CGImageDestinationFinalize(destination), "creazione JPEG temporaneo")
        return data as Data
    }
    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.styleMask.contains(.titled) && $0.frame.width >= 760 } }
    private static func snapshot(_ name: String, sheet: Bool = false) throws {
        let window = sheet ? mainWindow?.attachedSheet : mainWindow
        guard let content = window?.contentView,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw Failure.failed("Cattura finestra") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/\(name)"))
    }
    private static func wait(_ name: String, until predicate: () -> Bool) async throws {
        for _ in 0..<300 { if predicate() { return }; try await Task.sleep(for: .milliseconds(50)) }
        throw Failure.failed("Timeout: \(name)")
    }
    private static func check(_ value: Bool, _ name: String) throws { if !value { throw Failure.failed(name) } }
    private enum Failure: Error { case failed(String) }
}
