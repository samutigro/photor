import SwiftUI
import PhotorCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var memory: Double
    @State private var radius: Int
    @State private var fill: Bool
    private let original: ViewerConfiguration
    let apply: (ViewerConfiguration) -> Void
    init(configuration: ViewerConfiguration, apply: @escaping (ViewerConfiguration) -> Void) {
        original = configuration; self.apply = apply
        _memory = State(initialValue: Double(configuration.memoryLimit) / 1_073_741_824)
        _radius = State(initialValue: configuration.prefetchRadius)
        _fill = State(initialValue: configuration.fillFolder)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Cache in memoria").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text("Budget: \(Int(memory)) GiB").monospacedDigit()
                Slider(value: $memory, in: 4...32, step: 1)
                Text("Il budget include immagini, texture e riserve per la decodifica. macOS può richiederne la riduzione.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Stepper("Precarica \(radius) foto prima e dopo", value: $radius, in: 10...300, step: 10)
            Toggle("Prepara anche il resto della cartella quando c’è spazio", isOn: $fill)
            Text("Dettaglio completo: foto corrente e fino a 5 vicine per lato; per i RAW fino a 1. I file originali restano invariati.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Annulla") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Applica") {
                    var updated = original
                    updated.memoryLimit = Int(memory) * 1_073_741_824
                    updated.prefetchRadius = radius; updated.fillFolder = fill
                    apply(updated); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
    }
}
