import SwiftUI
import AppKit

@main
struct SonicForgeApp: App {
    @StateObject private var model = PlayerModel()
    var body: some Scene {
        Window("SonicForge", id: "studio") {
            StudioView(model: model)
                .frame(minWidth: 1000, minHeight: 720)
                .task { model.installTransportShortcuts(); await model.loadDemo() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cleanup() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") { model.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.asset == nil || model.loading)
                Button("Play Selection") { Task { await model.playSelection() } }
                    .keyboardShortcut(.space, modifiers: .shift)
                    .disabled(model.editor.selection == nil || model.loading)
                Button("Clear Selection") { model.clearSelection() }
                    .disabled(model.editor.selection == nil || model.loading)
            }
            CommandGroup(replacing: .newItem) {
                Button("Open WAV…") { model.open() }.keyboardShortcut("o")
                Button("Load Demo") { Task { await model.loadDemo() } }
            }
        }
    }
}
