import SwiftUI
import AppKit

@main
struct SonicForgeApp: App {
    @StateObject private var model = PlayerModel()
    var body: some Scene {
        Window("SonicForge", id: "studio") {
            StudioView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .task { await model.loadDemo() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cleanup() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open WAV…") { model.open() }.keyboardShortcut("o")
                Button("Load Demo") { Task { await model.loadDemo() } }
            }
        }
    }
}
