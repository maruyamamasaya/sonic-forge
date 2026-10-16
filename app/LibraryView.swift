import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var library: InstrumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var confirmLoad = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var selected: LibraryEntry? { library.filtered.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up").foregroundStyle(accent)
                Text("Instrument Library").font(.system(size: 22, weight: .medium))
                Spacer()
                if library.busy || model.busy { ProgressView().controlSize(.small) }
                Button("Done") { dismiss() }.buttonStyle(StudioButton())
            }
            HStack {
                TextField("Search instruments", text: $library.query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search instruments")
                Button("Add Files…") { library.addPanel() }.buttonStyle(StudioButton())
                Button("Add Demos") { Task { await library.addDemos() } }.buttonStyle(StudioButton())
            }.disabled(library.busy || model.busy)
            HStack {
                Text("\(library.filtered.count) \(library.filtered.count == 1 ? "instrument" : "instruments")").foregroundStyle(.secondary)
                Spacer()
                Text("Saved files · Original locations").foregroundStyle(.secondary)
            }.font(.system(size: 11))
            if library.filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "pianokeys").font(.system(size: 32)).foregroundStyle(accent)
                    Text(library.entries.isEmpty ? "Your instruments, together" : "No matching instruments")
                    Text(library.entries.isEmpty ? "Add saved instruments, or explore with Add Demos." : "Try another name.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(library.filtered, selection: $selection) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).font(.system(size: 13, weight: .medium))
                            Text(entry.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(entry.available ? (library.previewing == entry.url ? "PREVIEW" : "Ready") : "Missing")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(entry.available ? accent : .secondary)
                    }.padding(.vertical, 8).tag(entry.id)
                }.scrollContentBackground(.hidden).background(.black.opacity(0.15))
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.previewing == nil ? "Select an instrument to preview or load" : "Playing preview · −18 dB")
                    Text(library.previewDescription ?? "Preview keeps your current instrument and edits.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.font(.system(size: 12))
                Spacer()
                Button(library.previewing == nil ? "Preview" : "Stop Preview") {
                    if library.previewing != nil { library.stopPreview() }
                    else if let selected { model.stop(); Task { await library.preview(selected) } }
                }.buttonStyle(StudioButton())
                    .disabled(library.busy || model.busy || (library.previewing == nil && selected?.available != true))
                Button("Load Instrument") {
                    if model.instrumentDirty { confirmLoad = true } else { loadSelected() }
                }.buttonStyle(StudioButton(primary: true))
                    .disabled(selected?.available != true || library.busy || model.busy)
            }
            HStack {
                if let selected {
                    Button("Remove from List") { library.remove(selected); selection = nil }.buttonStyle(.plain)
                        .disabled(library.busy || model.busy)
                    Text("Original file is kept.").foregroundStyle(.secondary)
                }
                Spacer()
            }.font(.system(size: 10))
            if let error = library.error ?? model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).lineLimit(3).help(error)
            }
        }.padding(24).frame(width: 780, height: 570)
            .background(Color(red: 0.075, green: 0.09, blue: 0.105)).preferredColorScheme(.dark)
            .confirmationDialog("Replace unsaved instrument changes?", isPresented: $confirmLoad) {
                Button("Replace Instrument", role: .destructive) { loadSelected() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your current instrument has unsaved changes. Cancel and save it first to keep them.") }
            .onChange(of: selection) { _, _ in library.stopPreview() }
            .onChange(of: library.query) { _, _ in selection = nil; library.stopPreview() }
            .onDisappear { library.stopPreview() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in library.stopPreview() }
    }
    private func loadSelected() {
        guard let selected else { return }
        library.stopPreview()
        Task { if await model.loadInstrument(selected.url) { dismiss() } }
    }
}
