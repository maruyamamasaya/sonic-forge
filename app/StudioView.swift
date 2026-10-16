import SwiftUI

private let amber = Color(red: 0.96, green: 0.72, blue: 0.33)
private let base = Color(red: 0.075, green: 0.09, blue: 0.105)
private let panel = Color(red: 0.105, green: 0.125, blue: 0.14)
private let muted = Color(red: 0.64, green: 0.69, blue: 0.73)
private let line = Color.white.opacity(0.10)

struct StudioView: View {
    @ObservedObject var model: PlayerModel
    private var asset: AudioAsset? { model.asset }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(line).frame(height: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text(asset.map { $0.isDemo ? "Metal Hit — Demo" : $0.url.deletingPathExtension().lastPathComponent } ?? "Sample Studio")
                            .font(.system(size: 22, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if asset?.isDemo == true {
                            Text("DEMO").font(.system(size: 10, weight: .semibold)).foregroundStyle(amber)
                                .padding(.horizontal, 9).padding(.vertical, 5).background(amber.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        Spacer()
                        if model.loading { ProgressView().controlSize(.small) }
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
                        WaveCanvas(peaks: asset.peaks, fraction: fraction, overview: true, seek: model.seek)
                            .frame(height: 62).background(panel).overlay { Rectangle().stroke(line) }
                            .contentShape(Rectangle())
                            .accessibilityLabel("Full file overview. Click to seek.")
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "waveform").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(amber)
                            Text("Your sound starts here").font(.system(size: 20, weight: .medium))
                            Text("Open a WAV file or explore with a synthesized demo.")
                                .foregroundStyle(muted)
                            Button("Load Demo") { Task { await model.loadDemo() } }.buttonStyle(StudioButton(primary: true)).disabled(model.loading)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(line).frame(width: 1)
                inspector.frame(width: 268).background(panel)
            }
            Rectangle().fill(line).frame(height: 1)
            transport
            Rectangle().fill(line).frame(height: 1)
            HStack {
                Circle().fill(model.playing ? amber : muted).frame(width: 5, height: 5)
                Text(model.loading ? "Loading audio…" : asset == nil ? "No audio file loaded" : asset!.isDemo ? "Synthesized demo · Ready to play" : "WAV loaded · \(asset!.url.lastPathComponent)").lineLimit(1)
                Spacer()
                Text("System output").foregroundStyle(muted)
                Text("•").foregroundStyle(muted)
                Text("SonicForge 0.1").foregroundStyle(muted)
            }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 20).frame(height: 32)
        }
        .background(base).foregroundStyle(Color(red: 0.86, green: 0.89, blue: 0.91))
        .preferredColorScheme(.dark)
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
            Button("Load Demo") { Task { await model.loadDemo() } }.buttonStyle(StudioButton())
                .help("Generate an original 8-second stereo demo; no audio file needed")
            Button("Open WAV…") { model.open() }.buttonStyle(StudioButton()).keyboardShortcut("o", modifiers: .command)
        }.padding(.horizontal, 20).frame(height: 56).background(panel).disabled(model.loading)
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
                meter(channel: 0, name: "L")
                meter(channel: 1, name: "R")
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
    private func meter(channel: Int, name: String) -> some View {
        VStack(spacing: 6) {
            Text(name).font(.system(size: 10)).foregroundStyle(muted)
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.35))
                    Rectangle().fill(amber).frame(height: geometry.size.height * CGFloat((model.levels[channel] + 60) / 60))
                    VStack(spacing: 0) {
                        ForEach(0..<20, id: \.self) { _ in
                            Spacer(minLength: 0)
                            Rectangle().fill(base).frame(height: 2)
                        }
                    }
                }
            }.frame(width: 20)
        }.accessibilityLabel("\(name) output \(Int(model.levels[channel])) decibels")
    }
    private func waveform(asset: AudioAsset) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<9) { index in
                    Text(String(format: "%.1fs", asset.duration * Double(index) / 8))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted)
                    if index < 8 { Spacer(minLength: 0) }
                }
            }.frame(height: 25)
            WaveCanvas(peaks: asset.peaks, fraction: fraction, overview: false, seek: model.seek)
                .background(base).overlay { Rectangle().stroke(line) }
                .contentShape(Rectangle())
                .accessibilityLabel("Audio waveform. Click to change playback position.")
            Slider(value: Binding(get: { model.position }, set: { model.seek($0 / asset.duration) }), in: 0...asset.duration)
                .tint(amber).accessibilityLabel("Playback position").padding(.top, 8)
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
                .buttonStyle(StudioButton(primary: true)).keyboardShortcut(.space, modifiers: []).help("Play / Pause · Space").accessibilityLabel(model.playing ? "Pause" : "Play")
            Text("\(timeLabel(model.position)) / \(timeLabel(asset?.duration ?? 0))")
                .font(.system(size: 19, weight: .medium, design: .monospaced)).padding(.horizontal, 22).padding(.vertical, 13)
                .background(Color.black.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.leading, 24)
            Text("Space  Play / Pause").font(.system(size: 10)).foregroundStyle(muted).padding(.leading, 24)
            Spacer()
        }.padding(.vertical, 20).background(panel).disabled(asset == nil || model.loading)
    }
}

struct StudioButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(primary ? Color.black.opacity(0.85) : Color.white.opacity(0.88))
            .background(primary ? amber.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.065))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.07)) }
    }
}

struct WaveCanvas: View {
    let peaks: [[Float]]
    let fraction: Double
    let overview: Bool
    var seek: ((Double) -> Void)? = nil
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let lane = size.height / CGFloat(max(1, peaks.count))
                for (channel, values) in peaks.enumerated() {
                    let middle = lane * (CGFloat(channel) + 0.5)
                    var grid = Path()
                    for index in 0...8 {
                        let x = size.width * CGFloat(index) / 8
                        grid.move(to: CGPoint(x: x, y: CGFloat(channel) * lane))
                        grid.addLine(to: CGPoint(x: x, y: CGFloat(channel + 1) * lane))
                    }
                    grid.move(to: CGPoint(x: 0, y: middle)); grid.addLine(to: CGPoint(x: size.width, y: middle))
                    context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    var wave = Path()
                    for index in values.indices {
                        let x = CGFloat(index) / CGFloat(max(1, values.count - 1)) * size.width
                        let height = CGFloat(min(1, values[index])) * lane * 0.44
                        wave.move(to: CGPoint(x: x, y: middle - max(0.35, height)))
                        wave.addLine(to: CGPoint(x: x, y: middle + max(0.35, height)))
                    }
                    context.stroke(wave, with: .color(overview ? muted.opacity(0.65) : amber), lineWidth: max(0.65, size.width / CGFloat(max(1, values.count))))
                    if !overview {
                        context.draw(Text(channel == 0 ? (peaks.count == 1 ? "MONO" : "L") : "R").font(.system(size: 10)).foregroundColor(muted), at: CGPoint(x: 18, y: CGFloat(channel) * lane + 16))
                    }
                }
                var playhead = Path()
                let x = max(0, min(size.width - 1, size.width * fraction))
                playhead.move(to: CGPoint(x: x, y: 0)); playhead.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(playhead, with: .color(amber), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in seek?(Double(event.location.x / max(1, geometry.size.width))) })
        }
    }
}
