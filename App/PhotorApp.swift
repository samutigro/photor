import SwiftUI
import AppKit

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
final class PhotorAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: ViewerModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = ViewerModel()
        self.model = model
        makeMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Photor"
        window.minSize = NSSize(width: 760, height: 540)
        window.contentView = NSHostingView(rootView: ViewerView(model: model))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PhotorMainWindow")
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
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model?.open(url) }
    }
    @objc private func openFolder() { model?.chooseFolder() }
    @objc private func settings() { model?.settingsPresented = true }
    @objc private func previous() { model?.move(-1) }
    @objc private func next() { model?.move(1) }
    @objc private func fit() { model?.fit() }
    @objc private func actualSize() { model?.actualSize() }

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
        let windows = NSMenu(title: "Finestra")
        windows.addItem(withTitle: "Riduci a icona", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let fullscreen = windows.addItem(withTitle: "Schermo intero", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        for menu in [app, file, photo, windows] {
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
