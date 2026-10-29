import SwiftUI

struct ViewerView: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 16) {
                AlbumMenu(model: model)
                Button(action: model.toggleGrid) { Label(model.isGrid ? "Foto" : "Griglia", systemImage: model.isGrid ? "photo" : "square.grid.3x3") }
                    .help("Foto / griglia · ⌘G").disabled(model.assets.isEmpty)
                Button("Vai alla foto…") { model.jumpPresented = true }.disabled(model.assets.isEmpty)
                    .popover(isPresented: $model.jumpPresented) { JumpToPhotoView(model: model) }
                if model.activeAlbumID != nil {
                    Button { model.requestTransfer() } label: { Label("Trasferisci album…", systemImage: "square.and.arrow.up") }
                        .disabled(model.assets.isEmpty || model.isOpening)
                }
                Spacer()
                if !model.isGrid {
                    Button("Adatta", action: model.fit).disabled(model.frame == nil)
                    Button("100%", action: model.actualSize).disabled(model.frame == nil)
                }
            }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 8).disabled(model.isFileOperationRunning)
            if let message = model.albumSaveError {
                HStack { Text(message); Button("Riprova") { Task { if model.libraryReady { await model.flushAlbums() } else { await model.loadAlbums() } } } }
                    .font(.caption).foregroundStyle(.orange).padding(8)
            }
            if model.missingAlbumPhotos > 0 {
                Text("\(model.missingAlbumPhotos) foto dell’album non sono disponibili sul disco.")
                    .font(.caption).foregroundStyle(.secondary).padding(6)
            }
            if let notice = model.notice {
                HStack {
                    Text(notice).font(.callout).lineLimit(3)
                    Spacer()
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }
                }.padding(.horizontal, 18).padding(.vertical, 8).background(.quaternary)
            }
            ZStack {
                Color(red: 0.085, green: 0.085, blue: 0.10)
                if model.isGrid { PhotoGrid(model: model).id(model.catalogContext) }
                else if model.dependencies != nil { PhotoCanvas(model: model) }
                if model.assets.isEmpty && !model.isOpening {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(.secondary)
                        Text(model.activeAlbumID != nil ? "Questo album è vuoto" : model.folder == nil ? "Le tue foto, al volo." : "Nessuna foto in questa cartella")
                            .font(.system(size: 24, weight: .medium))
                        Text(model.activeAlbumID != nil ? "Aggiungi foto usando le icone in alto a destra." : "JPEG e RAF Fujifilm · Trascina una cartella per iniziare")
                            .foregroundStyle(.secondary)
                        Button("Apri cartella…", action: model.chooseFolder).buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(model.dependencies == nil)
                    }
                }
                if (!model.isGrid && model.isLoading) || model.isOpening {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.isOpening ? "Lettura cartella…" : "Preparazione foto…").font(.callout)
                    }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = model.error {
                    VStack(spacing: 12) {
                        Label(error, systemImage: "exclamationmark.triangle").multilineTextAlignment(.center)
                        HStack {
                            Button("Riprova", action: model.retry)
                            Button("Apri un’altra cartella…", action: model.chooseFolder)
                        }
                    }.padding(20).frame(maxWidth: 440).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 500)
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url); return true
        }
        .sheet(isPresented: $model.settingsPresented) {
            SettingsView(configuration: model.configuration) { model.apply($0) }
        }
        .sheet(isPresented: $model.albumManagerPresented) { AlbumManagerView(model: model) }
        .sheet(item: $model.transferDraft) { request in AlbumTransferView(model: model, request: request) }
        .confirmationDialog("Spostare la foto nel Cestino?", isPresented: Binding(get: { model.pendingTrash != nil }, set: { if !$0 { model.pendingTrash = nil } }), presenting: model.pendingTrash) { photo in
            Button("Sposta nel Cestino", role: .destructive) { Task { await model.trash(photo) } }
        } message: { photo in Text("\(photo.name) verrà rimossa dalla cartella e dagli album. Potrai recuperare il file dal Cestino del Mac.") }
        .onAppear { model.startup() }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button(action: model.chooseFolder) { Image(systemName: "folder") }
                .help("Apri cartella · ⌘O").accessibilityLabel("Apri cartella")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selected?.name ?? "Photor").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(model.collectionTitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button { model.move(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(model.index == 0).help("Foto precedente · ←").accessibilityLabel("Foto precedente")
            Text(model.counter).font(.system(.body, design: .monospaced)).monospacedDigit()
                .frame(minWidth: 85).accessibilityIdentifier("photoCounter")
            Button { model.move(1) } label: { Image(systemName: "chevron.right") }
                .disabled(model.index >= model.assets.count - 1).help("Foto successiva · →").accessibilityLabel("Foto successiva")
            Spacer(minLength: 12)
            AlbumButtons(model: model)
            Button { model.requestTrash() } label: { Image(systemName: "trash") }
                .help("Sposta nel Cestino · ⌘⌫").accessibilityLabel("Sposta nel Cestino")
                .disabled(!model.libraryReady || model.selected == nil || model.isFileOperationRunning || model.isOpening)
            Button { model.settingsPresented = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("Impostazioni cache").accessibilityLabel("Impostazioni cache")
        }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 12).disabled(model.isFileOperationRunning)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private var footer: some View {
        HStack(spacing: 12) {
            if let frame = model.frame {
                Text("\(frame.sourceSize.width) × \(frame.sourceSize.height)")
                Text(frame.embeddedPreview ? "Anteprima RAW" : (model.selected?.isRAW == true ? "RAW sviluppato" : "JPEG / immagine"))
                Text("\(Int((model.zoom * 100).rounded()))%")
            } else { Text("← → Sfoglia   ·   Pinch Zoom   ·   Doppio clic 100%") }
            Spacer()
            if model.pressureNotice {
                Image(systemName: "memorychip").foregroundStyle(.orange).help("Cache ridotta perché macOS ha segnalato pressione sulla memoria.")
            }
            if let status = model.status {
                if status.running > 0 { ProgressView().controlSize(.mini) }
                Text("Pronte \(status.cachedPhotos)/\(model.assets.count) · Dettaglio \(status.fullPhotos)")
                Text(String(format: "RAM %.1f / %.0f GiB", Double(status.memory.used) / 1_073_741_824,
                    Double(status.memory.limit) / 1_073_741_824))
                    .help("Immagini, texture e riserve dei lavori attivi. Non è la memoria totale del processo.")
            }
        }.font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            .padding(.horizontal, 18).frame(height: 34)
    }
}
