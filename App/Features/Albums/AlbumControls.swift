import SwiftUI
import PhotorCore

struct AlbumButtons: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        HStack(spacing: 12) {
            ForEach(model.albumButtons) { album in
                let marked = model.selected.map { album.contains($0) } ?? false
                Button { model.toggleAlbum(album.id) } label: {
                    Image(systemName: album.symbol + (marked ? ".fill" : ""))
                        .foregroundStyle(marked ? Color.yellow : Color.secondary)
                }
                .disabled(model.selected == nil || !model.libraryReady || model.isOpening)
                .help("\(marked ? "Rimuovi da" : "Aggiungi a") \(album.name) · \(model.albumShortcut(album))")
                .accessibilityLabel("\(album.name): \(marked ? "presente" : "assente")")
                .contextMenu { Button("Apri \(album.name)") { model.showAlbum(album.id) } }
            }
        }
    }
}

struct AlbumMenu: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        Menu {
            Button { model.showFolder() } label: { Label("Cartella aperta", systemImage: "folder") }
                .disabled(model.folder == nil)
            Divider()
            ForEach(model.library.albums) { album in
                Button { model.showAlbum(album.id) } label: { Label("\(album.name) (\(album.paths.count))", systemImage: album.symbol) }
            }
            Divider()
            Button("Gestisci album…") { model.albumManagerPresented = true }
        } label: {
            Label(model.collectionTitle, systemImage: model.activeAlbum?.symbol ?? "folder")
                .lineLimit(1).frame(maxWidth: 220, alignment: .leading)
        }.disabled(!model.libraryReady)
    }
}

struct AlbumManagerView: View {
    @ObservedObject var model: ViewerModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var newName = ""
    @ViewState<PhotoAlbum?> private var pendingRemoval: PhotoAlbum?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("I tuoi album").font(.title2.bold())
            Text("La stella è per i Preferiti. Puoi aggiungere fino a quattro album personalizzati, anche con foto di cartelle diverse.")
                .font(.callout).foregroundStyle(.secondary)
            Label("Preferiti · ⌘S", systemImage: "star.fill").foregroundStyle(.yellow)
            ForEach(model.library.customAlbums) { album in
                AlbumNameRow(album: album, shortcut: model.albumShortcut(album), rename: { model.renameAlbum(album.id, to: $0) }, remove: { pendingRemoval = album })
            }
            if model.library.customAlbums.count < 4 {
                HStack {
                    TextField("Nome del nuovo album", text: $newName)
                    Button("Aggiungi") { model.addAlbum(newName); if model.notice == nil { newName = "" } }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let message = model.notice ?? model.albumSaveError { Text(message).foregroundStyle(.orange).font(.callout) }
            HStack { Spacer(); Button("Fine") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 520)
            .confirmationDialog("Rimuovere questo album?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), presenting: pendingRemoval) { album in
                Button("Rimuovi \(album.name)", role: .destructive) { model.removeAlbum(album.id); pendingRemoval = nil }
            } message: { _ in Text("Le fotografie rimangono nelle loro cartelle.") }
    }
}

private struct AlbumNameRow: View {
    let album: PhotoAlbum
    let shortcut: String
    let rename: (String) -> Void
    let remove: () -> Void
    @ViewState<String> private var name: String
    init(album: PhotoAlbum, shortcut: String, rename: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.album = album; self.shortcut = shortcut; self.rename = rename; self.remove = remove
        _name = State(initialValue: album.name)
    }
    var body: some View {
        HStack {
            Image(systemName: album.symbol).frame(width: 20)
            TextField("Nome album", text: $name).onSubmit { rename(name) }
            Text(shortcut).foregroundStyle(.secondary).frame(width: 40)
            Button("Salva") { rename(name) }.disabled(name == album.name)
            Button(action: remove) { Image(systemName: "minus.circle") }.help("Rimuovi album")
        }
    }
}
