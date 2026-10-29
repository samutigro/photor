import AppKit

@MainActor
final class FolderAccess {
    private var active: URL?
    func choose(title: String = "Scegli una cartella di foto", prompt: String = "Apri cartella") async -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = prompt
        panel.canCreateDirectories = true
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
    func activate(_ url: URL, remember: Bool = true) {
        active?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        active = url
        if remember, let bookmark = try? url.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "lastFolderBookmark")
        }
    }
    func remembered() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "lastFolderBookmark") else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
