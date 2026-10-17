import SwiftUI

private let amber = Color(red: 0.96, green: 0.72, blue: 0.33)
private let base = Color(red: 0.075, green: 0.09, blue: 0.105)
private let panel = Color(red: 0.105, green: 0.125, blue: 0.14)
private let muted = Color(red: 0.64, green: 0.69, blue: 0.73)
private let line = Color.white.opacity(0.10)

struct StudioView: View {
    @ObservedObject var model: PlayerModel
    @State private var showingLibrary = false
    @State private var showingEnsemble = false
    @State private var composing = false
    @State private var playComposed = false
    private var asset: AudioAsset? { model.asset }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(line).frame(height: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text(model.instrumentFileURL?.deletingPathExtension().lastPathComponent ?? asset.map { $0.isDemo ? "Metal Hit — Demo" : $0.url.deletingPathExtension().lastPathComponent } ?? "Sample Studio")
                            .font(.system(size: 22, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if asset?.isDemo == true {
                            Text("DEMO").font(.system(size: 10, weight: .semibold)).foregroundStyle(amber)
                                .padding(.horizontal, 9).padding(.vertical, 5).background(amber.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        if model.busy { ProgressView().controlSize(.small) }
                    }
                    .padding(.bottom, 8)
                    Text(asset.map { "WAV · \($0.channels == 1 ? "Mono" : "Stereo") · \(($0.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...2)))) kHz · \($0.bitDepth)-bit" } ?? "Open a WAV file, or load the built-in demo to begin.")
                        .font(.system(size: 12)).foregroundStyle(muted)
                }.padding(20).frame(height: 94).background(panel)
                .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
                .frame(maxWidth: .infinity)
                inspectorHeader
            }.fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    if let asset {
                        waveform(asset: asset)
                        WaveCanvas(peaks: asset.peaks, fraction: fraction, overview: true,
                                   selection: model.editor.selectionRange, window: model.editor.visibleRange,
                                   seek: model.pan)
                            .frame(height: 42).background(panel).overlay { Rectangle().stroke(line) }
                            .contentShape(Rectangle())
                            .accessibilityLabel("Full file overview. Click or drag to move the zoomed view.")
                        InstrumentKeyboard(model: model)
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "waveform").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(amber)
                            Text("Your sound starts here").font(.system(size: 20, weight: .medium))
                            Text("Open a WAV file or explore with a synthesized demo.")
                                .foregroundStyle(muted)
                            Button("Load Demo") { Task { await model.loadDemo() } }.buttonStyle(StudioButton(primary: true)).disabled(model.busy)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).disabled(model.busy)
                Rectangle().fill(line).frame(width: 1)
                inspector.frame(width: 268).background(panel)
            }
            Rectangle().fill(line).frame(height: 1)
            transport
            Rectangle().fill(line).frame(height: 1)
            HStack {
                Circle().fill(model.playing ? amber : muted).frame(width: 5, height: 5)
                Text(model.preparingInstrument ? "Preparing instrument…" : model.exporting ? "Exporting selection…" : model.exportMessage ?? (model.loading ? "Loading audio…" : asset == nil ? "No audio file loaded" : asset!.isDemo ? "Synthesized demo · Ready to play" : "WAV loaded · \(asset!.url.lastPathComponent)")).lineLimit(1)
                Spacer()
                Text("System output").foregroundStyle(muted)
                Text("•").foregroundStyle(muted)
                Text("SonicForge 0.1").foregroundStyle(muted)
            }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 20).frame(height: 32)
        }
        .background(base).foregroundStyle(Color(red: 0.86, green: 0.89, blue: 0.91))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingEnsemble) { EnsembleView(model: model, ensemble: model.ensemble, library: model.library) }
        .sheet(isPresented: $showingLibrary) { LibraryView(model: model, library: model.library) }
        .sheet(isPresented: $composing, onDismiss: {
            if playComposed { playComposed = false; model.suspendMIDI(false); model.midi.playPerformance() }
        }) { PerformanceComposerView(model: model, midi: model.midi, composer: model.composer, onUse: { playComposed = true }) }
        .onExitCommand { model.clearSelection() }
        .alert("SonicForge", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var fraction: Double { guard let asset, asset.duration > 0 else { return 0 }; return model.position / asset.duration }
    private var toolbar: some View {
        HStack(spacing: 18) {
            Text("SonicForge").font(.system(size: 18, weight: .semibold))
            Rectangle().fill(line).frame(width: 1, height: 20)
            Text("Sample Studio").font(.system(size: 12)).foregroundStyle(muted)
            Spacer()
            Button("Ensemble…") { model.stop(); showingEnsemble = true }.buttonStyle(StudioButton())
            Button("Compose…") { model.stop(); composing = true }.buttonStyle(StudioButton())
                .disabled(model.instrumentSample == nil)
            Button("Library…") { model.stop(); showingLibrary = true }.buttonStyle(StudioButton())
            Button { model.exportSelection() } label: {
                Label("Export WAV…", systemImage: "square.and.arrow.up")
            }.buttonStyle(StudioButton()).disabled(model.editor.selection == nil)
                .help("Export selected range as 32-bit Float WAV · ⇧⌘E")
            Button("Load Demo") { Task { await model.loadDemo() } }.buttonStyle(StudioButton())
                .help("Generate an original 8-second stereo demo; no audio file needed")
            Button("Open WAV…") { model.open() }.buttonStyle(StudioButton()).keyboardShortcut("o", modifiers: .command)
        }.padding(.horizontal, 20).frame(height: 56).background(panel).disabled(model.busy)
    }
    private var inspectorHeader: some View {
        HStack { Text("SOURCE").font(.system(size: 11, weight: .semibold)).tracking(1.4); Spacer() }
            .padding(22).frame(width: 269, height: 94).background(panel)
            .overlay(alignment: .leading) { Rectangle().fill(line).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            info("Filename", asset?.url.lastPathComponent ?? "—")
            info("Duration", asset.map { timeLabel($0.duration) } ?? "—")
            info("Sample Rate", asset.map { "\(Int($0.sampleRate).formatted()) Hz" } ?? "—")
            info("Channels", asset.map { $0.channels == 1 ? "Mono" : "Stereo" } ?? "—")
            info("Bit Depth", asset.map { "\($0.bitDepth)-bit" } ?? "—")
            info("File Size", asset.map { ByteCountFormatter.string(fromByteCount: $0.byteCount, countStyle: .file) } ?? "—")
            Text("OUTPUT").font(.system(size: 11, weight: .semibold)).tracking(1.4).padding(.top, 24)
            HStack(spacing: 18) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach([0, -12, -24, -36, -48, -60], id: \.self) { value in
                        Text("\(value)").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted).frame(maxHeight: .infinity)
                    }
                }.frame(width: 28)
                OutputMeterColumn(state: model.outputMeter, channel: 0, name: "L")
                OutputMeterColumn(state: model.outputMeter, channel: 1, name: "R")
                Spacer(minLength: 0)
            }.padding(.top, 18).padding(.leading, 28).frame(minHeight: 100, maxHeight: 240)
            Spacer(minLength: 20)
            HStack {
                Text("Master Gain").foregroundStyle(muted)
                Spacer()
                Text(String(format: "%.1f dB", model.gainDB)).monospacedDigit()
            }.font(.system(size: 11))
            Slider(value: $model.gainDB, in: -60...0).tint(amber).accessibilityLabel("Master gain in decibels")
            Text("Output follows macOS sound settings.").font(.system(size: 9)).foregroundStyle(muted).padding(.top, 6)
        }.padding(.horizontal, 22).padding(.bottom, 22)
    }
    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(muted)
            Spacer(minLength: 8)
            Text(value).lineLimit(1).truncationMode(.middle).help(value)
        }.font(.system(size: 11)).frame(height: 35).overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }
    private func waveform(asset: AudioAsset) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("WAVEFORM").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(muted)
                Spacer()
                Button { model.zoom(by: 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .buttonStyle(StudioButton()).disabled(model.editor.zoom <= 1.001).accessibilityLabel("Zoom out")
                Text(model.editor.zoom.formatted(.number.precision(.fractionLength(0...1))) + "×").font(.system(size: 11, design: .monospaced)).frame(width: 38)
                Button { model.zoom(by: 2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .buttonStyle(StudioButton()).disabled(model.editor.zoom >= 31.999).accessibilityLabel("Zoom in")
                Button("Fit All") { model.fitAll() }.buttonStyle(StudioButton())
                Button("Fit Selection") { model.fitSelection() }.buttonStyle(StudioButton()).disabled(model.editor.selection == nil)
            }.padding(.bottom, 10)
            HStack(spacing: 0) {
                ForEach(0..<9) { index in
                    Text(String(format: "%.3fs", asset.duration * (model.editor.visibleRange.lowerBound + model.editor.visibleRange.count * Double(index) / 8)))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                    if index < 8 { Spacer(minLength: 0) }
                }
            }.frame(height: 25)
            WaveCanvas(peaks: asset.peaks, fraction: fraction, overview: false,
                       viewport: model.editor.visibleRange, selection: model.editor.selectionRange,
                       seek: model.seek, select: model.select)
                .background(base).overlay { Rectangle().stroke(line) }
                .accessibilityLabel("Audio waveform. Click to seek, drag to select a range. Drag selection edges to adjust.")
            HStack(spacing: 12) {
                if model.editor.selection != nil {
                    Text("IN  " + timeLabel(model.editor.selectionStart))
                    Text("OUT  " + timeLabel(model.editor.selectionEnd))
                    Text("LENGTH  " + timeLabel(model.editor.selectionEnd - model.editor.selectionStart)).foregroundStyle(amber)
                    Spacer(minLength: 0)
                    Button("Clear") { model.clearSelection() }.buttonStyle(.plain).foregroundStyle(muted)
                        .accessibilityLabel("Clear selection")
                } else {
                    Text("Drag to select · Click to seek").foregroundStyle(muted)
                    Spacer()
                }
            }.font(.system(size: 10, design: .monospaced)).lineLimit(1).frame(height: 32)
            Slider(value: Binding(get: { model.position }, set: { model.seek($0 / asset.duration) }), in: 0...asset.duration)
                .tint(amber).accessibilityLabel("Playback position")
        }
    }
    private var transport: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { model.seek(0) } label: { Image(systemName: "backward.end.fill").frame(width: 42, height: 34) }
                .buttonStyle(StudioButton()).help("Return to start").accessibilityLabel("Return to start")
            Button { model.stop() } label: { Image(systemName: "stop.fill").frame(width: 42, height: 34) }
                .buttonStyle(StudioButton()).help("Stop and return to start").accessibilityLabel("Stop")
            Button { model.toggle() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").frame(width: 42, height: 34) }
                .buttonStyle(StudioButton(primary: true)).help("Play / Pause · Space").accessibilityLabel(model.playing ? "Pause" : "Play")
            Button { Task { await model.playSelection() } } label: {
                Label("Play Selection", systemImage: "play.rectangle")
            }.buttonStyle(StudioButton()).disabled(model.editor.selection == nil)
                .help("Play selected range · Shift-Space").padding(.leading, 12)
            Text("\(timeLabel(model.position)) / \(timeLabel(asset?.duration ?? 0))")
                .font(.system(size: 16, weight: .medium, design: .monospaced)).padding(.horizontal, 22).padding(.vertical, 13)
                .background(Color.black.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.leading, 24)
            Text(model.playingSelection ? "SELECTION" : "Space  Play / Pause").font(.system(size: 10)).foregroundStyle(muted).padding(.leading, 24)
            Spacer()
        }.padding(.vertical, 20).background(panel).disabled(asset == nil || model.busy)
    }
}

struct StudioButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(primary ? Color.black.opacity(0.85) : Color.white.opacity(0.88))
            .background(primary ? amber.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.065))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.07)) }
            .opacity(isEnabled ? 1 : 0.35)
    }
}

struct WaveCanvas: View {
    let peaks: [[Float]]
    let fraction: Double
    let overview: Bool
    var viewport: Range<Double> = 0..<1
    var selection: Range<Double>?
    var window: Range<Double>?
    var seek: ((Double) -> Void)?
    var select: ((Double, Double) -> Void)?
    @State private var dragAnchor: Double?

    private func location(_ x: CGFloat, width: CGFloat) -> Double {
        max(0, min(1, viewport.lowerBound + Double(x / max(1, width)) * viewport.count))
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                func x(_ value: Double) -> CGFloat { CGFloat((value - viewport.lowerBound) / viewport.count) * size.width }
                if let selection {
                    let start = max(0, x(selection.lowerBound)), end = min(size.width, x(selection.upperBound))
                    if end > start {
                        context.fill(Path(CGRect(x: start, y: 0, width: end - start, height: size.height)), with: .color(amber.opacity(overview ? 0.10 : 0.14)))
                    }
                }
                let lane = size.height / CGFloat(max(1, peaks.count))
                for (channel, values) in peaks.enumerated() {
                    let middle = lane * (CGFloat(channel) + 0.5)
                    var grid = Path()
                    for index in 0...8 {
                        let gx = size.width * CGFloat(index) / 8
                        grid.move(to: CGPoint(x: gx, y: CGFloat(channel) * lane))
                        grid.addLine(to: CGPoint(x: gx, y: CGFloat(channel + 1) * lane))
                    }
                    grid.move(to: CGPoint(x: 0, y: middle)); grid.addLine(to: CGPoint(x: size.width, y: middle))
                    context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    var wave = Path()
                    let columns = max(1, Int(size.width * 1.5))
                    for column in 0..<columns {
                        let low = viewport.lowerBound + viewport.count * Double(column) / Double(columns)
                        let high = viewport.lowerBound + viewport.count * Double(column + 1) / Double(columns)
                        let first = max(0, min(values.count - 1, Int(low * Double(values.count))))
                        let last = max(first + 1, min(values.count, Int(ceil(high * Double(values.count)))))
                        let peak = values[first..<last].max() ?? 0
                        let wx = CGFloat(column) / CGFloat(columns) * size.width
                        let height = CGFloat(min(1, peak)) * lane * 0.44
                        wave.move(to: CGPoint(x: wx, y: middle - max(0.35, height)))
                        wave.addLine(to: CGPoint(x: wx, y: middle + max(0.35, height)))
                    }
                    context.stroke(wave, with: .color(overview ? muted.opacity(0.65) : amber), lineWidth: 0.8)
                    if !overview {
                        context.draw(Text(channel == 0 ? (peaks.count == 1 ? "MONO" : "L") : "R").font(.system(size: 10)).foregroundColor(muted), at: CGPoint(x: 22, y: CGFloat(channel) * lane + 16))
                    }
                }
                if let selection, !overview {
                    for boundary in [selection.lowerBound, selection.upperBound] {
                        let sx = x(boundary)
                        if sx >= 0 && sx <= size.width {
                            var edge = Path()
                            edge.move(to: CGPoint(x: sx, y: 0)); edge.addLine(to: CGPoint(x: sx, y: size.height))
                            context.stroke(edge, with: .color(amber.opacity(0.9)), lineWidth: 1)
                            context.fill(Path(CGRect(x: sx - 3, y: 0, width: 6, height: 12)), with: .color(amber))
                        }
                    }
                }
                if let window, window.count < 0.9999 {
                    let rect = CGRect(x: x(window.lowerBound), y: 1, width: CGFloat(window.count) * size.width, height: size.height - 2)
                    context.fill(Path(rect), with: .color(.white.opacity(0.06)))
                    context.stroke(Path(rect), with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
                if fraction >= viewport.lowerBound && fraction <= viewport.upperBound {
                    var playhead = Path()
                    let px = max(0, min(size.width - 1, x(fraction)))
                    playhead.move(to: CGPoint(x: px, y: 0)); playhead.addLine(to: CGPoint(x: px, y: size.height))
                    context.stroke(playhead, with: .color(amber), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    let current = location(event.location.x, width: geometry.size.width)
                    guard let select else { seek?(current); return }
                    guard abs(event.translation.width) >= 3 || dragAnchor != nil else { return }
                    if dragAnchor == nil {
                        let start = location(event.startLocation.x, width: geometry.size.width)
                        let tolerance = 8 / Double(max(1, geometry.size.width)) * viewport.count
                        if let selection, abs(start - selection.lowerBound) < tolerance {
                            dragAnchor = selection.upperBound
                        } else if let selection, abs(start - selection.upperBound) < tolerance {
                            dragAnchor = selection.lowerBound
                        } else { dragAnchor = start }
                    }
                    select(dragAnchor ?? current, current)
                }
                .onEnded { event in
                    if dragAnchor == nil { seek?(location(event.location.x, width: geometry.size.width)) }
                    dragAnchor = nil
                })
        }
    }
}

private struct OutputMeterColumn: View {
    @ObservedObject var state: OutputMeterState
    let channel: Int
    let name: String
    var body: some View {
        VStack(spacing: 6) {
            Text(name).font(.system(size: 10)).foregroundStyle(muted)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.35))
                    Rectangle().fill(amber).frame(height: geometry.size.height * CGFloat((state.levels[channel] + 60) / 60))
                    VStack(spacing: 0) {
                        ForEach(0..<20, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(base).frame(height: 2)
                        }
                    }
                }
            }.frame(width: 20)
        }.accessibilityLabel("\(name) output \(Int(state.levels[channel])) decibels")
    }
}
