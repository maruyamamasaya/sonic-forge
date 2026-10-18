import SwiftUI

struct PerformanceEditor: View {
    @ObservedObject var midi: MIDIInput
    @Environment(\.dismiss) private var dismiss
    @State private var showPedals = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("演奏データの編集").font(.system(size: 12, weight: .semibold)).tracking(1)
                Text(midi.performanceDirty ? "● 未保存" : midi.customPerformance ? "保存済み" : "内蔵プリセット").foregroundStyle(.secondary)
                Spacer()
                Button("開く…") { midi.openPerformancePanel() }
                Button("保存…") { midi.savePerformancePanel() }.disabled(validationError != nil)
                Button("閉じる") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("演奏名", text: $midi.performance.name).font(.title3)
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text(String(format: "テンポ・%.1f BPM", midi.performance.tempo))
                    Slider(value: $midi.performance.tempo, in: 40...240, step: 1).accessibilityIdentifier("Performance tempo").accessibilityLabel("演奏テンポ")
                }
                VStack(alignment: .leading) {
                    Text(String(format: "移調・%+d 半音", midi.performance.transpose))
                    Stepper("半音", value: $midi.performance.transpose, in: -24...24).labelsHidden().accessibilityIdentifier("Performance transpose").accessibilityLabel("演奏全体の移調")
                }
                VStack(alignment: .leading) {
                    Text(String(format: "強弱・%.1f %%", midi.performance.velocityPercent))
                    Slider(value: $midi.performance.velocityPercent, in: 25...150, step: 1).accessibilityIdentifier("Performance dynamics").accessibilityLabel("演奏全体の強弱")
                }
            }.font(.system(size: 10)).tint(accent)
            HStack {
                Picker("演奏イベント", selection: $showPedals) { Text("音符").tag(false); Text("ペダル").tag(true) }.pickerStyle(.segmented).frame(width: 200)
                Spacer()
                Button("プリセットに戻す") { midi.resetPerformance() }
                Button(showPedals ? "ペダル追加" : "音符追加") {
                    if showPedals { midi.performance.pedals.append(PerformancePedal(beat: 0, down: false)) }
                    else { midi.performance.notes.append(PerformanceNote(beat: 0, duration: 1, pitch: 60, velocity: 80)) }
                }.disabled(showPedals ? midi.performance.pedals.count >= 64 : midi.performance.notes.count >= 256)
            }
            HStack {
                Text("開始拍").frame(width: 70)
                if !showPedals {
                    Text("長さ").frame(width: 70); Text("音程").frame(width: 120); Text("強弱").frame(width: 75)
                } else { Text("ペダル").frame(width: 120) }
                Text("チャンネル").frame(width: 80)
                Spacer()
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    if showPedals {
                        ForEach(midi.performance.pedals.indices, id: \.self) { index in
                            HStack {
                                TextField("ペダルの開始拍", value: pedal(index).beat, format: .number).frame(width: 70)
                                Toggle("踏む", isOn: pedal(index).down).frame(width: 120)
                                TextField("チャンネル", value: Binding(get: { pedal(index).wrappedValue.channel + 1 }, set: { pedal(index).wrappedValue.channel = max(1, min(16, $0)) - 1 }), format: .number).frame(width: 80)
                                Spacer()
                                Button("削除") { if midi.performance.pedals.indices.contains(index) { midi.performance.pedals.remove(at: index) } }
                            }
                        }
                    } else {
                        ForEach(midi.performance.notes.indices, id: \.self) { index in
                            HStack {
                                TextField("音符の開始拍", value: note(index).beat, format: .number).frame(width: 70)
                                TextField("音符の長さ", value: note(index).duration, format: .number).frame(width: 70)
                                HStack {
                                    TextField("音符の音程", value: note(index).pitch, format: .number).frame(width: 50)
                                    Text((0...127).contains(note(index).wrappedValue.pitch) ? NotePitch.name(note(index).wrappedValue.pitch) : "—").foregroundStyle(accent)
                                }.frame(width: 120)
                                TextField("音符の強弱", value: note(index).velocity, format: .number).frame(width: 75)
                                TextField("チャンネル", value: Binding(get: { note(index).wrappedValue.channel + 1 }, set: { note(index).wrappedValue.channel = max(1, min(16, $0)) - 1 }), format: .number).frame(width: 80)
                                Spacer()
                                Button("削除") { if midi.performance.notes.indices.contains(index) { midi.performance.notes.remove(at: index) } }
                            }
                        }
                    }
                }.textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
            }.frame(maxHeight: .infinity)
            if let validationError { Text(validationError).foregroundStyle(.orange).lineLimit(2) }
            else { Text("\(midi.performance.notes.count) 音符・\(midi.performance.pedals.count) ペダル操作・演奏できます").foregroundStyle(.secondary) }
            if let error = midi.error { Text(error).foregroundStyle(.orange).lineLimit(2) }
            Text("開始・長さは拍数、音程はMIDI番号0〜127、チャンネルは1〜16。閉じて自動演奏で確認できます。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(22).frame(width: 780, height: 570).background(Color(red: 0.075, green: 0.09, blue: 0.105))
            .preferredColorScheme(.dark).controlSize(.small)
    }
    private func note(_ index: Int) -> Binding<PerformanceNote> {
        Binding(get: { midi.performance.notes.indices.contains(index) ? midi.performance.notes[index] : PerformanceNote(beat: 0, duration: 1, pitch: 60, velocity: 80) },
                set: { if midi.performance.notes.indices.contains(index) { midi.performance.notes[index] = $0 } })
    }
    private func pedal(_ index: Int) -> Binding<PerformancePedal> {
        Binding(get: { midi.performance.pedals.indices.contains(index) ? midi.performance.pedals[index] : PerformancePedal(beat: 0, down: false) },
                set: { if midi.performance.pedals.indices.contains(index) { midi.performance.pedals[index] = $0 } })
    }
    private var validationError: String? {
        do { _ = try midi.performance.events(root: midi.performanceRoot); return nil }
        catch { return error.localizedDescription }
    }
}
