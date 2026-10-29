import SwiftUI
import PhotorCore

struct AlbumTransferView: View {
    @ObservedObject var model: ViewerModel
    let request: AlbumTransferRequest
    @Environment(\.dismiss) private var dismiss
    @ViewState<PhotoTransferMode> private var mode = .copy
    @ViewState<URL?> private var destination: URL?
    @ViewState<Bool> private var confirmMove = false
    @ViewState<Bool> private var started = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Trasferisci \(request.name)").font(.title2.bold())
            Text("\(request.photos.count) foto disponibili").foregroundStyle(.secondary)
            Picker("Operazione", selection: $mode) {
                Text("Copia").tag(PhotoTransferMode.copy)
                Text("Sposta").tag(PhotoTransferMode.move)
            }.pickerStyle(.segmented).disabled(started)
            Text(mode == .copy ? "Gli originali rimangono dove sono. Gli album continuano a riferirsi agli originali." : "I file vengono trasferiti e rimossi dalle cartelle di origine. Tutti gli album seguiranno i nuovi percorsi.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text(destination?.path ?? "Scegli la cartella di destinazione").lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Scegli…") {
                    Task { destination = await FolderAccess().choose(title: "Destinazione delle foto", prompt: "Usa questa cartella") }
                }.disabled(started)
            }
            Text("Se un nome esiste già, la nuova foto riceve un suffisso, per esempio “foto (2).JPG”.")
                .font(.caption).foregroundStyle(.secondary)
            if model.isFileOperationRunning {
                ProgressView(value: Double(model.transferProgress), total: Double(max(1, model.transferTotal)))
                Text("\(model.transferProgress) / \(model.transferTotal)").monospacedDigit()
            }
            if let report = model.transferReport {
                Text("\(report.successes.count) completate · \(report.failures.count) errori" + (report.cancelled ? " · annullato" : ""))
                if !report.failures.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                                Text("\(failure.source.lastPathComponent): \(failure.message)").font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }
            } else if started, !model.isFileOperationRunning, let notice = model.notice { Text(notice).foregroundStyle(.orange) }
            if let error = model.albumSaveError { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                if model.isFileOperationRunning {
                    Button("Annulla dopo il file corrente") { model.transferCancellation?.cancel() }
                } else {
                    Button(started ? "Chiudi" : "Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                    if !started {
                        Button(mode == .copy ? "Copia foto" : "Sposta foto") {
                            if mode == .move { confirmMove = true } else { begin() }
                        }.buttonStyle(.borderedProminent).disabled(destination == nil)
                    }
                }
            }
        }.padding(24).frame(width: 520)
            .interactiveDismissDisabled(model.isFileOperationRunning)
            .confirmationDialog("Spostare \(request.photos.count) foto?", isPresented: $confirmMove) {
                Button("Sposta nella destinazione", role: .destructive, action: begin)
            } message: { Text("Le foto completate verranno rimosse dalle cartelle di origine. In caso di annullamento, quelle già spostate restano nella destinazione.") }
    }
    private func begin() {
        guard let destination else { return }
        started = true
        Task { await model.transfer(request.photos, to: destination, mode: mode) }
    }
}
