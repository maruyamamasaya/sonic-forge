import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class MIDIImportDraft: ObservableObject {
    struct Assignment: Identifiable {
        let id: String
        var selected = false
        var instrument: EnsembleInstrument?
        var instrumentName = "楽器を選択"
        var transpose = 0
    }
    @Published var song: MIDIFileSong?
    @Published var assignments: [Assignment] = []
    @Published var start = 0.0
    @Published var end = 0.0
    @Published var busy = false
    @Published var error: String?
    private var revision = UUID()
    func cancel() { revision = UUID(); busy = false }
    func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension:"mid") ?? .data, UTType(filenameExtension:"midi") ?? .data]
        panel.allowsMultipleSelection = false; panel.title = "MIDIファイルを読み込む"
        if panel.runModal() == .OK, let url = panel.url { Task { await load(url) } }
    }
    func load(_ url: URL) async {
        guard !busy else { return }
        busy = true; let token = UUID(); revision = token
        do {
            let value = try await Task.detached(priority:.userInitiated) { try MIDIFileImport.load(url) }.value
            guard revision == token else { return }
            song = value; assignments = value.parts.map { Assignment(id:$0.id) }
            start = 0; end = min(256,value.endBeat); error = nil
        } catch { if revision == token { self.error = error.localizedDescription } }
        if revision == token { busy = false }
    }
    func chooseInstrument(_ url: URL, id: String) async {
        guard !busy, assignments.contains(where:{$0.id == id}) else { return }
        busy = true; let token = revision
        do {
            let value = try await Task.detached(priority:.userInitiated) { try EnsembleInstrument.load(url) }.value
            guard token == revision, let i = assignments.firstIndex(where:{$0.id == id}) else { return }
            assignments[i].instrument = value; assignments[i].instrumentName = url.deletingPathExtension().lastPathComponent
            error = nil
        } catch { if token == revision { self.error = error.localizedDescription } }
        if token == revision { busy = false }
    }
    func instrumentPanel(id: String) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.sonicForgeInstrument]
        if panel.runModal() == .OK, let url = panel.url { Task { await chooseInstrument(url,id:id) } }
    }
    func snapshot() throws -> EnsembleSnapshot {
        guard let song else { throw AudioError.invalid("MIDIを選択してください。") }
        let selected = assignments.filter(\.selected)
        guard (1...4).contains(selected.count), start >= 0, end <= song.endBeat+1e-6 else { throw AudioError.invalid("1〜4パートと、曲の範囲内を選択してください。") }
        let parts = try selected.map { a -> EnsemblePartSnapshot in
            guard let instrument = a.instrument, let part = song.parts.first(where:{$0.id == a.id}) else { throw AudioError.invalid("各パートの楽器を選択してください。") }
            let performance = try part.performance(start:start,end:end,tempo:song.tempo,transpose:a.transpose)
            _ = try performance.events(root:instrument.root)
            return EnsemblePartSnapshot(name:String(part.name.prefix(80)),instrument:instrument,performance:performance,gainDB:0,muted:false)
        }
        let value = EnsembleSnapshot(tempo:song.tempo,masterDB:0,parts:parts)
        try EnsembleDocument.validate(value); return value
    }
    var validation: String? { do { _ = try snapshot(); return nil } catch { return error.localizedDescription } }
}

struct MIDIFileImportView: View {
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    let wood: WorkspaceWood
    @StateObject private var draft = MIDIImportDraft()
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("MIDIから曲を作る").font(.title2)
                Spacer()
                Button("閉じる") { draft.cancel(); dismiss() }.accessibilityIdentifier("midi.import.close")
            }
            Text("トラックと楽器を確認してから、現在の構成へ取り込みます。音色指定・ピッチベンド等は再現しません。1〜4パート、1パート256音・最大8音同時です。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("MIDIを選ぶ…") { draft.open() }.accessibilityIdentifier("midi.import.file")
                if draft.busy { ProgressView().controlSize(.small) }
                Text(draft.song?.name ?? "未選択").lineLimit(1)
            }.disabled(draft.busy)
            if let song = draft.song {
                HStack {
                    Text(String(format:"%.2f BPM · 全体 %.2f拍 · %d候補",song.tempo,song.endBeat,song.parts.count)).font(.caption)
                    Spacer()
                    TextField("開始拍",value:$draft.start,format:.number).frame(width:80).accessibilityIdentifier("midi.import.start")
                    Text("〜")
                    TextField("終了拍",value:$draft.end,format:.number).frame(width:80).accessibilityIdentifier("midi.import.end")
                    Text("拍を取り込む").font(.caption)
                }.disabled(draft.busy)
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        ForEach(draft.assignments.indices,id:\.self) { i in
                            let a = draft.assignments[i], part = song.parts[i]
                            VStack(alignment:.leading,spacing:6) {
                                HStack {
                                    Toggle(part.name,isOn:$draft.assignments[i].selected).accessibilityIdentifier("midi.import.select.\(a.id)")
                                    Spacer()
                                    Text("\(part.notes.count)音 · \(NotePitch.name(part.pitchRange.lowerBound))〜\(NotePitch.name(part.pitchRange.upperBound))").font(.caption)
                                }
                                HStack {
                                    Menu(a.instrumentName) {
                                        Button("楽器ファイルを開く…") { draft.instrumentPanel(id:a.id) }
                                        ForEach(library.entries.filter(\.available)) { entry in
                                            Button(entry.name) { Task { await draft.chooseInstrument(entry.url,id:a.id) } }
                                        }
                                    }.accessibilityIdentifier("midi.import.instrument.\(a.id)")
                                    if let instrument = a.instrument { Text("基準音 \(NotePitch.name(instrument.root))").font(.caption) }
                                    Spacer()
                                    Stepper("移調 \(a.transpose)半音",value:$draft.assignments[i].transpose,in:-24...24)
                                        .frame(width:180).accessibilityIdentifier("midi.import.transpose.\(a.id)")
                                }
                            }.padding(10).background(.black.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius:8))
                        }
                        ForEach(Array(song.warnings.enumerated()),id:\.offset) { _,warning in Text(warning).font(.caption).foregroundStyle(.orange) }
                    }
                }.disabled(draft.busy)
            }
            if let error = draft.error { Text(error).foregroundStyle(.orange).font(.caption).accessibilityIdentifier("midi.import.error") }
            if let message = draft.validation { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("midi.import.validation") }
            HStack {
                Text("取り込みは曲全体の取り消しで戻せます。元MIDI・元の楽器ファイルは変更しません。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("この割り当てで取り込む") { confirm = true }
                    .disabled(draft.busy || !ensemble.canEdit || draft.validation != nil).accessibilityIdentifier("midi.import.apply")
            }
        }
        .padding(22).frame(width:760,height:600).background(WoodSurface(wood:wood)).preferredColorScheme(.dark)
        .confirmationDialog("現在の構成をMIDIの割り当てで置き換えますか？未保存の内容は先に構成保存で残してください。",isPresented:$confirm) {
            Button("構成を取り込む") {
                do { if ensemble.importMIDI(try draft.snapshot()) { dismiss() } else { draft.error = ensemble.error } }
                catch { draft.error = error.localizedDescription }
            }
            Button("キャンセル",role:.cancel) { }
        }
        .onDisappear { draft.cancel() }
    }
}
