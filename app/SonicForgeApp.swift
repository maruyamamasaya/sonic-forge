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
        .defaultSize(width: 1920, height: 1080)
        .commands {
            CommandMenu("再生") {
                Button("再生・一時停止") {
                    if model.ensembleWorkspaceActive {
                        if model.ensemble.playing { model.ensemble.stop() }
                        else { model.stop(); model.library.stopPreview(); model.ensemble.play() }
                    } else { model.toggle() }
                }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.ensembleWorkspaceActive ? model.ensemble.busy || model.ensemble.parts.isEmpty : model.asset == nil || model.busy)
                Button("選択範囲を再生") { Task { await model.playSelection() } }
                    .keyboardShortcut(.space, modifiers: .shift)
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
                Button("範囲選択を解除") { model.clearSelection() }
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button("楽器を開く…") { model.ensembleWorkspaceActive = false; model.openInstrumentPanel() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("保存…") {
                    if model.ensembleWorkspaceActive { model.ensemble.savePanel() } else { model.saveInstrumentPanel() }
                }.keyboardShortcut("s")
                    .disabled(model.ensembleWorkspaceActive ? !model.ensemble.canEdit || model.ensemble.parts.isEmpty : model.instrumentSample == nil || model.busy)
                Button("曲の構成を開く…") { NotificationCenter.default.post(name: .openEnsembleWorkspace, object: nil) }
                    .disabled(!model.ensembleWorkspaceActive || !model.ensemble.canEdit)
                Button("楽器を保存…") { model.saveInstrumentPanel() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.instrumentSample == nil || model.busy)
                Button("WAVを開く…") { model.ensembleWorkspaceActive = false; model.open() }.keyboardShortcut("o")
                Button("選択範囲をWAVに書き出す…") { model.exportSelection() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.ensembleWorkspaceActive || model.editor.selection == nil || model.busy)
                Button("デモを開く") { model.ensembleWorkspaceActive = false; Task { await model.loadDemo() } }
            }
        }
    }
}
