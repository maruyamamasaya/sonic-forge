import SwiftUI
import AppKit

@main
struct SonicForgeApp: App {
    @StateObject private var model = PlayerModel()
    var body: some Scene {
        Window("SonicForge", id: "studio") {
            WorkspaceView(model: model, ensemble: model.ensemble, library: model.library)
                .frame(minWidth: 1100, minHeight: model.ensembleWorkspaceActive ? 760 : 880)
                .task { model.installTransportShortcuts(); await model.startSession() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cleanup() }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    if model.ensembleWorkspaceActive {
                        if model.ensemble.playing { model.ensemble.stop() }
                        else { model.stop(); model.library.stopPreview(); model.ensemble.play() }
                    } else { model.toggle() }
                }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.ensembleWorkspaceActive ? model.ensemble.busy || model.ensemble.parts.isEmpty : model.asset == nil || model.busy)
                Button("Play Selection") { Task { await model.playSelection() } }
                    .keyboardShortcut(.space, modifiers: .shift)
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
                Button("Clear Selection") { model.clearSelection() }
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Instrument…") { model.ensembleWorkspaceActive = false; model.openInstrumentPanel() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Save…") {
                    if model.ensembleWorkspaceActive { model.ensemble.savePanel() } else { model.saveInstrumentPanel() }
                }.keyboardShortcut("s")
                    .disabled(model.ensembleWorkspaceActive ? !model.ensemble.canEdit || model.ensemble.parts.isEmpty : model.instrumentSample == nil || model.busy)
                Button("Open Ensemble…") { NotificationCenter.default.post(name: .openEnsembleWorkspace, object: nil) }
                    .disabled(!model.ensembleWorkspaceActive || !model.ensemble.canEdit)
                Button("Save Instrument…") { model.saveInstrumentPanel() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.instrumentSample == nil || model.busy)
                Button("Open WAV…") { model.ensembleWorkspaceActive = false; model.open() }.keyboardShortcut("o")
                Button("Export Selection as WAV…") { model.exportSelection() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
                Button("Load Demo") { model.ensembleWorkspaceActive = false; Task { await model.loadDemo() } }
            }
        }
    }
}
