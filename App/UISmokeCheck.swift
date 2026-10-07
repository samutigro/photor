import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum UISmokeCheck {
    static func run(_ model: ViewerModel) async -> Bool {
        do {
            try await wait("prima foto") { model.frame != nil && model.canvas?.window != nil }
            guard model.assets.count >= 2, let dependencies = model.dependencies, let canvas = model.canvas else {
                throw CheckError.failed("Servono almeno due immagini per la prova UI")
            }
            print("PASS UI: finestra aperta, prima immagine e contatore \(model.counter)")
            model.move(1)
            try await wait("seconda foto completa") { model.frame?.key.photo == model.selected?.id && model.frame?.key.representation.isFull == true }
            guard model.counter == "2 / \(model.assets.count)" else { throw CheckError.failed("Contatore errato") }
            model.actualSize()
            guard abs(dependencies.renderer.actualPixelScale(in: canvas) - 1) < 0.01 else { throw CheckError.failed("Zoom 100% errato") }
            let oldZoom = dependencies.renderer.viewport.zoom
            dependencies.renderer.viewport.magnify(by: 1.5, anchor: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), bounds: canvas.bounds.size)
            dependencies.renderer.changed(in: canvas)
            guard dependencies.renderer.viewport.zoom > oldZoom else { throw CheckError.failed("Magnificazione errata") }
            model.fit()
            guard dependencies.renderer.viewport.zoom == 1 else { throw CheckError.failed("Adatta errato") }
            print("PASS UI: navigazione, contatore, zoom 100%, magnifica e adatta")
            try await wait("precaching completo") { (model.status?.fullPhotos ?? 0) >= 2 }
            try await Task.sleep(for: .milliseconds(350))
            model.move(-1)
            guard model.frame?.key.photo == model.selected?.id else { throw CheckError.failed("Foto vicina non disponibile sincronicamente") }
            print("PASS UI: ritorno alla foto precedente dalla cache nello stesso turno UI")
            for _ in 0..<20 { model.move(1); model.move(-1) }
            try await wait("navigazione rapida") { model.frame?.key.photo == model.assets[0].id && !model.isLoading }
            try await Task.sleep(for: .milliseconds(500))
            guard model.frame?.key.photo == model.selected?.id else { throw CheckError.failed("Risultato obsoleto mostrato") }
            model.fit()
            try await Task.sleep(for: .milliseconds(150))
            try await wait("presentazione GPU nella finestra") { dependencies.renderer.lastPresentedKey?.photo == model.selected?.id }
            let rendered = try dependencies.renderer.snapshot()
            let output = URL(fileURLWithPath: "/private/tmp/photor-render-check.png")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CheckError.failed("PNG diagnostico") }
            CGImageDestinationAddImage(destination, rendered, nil)
            guard CGImageDestinationFinalize(destination) else { throw CheckError.failed("Scrittura PNG diagnostico") }
            if let content = canvas.window?.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/photor-window-check.png"))
            }
            print("PASS UI: 40 cambi rapidi, risultato corrente corretto, rendering GPU esportato")
            return true
        } catch { print("FAIL UI: \(error)"); return false }
    }
    private static func wait(_ name: String, until predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CheckError.failed("Timeout: \(name)")
    }
    private enum CheckError: Error { case failed(String) }
}
