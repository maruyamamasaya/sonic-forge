import SwiftUI
import AppKit

extension Notification.Name { static let openEnsembleWorkspace = Notification.Name("SonicForge.openEnsembleWorkspace") }

struct WorkspaceView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var ensemble: EnsembleModel
    @ObservedObject var library: InstrumentLibrary
    @AppStorage("workspaceWoodThemeV1") private var wood: WorkspaceWood = .walnut
    @State private var selectedSection: UUID?
    @State private var selectedPart: UUID?
    @State private var selectedClip: UUID?
    @State private var librarySelection: String?
    @State private var confirmOpen = false
    @State private var allParts = false
    @State private var arranging = false
    @StateObject private var arranger = ArrangementComposer()
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    private var part: EnsemblePart? { ensemble.parts.first { $0.id == selectedPart } ?? ensemble.parts.first }
    private var activeClip: UUID? {
        guard let part else { return nil }
        return part.allClips.first(where: { $0.id == selectedClip })?.id ?? part.primaryClipID
    }
    private var entry: LibraryEntry? { library.filtered.first { $0.id == librarySelection } }
    var body: some View {
        Group {
            if model.ensembleWorkspaceActive { workspace }
            else { StudioView(model: model, onShowEnsemble: { model.stop(); library.stopPreview(); model.ensembleWorkspaceActive = true }) }
        }
        .onAppear { model.suspendMIDI(model.ensembleWorkspaceActive) }
        .onChange(of: model.ensembleWorkspaceActive) { _, active in
            ensemble.stop(); model.stop(); library.stopPreview(); model.suspendMIDI(active)
        }
        .onChange(of: ensemble.parts.map(\.id)) { _, _ in
            if !ensemble.parts.contains(where: { $0.id == selectedPart }) {
                selectedPart = ensemble.parts.first?.id; selectedClip = ensemble.parts.first?.primaryClipID
            }
        }
        .onChange(of: ensemble.sections.map(\.id)) { _, ids in
            if let selectedSection, !ids.contains(selectedSection) { self.selectedSection = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openEnsembleWorkspace)) { _ in requestOpen() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in ensemble.stop(); library.stopPreview() }
        .onChange(of: library.query) { _, _ in librarySelection = nil; library.stopPreview() }
        .onDisappear { model.separation.cancel(); model.separation.stopPreview(); ensemble.stop(); library.stopPreview(); model.stop() }
        .sheet(isPresented: $arranging) {
            ArrangementComposerView(ensemble: ensemble, connection: model.composer, composer: arranger, wood: wood)
        }
        .sheet(isPresented: $allParts) { EnsembleView(model: model, ensemble: ensemble, library: library) }
        .confirmationDialog("未保存の構成を置き換えますか？", isPresented: $confirmOpen) {
            Button("構成を選ぶ…", role: .destructive) { ensemble.openPanel() }
            Button("キャンセル", role: .cancel) { }
        } message: { Text("変更を残す場合はキャンセルして先に保存してください。読み込みに失敗した場合は元の構成を保ちます。") }
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                libraryPanel.frame(width: 190).foregroundStyle(wood.ink).environment(\.colorScheme, wood.scheme)
                    .background(WoodSurface(wood: wood)).overlay(alignment: .trailing) { Rectangle().fill(.black.opacity(0.45)).frame(width: 3).allowsHitTesting(false) }
                Divider()
                VStack(spacing: 0) {
                    sectionToolbar
                    if ensemble.parts.isEmpty && ensemble.sections.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "pianokeys").font(.system(size: 38)).foregroundStyle(accent)
                            Text("曲の構成を作る").font(.system(size: 21, weight: .medium))
                            Text("左の楽器を選ぶか、デモ曲から始められます。").foregroundStyle(.secondary)
                            Button("デモ曲") { Task { await ensemble.addSharedSongDemo() } }
                                .disabled(!ensemble.sections.isEmpty || !ensemble.canEdit)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VSplitView {
                            ScrollView(.vertical) {
                                EnsembleTimelineView(ensemble: ensemble, expanded: true,
                                                     selectedPart: selectedSection == nil ? part?.id : nil,
                                                     selectedClip: selectedSection == nil ? activeClip : nil,
                                                     onSelect: select, selectedSection: selectedSection,
                                                     onSelectSection: { selectedSection = $0 })
                                    .frame(maxWidth: .infinity, alignment: .top)
                            }.frame(minHeight: 190, idealHeight: CGFloat(ensemble.parts.count) * 86 + 94, maxHeight: CGFloat(max(2, ensemble.parts.count)) * 86 + 128)
                            if let part, let activeClip {
                                SelectedClipNotes(ensemble: ensemble, part: part, clipID: activeClip).id(activeClip).frame(minHeight: 145, idealHeight: 270)
                            }
                        }
                    }
                    HStack {
                        Button("パート追加") { if let added = ensemble.addPart() { select(added.id, added.primaryClipID) } }
                        Button("編集中の楽器を追加") { if let instrument = currentInstrument, let added = ensemble.addPart(instrument: instrument, performance: model.midi.performance) { select(added.id, added.primaryClipID) } }
                            .disabled(currentInstrument == nil || model.busy)
                        Spacer()
                        Menu("デモ") {
                            Button("デモ曲") { Task { await ensemble.addSharedSongDemo() } }.disabled(!ensemble.parts.isEmpty || !ensemble.sections.isEmpty)
                            Button("デモ2パート") { Task { await ensemble.addDemos() } }
                            Button("左右配置デモ") { Task { await ensemble.addDemos(panned: true) } }
                            Button("リミッターデモ") { Task { await ensemble.addDemos(limited: true) } }
                            Button("コンプレッサーデモ") { Task { await ensemble.addDemos(compressed: true) } }
                            Button("ディレイデモ") { Task { await ensemble.addDemos(delayed: true) } }
                            Button("リバーブデモ") { Task { await ensemble.addDemos(reverberant: true) } }
                            Button("音質調整デモ") { Task { await ensemble.addDemos(equalized: true) } }
                            Button("4拍遅れて入るデモ") { Task { await ensemble.addDemos(staggered: true) } }
                            Button("繰り返しデモ") { Task { await ensemble.addDemos(staggered: true, repeating: true) } }
                        }.frame(width: 85).disabled(ensemble.parts.count > 2)
                    }.disabled(!ensemble.canEdit || ensemble.parts.count >= 4).padding(.horizontal, 10).padding(.vertical, 8)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.10, green: 0.12, blue: 0.095))
                    .overlay { Rectangle().stroke(.black.opacity(0.6), lineWidth: 2).allowsHitTesting(false) }
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 1, y: 1)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("選択対象の設定").font(.system(size: 10, weight: .medium)).tracking(1.5).foregroundStyle(.secondary).padding(16)
                    if let selectedSection, ensemble.sections.contains(where: { $0.id == selectedSection }) {
                        WorkspaceSectionInspector(ensemble: ensemble, sectionID: selectedSection, onSelect: { self.selectedSection = $0 })
                    } else if let part {
                        WorkspaceInspector(part: part, ensemble: ensemble, currentPerformance: model.midi.performance,
                                           clipID: activeClip ?? part.primaryClipID)
                            .id(part.id)
                    } else {
                        Text("パートやクリップを選んでください").foregroundStyle(.secondary).padding(16)
                        Spacer()
                    }
                }.frame(width: 250).foregroundStyle(wood.ink).environment(\.colorScheme, wood.scheme)
                    .background(WoodSurface(wood: wood)).overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.45)).frame(width: 3).allowsHitTesting(false) }
            }.frame(maxHeight: .infinity)
            Divider()
            EnsembleTransportControls(ensemble: ensemble, selectedSection: selectedSection)
                .padding(.horizontal, 18).padding(.vertical, 6)
            transport
            if ensemble.exporting {
                HStack {
                    ProgressView(value: ensemble.exportProgress).tint(accent)
                    Text("書き出し中 \(Int(ensemble.exportProgress * 100))%")
                    Button("書き出しを中止") { ensemble.cancelExport() }
                }.font(.system(size: 11)).padding(.horizontal, 20).padding(.bottom, 10)
            }
            HStack {
                Text(ensemble.error ?? library.error ?? JapaneseUI.status(ensemble.fileMessage ?? "クリップを選択 · Spaceで再生・停止"))
                    .foregroundStyle(ensemble.error == nil && library.error == nil ? Color.secondary : .orange).lineLimit(2)
                    .help(ensemble.error ?? library.error ?? "")
                Spacer()
                Text("\(ensemble.parts.count)/4 パート・\(ensemble.sections.count)/8 セクション").foregroundStyle(.secondary)
            }.font(.system(size: 10)).padding(.horizontal, 16).padding(.vertical, 7)
        }.background(Color(red: 0.075, green: 0.085, blue: 0.10))
            .padding(7).background(WoodSurface(wood: wood))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .black.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false) }
            .preferredColorScheme(.dark).buttonStyle(CabinetButton()).controlSize(.small)
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent)
            Text("SonicForge").font(.custom("Georgia", size: 20)).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
            Text("曲の構成").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider().frame(height: 20)
            Text(ensemble.fileURL?.deletingPathExtension().lastPathComponent ?? "無題の構成").lineLimit(1).truncationMode(.middle)
            Text(ensemble.dirty ? "● 未保存" : ensemble.fileURL == nil ? "新規" : "保存済み").foregroundStyle(ensemble.dirty ? accent : .secondary)
            Spacer()
            if ensemble.busy { ProgressView().controlSize(.small) }
            Picker("木材の種類", selection: $wood) {
                ForEach(WorkspaceWood.allCases) { Text(JapaneseUI.wood($0.rawValue)).tag($0) }
            }.labelsHidden().frame(width: 118).accessibilityIdentifier("Wood theme").accessibilityLabel("木材の種類")
            StudioHelpButton(wood: wood)
            Button("全パート…") { library.stopPreview(); ensemble.stop(); allParts = true }.disabled(ensemble.busy)
            Button("開く…") { requestOpen() }.disabled(!ensemble.canEdit).accessibilityIdentifier("Open ensemble").accessibilityLabel("構成を開く")
            Button("保存…") { ensemble.savePanel() }.disabled(!ensemble.canEdit || ensemble.parts.isEmpty).accessibilityIdentifier("Save ensemble").accessibilityLabel("構成を保存").help(StudioHelpTopic.save.explanation)
            Button("WAV書き出し…") { library.stopPreview(); ensemble.exportPanel(protecting: model.asset.map { [$0.url] } ?? []) }
                .disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
        }.font(.system(size: 11)).padding(.horizontal, 16).frame(height: 52)
            .foregroundStyle(wood.ink).environment(\.colorScheme, wood.scheme).background(WoodSurface(wood: wood, horizontalGrain: true))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.4)).frame(height: 2).allowsHitTesting(false) }
    }
    private var sectionToolbar: some View {
        HStack(spacing: 10) {
            Text("曲の構成").font(.system(size: 10)).tracking(1.2).foregroundStyle(.secondary)
            Button { ensemble.restoreSongEdit() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!ensemble.canUndoSong).accessibilityIdentifier("Undo song edit").accessibilityLabel("曲の編集を取り消す")
                .help("取り消す：" + ensemble.undoSongLabel + "。曲全体の直近50操作が対象です。")
            Button { ensemble.restoreSongEdit(redo: true) } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!ensemble.canRedoSong).accessibilityIdentifier("Redo song edit").accessibilityLabel("曲の編集をやり直す")
                .help("やり直す：" + ensemble.redoSongLabel)

            Spacer()
            Button("AI編曲…") { library.stopPreview(); model.stop(); arranging = true }
                .disabled(!ensemble.canEdit || ensemble.parts.isEmpty)
                .accessibilityIdentifier("Arrange ensemble with AI").accessibilityLabel("AIで編曲案を作る").help(StudioHelpTopic.ai.explanation)
            Button("セクション追加") {
                ensemble.addSection()
                selectedSection = ensemble.sections.last?.id
            }.disabled(!ensemble.canEdit || ensemble.sections.count >= 8)
        }.padding(.horizontal, 10).frame(height: 36)
    }
    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("楽器ライブラリ").font(.system(size: 10, weight: .medium)).tracking(1.2)
            TextField("楽器を検索", text: $library.query).textFieldStyle(.roundedBorder)
            HStack {
                Button("ファイル…") { library.addPanel() }.accessibilityIdentifier("Add Files…").accessibilityLabel("楽器ファイルを追加")
                Button("デモ追加") { Task { await library.addDemos() } }
            }.disabled(library.busy)
            List(library.filtered, selection: $librarySelection) { value in
                VStack(alignment: .leading, spacing: 4) {
                    Label(value.name, systemImage: "waveform").lineLimit(2)
                    Text(value.available ? "保存された楽器" : "見つかりません").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.vertical, 5).tag(value.id).help(value.url.path)
            }.listStyle(.plain).scrollContentBackground(.hidden).onChange(of: librarySelection) { _, _ in library.stopPreview() }
            Text(library.previewDescription.map(JapaneseUI.preview) ?? "\(library.filtered.count) 楽器").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button(library.previewing == nil ? "試聴" : "試聴停止") {
                    if library.previewing != nil { library.stopPreview() }
                    else if let entry { ensemble.stop(); model.stop(); Task { await library.preview(entry) } }
                }.disabled(library.busy || ensemble.busy || model.busy || (library.previewing == nil && entry?.available != true))
                Button("割り当て") { if let entry, let part { library.stopPreview(); Task { await ensemble.loadInstrument(entry.url, part: part.id) } } }
                    .disabled(!ensemble.canEdit || library.busy || entry?.available != true || part == nil)
            }
            Button("新規パートに追加") {
                guard let entry, let added = ensemble.addPart() else { return }
                select(added.id, added.primaryClipID)
                library.stopPreview(); Task { await ensemble.loadInstrument(entry.url, part: added.id) }
            }.disabled(!ensemble.canEdit || library.busy || entry?.available != true || ensemble.parts.count >= 4)
            if let entry {
                Button("一覧から外す") { library.remove(entry); librarySelection = nil }.font(.system(size: 10)).disabled(library.busy)
            }
            Divider()
            Text("素材・楽器編集").font(.system(size: 10)).tracking(1.2).foregroundStyle(.secondary)
            Button("波形・楽器を編集…") { openStudio() }.disabled(ensemble.busy || model.busy)
                .accessibilityIdentifier("Open Sample Studio").accessibilityLabel("素材・楽器編集を開く")
            Text("切り出し・鍵盤・MIDI・AI演奏").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(11).frame(maxHeight: .infinity)
    }
    private var transport: some View {
        HStack(spacing: 20) {
            Button("全停止") { ensemble.stop(); library.stopPreview(); model.stop() }.accessibilityIdentifier("Stop all workspace audio").accessibilityLabel("すべての音を止める")
            Button(ensemble.playing ? "一時停止" : ensemble.rangeLoopEnabled ? "範囲を再生" : ensemble.positionBeats > 0 ? "ここから再生" : "全体を再生") {
                if ensemble.playing { ensemble.pause() }
                else { model.prepareEnsemblePlayback(); library.stopPreview(); ensemble.play() }
            }.buttonStyle(CabinetButton(primary: true)).disabled(ensemble.busy || ensemble.parts.isEmpty)
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: "%06.2f / %.2f", ensemble.positionBeats, arrangementBeats)).font(.system(size: 18, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 4).background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.1)) }
                Text(ensemble.releasing ? "余韻を再生中" : ensemble.rangeLoopEnabled && ensemble.playing ? "再生位置・拍・ループ\(ensemble.playbackPass)周目" : "再生位置・拍").font(.system(size: 9)).foregroundStyle(.secondary)
            }.frame(width: 200, alignment: .leading)
            TextField("曲全体のテンポ", value: $ensemble.tempo, format: .number).textFieldStyle(.roundedBorder).frame(width: 58).disabled(!ensemble.canEdit)
            Text("BPM").foregroundStyle(.secondary).help(StudioHelpTopic.beat.explanation)
            Spacer()
            MasterLimiterControl(ensemble: ensemble)
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "全体音量・%.0f dB", ensemble.masterDB)).font(.system(size: 10))
                Slider(value: $ensemble.masterDB, in: -60...0).frame(width: 145).tint(accent).accessibilityIdentifier("Ensemble master volume").accessibilityLabel("曲全体の音量").disabled(ensemble.busy)
                Text("出力 \(Int(ensemble.level)) dB").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 18).padding(.vertical, 9).background(LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.14), Color(red: 0.11, green: 0.13, blue: 0.095)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
    }
    private var arrangementBeats: Double {
        max(EnsembleSections.end(ensemble.sections), ensemble.parts.flatMap(\.allClips).map {
            EnsembleSections.offset($0.sectionID, in: ensemble.sections) + ($0.startBeat.isFinite ? max(0, $0.startBeat) : 0)
                + (EnsembleTimeline.repeatedLength($0.performance, count: $0.repeatCount) ?? 0)
        }.max() ?? 0)
    }
    private func requestOpen() {
        guard ensemble.canEdit else { return }
        library.stopPreview()
        if ensemble.dirty { confirmOpen = true } else { ensemble.openPanel() }
    }
    private func select(_ partID: UUID, _ clipID: UUID) { selectedSection = nil; selectedPart = partID; selectedClip = clipID }
    private func openStudio() { ensemble.stop(); library.stopPreview(); model.ensembleWorkspaceActive = false }
    private var currentInstrument: EnsembleInstrument? {
        guard let sample = model.instrumentSample else { return nil }
        return EnsembleInstrument(sample: sample, root: model.rootNote, envelope: model.envelope, loop: model.sampleLoop,
                                  name: model.instrumentFileURL?.deletingPathExtension().lastPathComponent ?? sample.name)
    }
}
