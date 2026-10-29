import SwiftUI
import AppKit
import PhotorCore
import PhotorRendering

@MainActor
final class ViewerModel: ObservableObject {
    @Published var assets: [PhotoAsset] = []
    @Published var index = 0
    @Published var folder: URL?
    @Published var frame: TextureFrame?
    @Published var status: PipelineStatus?
    @Published var configuration = ViewerSettings.load()
    @Published var error: String?
    @Published var isLoading = false
    @Published var isOpening = false
    @Published var zoom = 1.0
    @Published var settingsPresented = false
    @Published var pressureNotice = false
    let dependencies: AppDependencies?
    private let folderAccess = FolderAccess()
    private var eventTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var navigation: UInt64 = 0
    var folderRequest: UInt64 = 0
    var catalogContext: URL?
    var pendingSelection: PhotoID?
    var folderAssets: [PhotoAsset] = []
    let albumStore: AlbumStore
    var albumRevision: UInt64 = 0
    @Published var library = AlbumLibrary()
    @Published var libraryReady = false
    @Published var hasUnsavedAlbums = false
    @Published var albumSaveError: String?
    @Published var albumManagerPresented = false
    @Published var activeAlbumID: UUID?
    @Published var notice: String?
    @Published var missingAlbumPhotos = 0
    @Published var isGrid = false
    @Published var gridScrollRequest = 0
    @Published var jumpPresented = false
    @Published var pendingTrash: PhotoAsset?
    @Published var isFileOperationRunning = false
    @Published var transferDraft: AlbumTransferRequest?
    @Published var transferProgress = 0
    @Published var transferTotal = 0
    @Published var transferReport: TransferReport?
    var transferCancellation: CancellationFlag?
    private var started = false
    weak var canvas: PhotoMetalView?
    var selected: PhotoAsset? { assets.indices.contains(index) ? assets[index] : nil }
    var counter: String { assets.isEmpty ? "0 / 0" : "\(index + 1) / \(assets.count)" }

    init(libraryURL: URL = AlbumStore.defaultURL) {
        albumStore = AlbumStore(url: libraryURL)
        do { dependencies = try AppDependencies(configuration: ViewerSettings.load()) }
        catch { dependencies = nil; self.error = error.localizedDescription }
        Task { await loadAlbums() }
        if let dependencies {
            eventTask = Task { [weak self, pipeline = dependencies.pipeline] in
                await pipeline.startMemoryMonitoring()
                for await event in pipeline.events {
                    guard !Task.isCancelled else { break }
                    self?.consume(event)
                }
            }
        }
    }

    func startup() {
        guard !started else { return }
        started = true
        let arguments = CommandLine.arguments
        if let option = arguments.firstIndex(of: "--folder"), arguments.indices.contains(option + 1) {
            open(URL(fileURLWithPath: arguments[option + 1]), remember: false)
        } else if !arguments.contains("--ui-test"), !arguments.contains("--features-test"), let remembered = folderAccess.remembered() { open(remembered) }
    }
    func chooseFolder() {
        guard !isFileOperationRunning else { return }
        Task { if let url = await folderAccess.choose() { open(url) } }
    }
    func open(_ url: URL, remember: Bool = true) {
        guard !isFileOperationRunning else { return }
        guard let dependencies else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "Scegli una cartella, non un singolo file."; return
        }
        folderAccess.activate(url, remember: remember)
        dependencies.presentations.clear()
        activeAlbumID = nil; missingAlbumPhotos = 0; pendingSelection = nil; folderAssets = []
        catalogContext = url
        frame = nil; assets = []; index = 0; error = nil
        isOpening = true; isLoading = true; folder = url
        folderRequest &+= 1
        let request = folderRequest
        Task {
            await dependencies.textures.clear()
            await dependencies.thumbnails.clear()
            guard request == folderRequest else { return }
            await dependencies.pipeline.open(url)
        }
    }
    func move(_ delta: Int) {
        guard !isOpening else { return }
        select(index + delta)
    }
    func select(_ requested: Int) {
        guard let dependencies, !assets.isEmpty, !isOpening, !isFileOperationRunning else { return }
        let next = min(assets.count - 1, max(0, requested))
        guard next != index else { return }
        index = next; frame = dependencies.presentations.frame(for: assets[next]); error = nil; isLoading = frame == nil
        Task { await dependencies.pipeline.select(next) }
    }
    func fit() { if let canvas { dependencies?.renderer.fit(in: canvas) } }
    func toggleGrid() {
        guard !isFileOperationRunning else { return }
        isGrid.toggle()
        Task { await dependencies?.pipeline.setGridMode(isGrid) }
    }
    func openPhoto(_ photo: PhotoAsset) {
        guard !isFileOperationRunning else { return }
        guard let position = assets.firstIndex(where: { $0.id == photo.id }) else { return }
        select(position)
        if isGrid { toggleGrid() }
    }
    func jump(to number: Int) -> Bool {
        guard number >= 1, number <= assets.count else { return false }
        select(number - 1); gridScrollRequest &+= 1; return true
    }
    func actualSize() { if let canvas { dependencies?.renderer.actualSize(in: canvas) } }
    func retry() { error = nil; Task { await dependencies?.pipeline.retry() } }
    func apply(_ value: ViewerConfiguration) {
        configuration = value; pressureNotice = false; ViewerSettings.save(value)
        dependencies?.presentations.clear(keeping: selected?.id)
        Task {
            await dependencies?.textures.clear(keeping: selected?.id)
            await dependencies?.pipeline.configure(value)
        }
    }
    func updatePixelSize(_ size: Int) {
        guard size > 0 else { return }
        let bucket = [2048, 3072, 4096, 5120, 6144, 8192].first(where: { $0 >= size }) ?? 8192
        guard bucket != configuration.screenMaxPixel else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.configuration.screenMaxPixel = bucket
            await self.dependencies?.pipeline.setScreenMaxPixel(bucket)
        }
    }

    private func consume(_ event: PipelineEvent) {
        switch event {
        case .catalog(let photos, let url):
            guard catalogContext == url else { return }
            assets = photos
            index = pendingSelection.flatMap { id in photos.firstIndex { $0.id == id } } ?? 0
            pendingSelection = nil
            if activeAlbumID == nil { folderAssets = photos }
            isOpening = false; isLoading = !photos.isEmpty && frame?.key.photo != selected?.id
        case .selected(let position, let token):
            guard position == index else { return }
            navigation = token
            Task { await dependencies?.textures.setFocus(selected?.id) }
        case .display(let image, let token):
            guard token == navigation, image.key.photo == selected?.id else { return }
            prepare(image, token: token)
        case .warm(let image):
            guard let dependencies else { return }
            Task {
                if let texture = try? await dependencies.textures.frame(for: image),
                   let position = assets.firstIndex(where: { $0.id == texture.key.photo && $0.revision == texture.key.revision }), abs(position - index) <= 2 {
                    dependencies.presentations.insert(texture)
                    status = await dependencies.pipeline.snapshot()
                }
            }
        case .status(let value): status = value
        case .failure(let id, let message):
            if id == nil || id == selected?.id { error = message; isOpening = false; isLoading = false }
        case .memoryPressure:
            pressureNotice = true
            dependencies?.presentations.clear(keeping: selected?.id)
            Task {
                await dependencies?.textures.clear(keeping: selected?.id)
                await dependencies?.thumbnails.clear()
            }
        }
    }
    private func prepare(_ image: CachedImage, token: UInt64) {
        guard let dependencies else { return }
        Task {
            do {
                let texture = try await dependencies.textures.frame(for: image)
                guard token == navigation, texture.key.photo == selected?.id,
                      texture.key.revision == selected?.revision else { return }
                if frame?.key.representation.isFull == true && !texture.key.representation.isFull { return }
                dependencies.presentations.insert(texture)
                frame = texture; isLoading = false; error = nil
                status = await dependencies.pipeline.snapshot()
            } catch {
                guard token == navigation, image.key.photo == selected?.id else { return }
                if frame == nil { self.error = error.localizedDescription; isLoading = false }
            }
        }
    }
}
