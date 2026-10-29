import SwiftUI
import PhotorCore

struct PhotoGrid: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 230), spacing: 12)], spacing: 14) {
                    ForEach(Array(model.assets.enumerated()), id: \.element.id) { position, photo in
                        ThumbnailCell(photo: photo, position: position, selected: model.selected?.id == photo.id,
                            albums: model.library.albums.filter { $0.contains(photo) }, cache: model.dependencies?.thumbnails,
                            open: { model.openPhoto(photo) })
                            .id(photo.id)
                            .contextMenu {
                                Button("Apri foto") { model.openPhoto(photo) }
                                ForEach(model.library.albums) { album in
                                    Button { model.toggleAlbum(album.id, photo: photo) } label: {
                                        Label("\(album.contains(photo) ? "Rimuovi da" : "Aggiungi a") \(album.name)", systemImage: album.symbol)
                                    }
                                }
                                Divider()
                                Button("Sposta nel Cestino", role: .destructive) { model.requestTrash(photo) }
                            }
                    }
                }.padding(16)
            }
            .onAppear { if let id = model.selected?.id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: model.gridScrollRequest) { _, _ in
                if let id = model.selected?.id { proxy.scrollTo(id, anchor: .center) }
            }
        }.accessibilityIdentifier("photoGrid")
    }
}

private struct ThumbnailCell: View {
    let photo: PhotoAsset
    let position: Int
    let selected: Bool
    let albums: [PhotoAlbum]
    let cache: ThumbnailCache?
    let open: () -> Void
    @ViewState<CachedImage?> private var frame: CachedImage?
    @ViewState<Bool> private var failed = false
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                Color(white: 0.12).aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let frame {
                            GeometryReader { geometry in
                                Image(decorative: frame.decoded.image, scale: 1)
                                    .resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            }
                        } else if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                        else { ProgressView().controlSize(.small) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !albums.isEmpty {
                            HStack(spacing: 4) { ForEach(albums) { Image(systemName: $0.symbol + ".fill") } }
                                .font(.caption).foregroundStyle(.yellow).padding(6).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6)).padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
                HStack(spacing: 6) {
                    Text("\(position + 1)").monospacedDigit().foregroundStyle(.secondary)
                    Text(photo.name).lineLimit(1).truncationMode(.middle)
                }.font(.caption)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Foto \(position + 1), \(photo.name)")
            .task(id: CacheKey(asset: photo, representation: .screen(maxPixel: 512))) {
                failed = false
                do {
                    let loaded = try await cache?.image(for: photo)
                    guard !Task.isCancelled else { return }
                    frame = loaded
                } catch { if !Task.isCancelled { failed = true } }
            }
            .onDisappear { frame = nil }
    }
}

struct JumpToPhotoView: View {
    @ObservedObject var model: ViewerModel
    @ViewState<String> private var number = ""
    @ViewState<Bool> private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vai alla foto").font(.headline)
            HStack {
                TextField("1…\(model.assets.count)", text: $number).frame(width: 120).focused($focused).onSubmit(jump)
                Button("Vai", action: jump)
            }
            if invalid { Text("Inserisci un numero tra 1 e \(model.assets.count).").font(.caption).foregroundStyle(.orange) }
        }.padding(20).onAppear { number = "\(model.index + 1)"; focused = true }
    }
    private func jump() {
        guard let value = Int(number), model.jump(to: value) else { invalid = true; return }
        model.jumpPresented = false
    }
}
