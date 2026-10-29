import SwiftUI
import AppKit
import PhotorCore

@main
enum EntryPoint {
    @MainActor static func main() {
        setbuf(stdout, nil)
        if let option = CommandLine.arguments.firstIndex(of: "--smoke-test"), CommandLine.arguments.indices.contains(option + 1) {
            Task {
                let success = await SmokeCheck.run(folder: URL(fileURLWithPath: CommandLine.arguments[option + 1]))
                exit(success ? 0 : 1)
            }
            dispatchMain()
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let delegate = PhotorAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class PhotorAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var model: ViewerModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let featureTest = CommandLine.arguments.contains("--features-test")
        let model = ViewerModel(libraryURL: featureTest ? FeatureSmokeCheck.root.appendingPathComponent("albums.json") : AlbumStore.defaultURL)
        self.model = model
        makeMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Photor"
        window.delegate = self
        window.minSize = NSSize(width: 760, height: 540)
        window.contentView = NSHostingView(rootView: ViewerView(model: model))
        window.isReleasedWhenClosed = false
        if !featureTest { window.setFrameAutosaveName("PhotorMainWindow") }
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        model.startup()
        if CommandLine.arguments.contains("--ui-test") {
            Task {
                let success = await UISmokeCheck.run(model)
                exit(success ? 0 : 1)
            }
        }
        if featureTest {
            Task { let success = await FeatureSmokeCheck.run(model); exit(success ? 0 : 1) }
        }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let model, !model.isFileOperationRunning else { return false }
        if [#selector(previous), #selector(next), #selector(fit), #selector(actualSize)].contains(item.action),
           NSApp.keyWindow?.firstResponder is NSTextView { return false }
        switch item.action {
        case #selector(favorite): return model.libraryReady && model.selected != nil && !model.isOpening
        case #selector(customAlbum(_:)): return model.libraryReady && model.selected != nil && !model.isOpening && model.library.customAlbums.indices.contains(item.tag)
        case #selector(trash): return model.libraryReady && model.selected != nil && !model.isOpening
        case #selector(transferAlbum): return model.activeAlbum != nil && !model.assets.isEmpty && !model.isOpening
        case #selector(grid), #selector(jump): return !model.assets.isEmpty && !model.isOpening
        default: return true
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.isFileOperationRunning {
            model.notice = "Attendi la fine dell’operazione o annullala prima di chiudere Photor."
            return .terminateCancel
        }
        guard model.hasUnsavedAlbums else { return .terminateNow }
        Task { NSApp.reply(toApplicationShouldTerminate: await model.flushAlbums()) }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model else { return true }
        guard !model.isFileOperationRunning else { return false }
        if model.hasUnsavedAlbums {
            Task { if await model.flushAlbums() { sender.performClose(nil) } }
            return false
        }
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model?.open(url) }
    }
    @objc private func openFolder() { model?.chooseFolder() }
    @objc private func settings() { model?.settingsPresented = true }
    @objc private func previous() { model?.move(-1) }
    @objc private func next() { model?.move(1) }
    @objc private func fit() { model?.fit() }
    @objc private func actualSize() { model?.actualSize() }
    @objc private func favorite() { model?.toggleAlbum(PhotoAlbum.favoritesID) }
    @objc private func customAlbum(_ sender: NSMenuItem) { model?.toggleCustomAlbum(sender.tag) }
    @objc private func favorites() { if model?.isFileOperationRunning == false { model?.showAlbum(PhotoAlbum.favoritesID) } }
    @objc private func manageAlbums() { if model?.isFileOperationRunning == false { model?.albumManagerPresented = true } }
    @objc private func grid() { if model?.isFileOperationRunning == false { model?.toggleGrid() } }
    @objc private func jump() { if model?.isFileOperationRunning == false { model?.jumpPresented = true } }
    @objc private func trash() { model?.requestTrash() }
    @objc private func transferAlbum() { model?.requestTransfer() }

    private func makeMenus() {
        let bar = NSMenu()
        let app = NSMenu(title: "Photor")
        app.addItem(withTitle: "Informazioni su Photor", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        add("Impostazioni cache…", action: #selector(settings), key: ",", to: app)
        app.addItem(.separator())
        app.addItem(withTitle: "Esci da Photor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File")
        add("Apri cartella…", action: #selector(openFolder), key: "o", to: file)
        file.addItem(withTitle: "Chiudi finestra", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let photo = NSMenu(title: "Foto")
        add("Precedente", action: #selector(previous), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [], to: photo)
        add("Successiva", action: #selector(next), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [], to: photo)
        photo.addItem(.separator())
        add("Adatta alla finestra", action: #selector(fit), key: " ", modifiers: [], to: photo)
        add("Dimensione reale", action: #selector(actualSize), key: "1", modifiers: [], to: photo)
        add("Foto / Griglia", action: #selector(grid), key: "g", to: photo)
        add("Vai alla foto…", action: #selector(jump), key: "j", to: photo)
        photo.addItem(.separator())
        add("Sposta nel Cestino…", action: #selector(trash), key: String(UnicodeScalar(NSDeleteCharacter)!), to: photo)
        let albums = NSMenu(title: "Album")
        add("Aggiungi / rimuovi dai Preferiti", action: #selector(favorite), key: "s", to: albums)
        for index in 0..<4 {
            let item = albums.addItem(withTitle: "Aggiungi / rimuovi dall’album \(index + 1)", action: #selector(customAlbum(_:)), keyEquivalent: "\(index + 1)")
            item.target = self; item.tag = index
        }
        albums.addItem(.separator())
        add("Apri Preferiti", action: #selector(favorites), key: "s", modifiers: [.command, .option], to: albums)
        add("Gestisci album…", action: #selector(manageAlbums), key: "a", modifiers: [.command, .shift], to: albums)
        add("Copia / sposta album…", action: #selector(transferAlbum), key: "e", modifiers: [.command, .shift], to: albums)
        let windows = NSMenu(title: "Finestra")
        windows.addItem(withTitle: "Riduci a icona", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let fullscreen = windows.addItem(withTitle: "Schermo intero", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        for menu in [app, file, photo, albums, windows] {
            let item = NSMenuItem(); item.submenu = menu; bar.addItem(item)
        }
        NSApp.mainMenu = bar; NSApp.windowsMenu = windows
    }
    private func add(_ title: String, action: Selector, key: String,
                     modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
    }
}
