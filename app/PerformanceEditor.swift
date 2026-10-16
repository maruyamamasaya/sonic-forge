import SwiftUI

struct PerformanceEditor: View {
    @ObservedObject var midi: MIDIInput
    @Environment(\.dismiss) private var dismiss
    @State private var showPedals = false
    private let accent = Color(red: 0.96, green: 0.72, blue: 0.33)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PERFORMANCE EDITOR").font(.system(size: 12, weight: .semibold)).tracking(1)
                Text(midi.performanceDirty ? "● Unsaved" : midi.customPerformance ? "Saved" : "Factory").foregroundStyle(.secondary)
                Spacer()
                Button("Open…") { midi.openPerformancePanel() }
                Button("Save…") { midi.savePerformancePanel() }.disabled(validationError != nil)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("Performance name", text: $midi.performance.name).font(.title3)
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text(String(format: "TEMPO · %.1f BPM", midi.performance.tempo))
                    Slider(value: $midi.performance.tempo, in: 40...240, step: 1).accessibilityLabel("Performance tempo")
                }
                VStack(alignment: .leading) {
                    Text(String(format: "TRANSPOSE · %+d st", midi.performance.transpose))
                    Stepper("Semitones", value: $midi.performance.transpose, in: -24...24).labelsHidden().accessibilityLabel("Performance transpose")
                }
                VStack(alignment: .leading) {
                    Text(String(format: "VELOCITY · %.1f %%", midi.performance.velocityPercent))
                    Slider(value: $midi.performance.velocityPercent, in: 25...150, step: 1).accessibilityLabel("Performance dynamics")
                }
            }.font(.system(size: 10)).tint(accent)
            HStack {
                Picker("Events", selection: $showPedals) { Text("Notes").tag(false); Text("Pedal").tag(true) }.pickerStyle(.segmented).frame(width: 200)
                Spacer()
                Button("Reset factory") { midi.resetPerformance() }
                Button(showPedals ? "Add pedal" : "Add note") {
                    if showPedals { midi.performance.pedals.append(PerformancePedal(beat: 0, down: false)) }
                    else { midi.performance.notes.append(PerformanceNote(beat: 0, duration: 1, pitch: 60, velocity: 80)) }
                }.disabled(showPedals ? midi.performance.pedals.count >= 64 : midi.performance.notes.count >= 256)
            }
            HStack {
                Text("BEAT").frame(width: 70)
                if !showPedals {
                    Text("LENGTH").frame(width: 70); Text("PITCH").frame(width: 120); Text("VELOCITY").frame(width: 75)
                } else { Text("PEDAL").frame(width: 120) }
                Text("CHANNEL").frame(width: 80)
                Spacer()
            }.font(.system(size: 9)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    if showPedals {
                        ForEach(midi.performance.pedals.indices, id: \.self) { index in
                            HStack {
                                TextField("Pedal beat", value: pedal(index).beat, format: .number).frame(width: 70)
                                Toggle("Down", isOn: pedal(index).down).frame(width: 120)
                                TextField("Channel", value: Binding(get: { pedal(index).wrappedValue.channel + 1 }, set: { pedal(index).wrappedValue.channel = max(1, min(16, $0)) - 1 }), format: .number).frame(width: 80)
                                Spacer()
                                Button("Remove") { if midi.performance.pedals.indices.contains(index) { midi.performance.pedals.remove(at: index) } }
                            }
                        }
                    } else {
                        ForEach(midi.performance.notes.indices, id: \.self) { index in
                            HStack {
                                TextField("Note beat", value: note(index).beat, format: .number).frame(width: 70)
                                TextField("Note length", value: note(index).duration, format: .number).frame(width: 70)
                                HStack {
                                    TextField("Note pitch", value: note(index).pitch, format: .number).frame(width: 50)
                                    Text((0...127).contains(note(index).wrappedValue.pitch) ? NotePitch.name(note(index).wrappedValue.pitch) : "—").foregroundStyle(accent)
                                }.frame(width: 120)
                                TextField("Note velocity", value: note(index).velocity, format: .number).frame(width: 75)
                                TextField("Channel", value: Binding(get: { note(index).wrappedValue.channel + 1 }, set: { note(index).wrappedValue.channel = max(1, min(16, $0)) - 1 }), format: .number).frame(width: 80)
                                Spacer()
                                Button("Remove") { if midi.performance.notes.indices.contains(index) { midi.performance.notes.remove(at: index) } }
                            }
                        }
                    }
                }.textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
            }.frame(maxHeight: .infinity)
            if let validationError { Text(validationError).foregroundStyle(.orange).lineLimit(2) }
            else { Text("\(midi.performance.notes.count) notes · \(midi.performance.pedals.count) pedal events · Ready to play").foregroundStyle(.secondary) }
            if let error = midi.error { Text(error).foregroundStyle(.orange).lineLimit(2) }
            Text("Beat / Length = quarter notes · Pitch = MIDI 0–127 · Channel = 1–16 · Close to audition with Auto play")
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
