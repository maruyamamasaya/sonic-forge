import Foundation

enum LibraryTests {
    @MainActor static func run(playback: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SonicForge-Library-" + UUID().uuidString)
        let suite = "SonicForge-Library-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let library = InstrumentLibrary(defaults: defaults, directory: root)
        await library.addDemos()
        precondition(library.error == nil && library.entries.count == 2)
        let first = library.entries[0]
        let bytes = try Data(contentsOf: first.url)
        await library.addDemos()
        let after = try Data(contentsOf: first.url)
        precondition(library.entries.count == 2 && after == bytes)
        library.query = "soft"
        precondition(library.filtered.count == 1 && library.filtered[0].name.contains("Soft"))
        library.query = "no match"
        precondition(library.filtered.isEmpty)
        let second = InstrumentLibrary(defaults: defaults, directory: root)
        precondition(second.entries == library.entries)
        await second.add([first.url])
        precondition(second.entries.count == 2)
        let corrupt = root.appendingPathComponent("corrupt.sfinstrument")
        try Data("bad".utf8).write(to: corrupt)
        await second.add([corrupt])
        precondition(second.entries.count == 2 && second.error != nil)
        if playback {
            let player = PlayerModel()
            await player.loadDemo()
            player.rootNote = 60
            let original = player.instrumentSample
            await second.preview(first)
            precondition(second.previewing == first.url && second.previewDescription != nil)
            try await Task.sleep(nanoseconds: 150_000_000)
            precondition(second.previewLevels.max()! > -60)
            precondition(player.rootNote == 60 && player.instrumentDirty && player.instrumentSample?.name == original?.name)
            second.stopPreview()
            precondition(second.previewing == nil)
            await second.preview(second.entries[1])
            precondition(second.previewing != nil)
            try await Task.sleep(nanoseconds: 3_200_000_000)
            precondition(second.previewing == nil)
            // Closing during decode must never start delayed audio.
            let pending = Task { await second.preview(first) }
            await Task.yield()
            second.stopPreview()
            await pending.value
            precondition(second.previewing == nil)
            let loaded = await player.loadInstrument(first.url, remember: false)
            precondition(loaded)
            precondition(player.rootNote == 57 && !player.instrumentDirty)
            player.playNote(57)
            try await Task.sleep(nanoseconds: 150_000_000)
            precondition(player.soundingVoices > 0)
            player.stopInstrument()
            player.cleanup()
            print("PASS: library preview, stop, auto-end, cancellation, current-edit preservation, demo load and keyboard playback")
        }
        second.remove(first)
        precondition(FileManager.default.fileExists(atPath: first.url.path))
        precondition(InstrumentLibrary(defaults: defaults, directory: root).entries.count == 1)
        let remaining = second.entries[0]
        try FileManager.default.removeItem(at: remaining.url)
        precondition(!remaining.available)
        await second.preview(remaining)
        precondition(second.previewing == nil && second.error != nil)
        print("PASS: library demo generation, duplicate/overwrite protection, search, persistent index, invalid/missing files and nondestructive removal")
    }
}
