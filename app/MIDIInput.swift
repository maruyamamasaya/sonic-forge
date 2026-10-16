import Foundation
import Combine
import CoreMIDI

struct MIDIMessage: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case on(Int), off, allOff, silence, sustain(Bool), resetControllers }
    let channel: UInt8
    let note: Int
    let kind: Kind
}

/// MIDI 1 byte stream. Running status and messages split across packets are retained.
struct MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    mutating func consume(_ bytes: [UInt8]) -> [MIDIMessage] {
        var result: [MIDIMessage] = []
        for byte in bytes {
            if byte >= 0xF8 { continue }
            if byte & 0x80 != 0 {
                data.removeAll(keepingCapacity: true)
                status = byte < 0xF0 ? byte : 0
                continue
            }
            guard status >= 0x80 else { continue }
            data.append(byte)
            let type = status & 0xF0
            let count = type == 0xC0 || type == 0xD0 ? 1 : 2
            guard data.count == count else { continue }
            let channel = status & 0x0F
            if type == 0x90 { result.append(MIDIMessage(channel: channel, note: Int(data[0]), kind: data[1] == 0 ? .off : .on(Int(data[1])))) }
            if type == 0x80 { result.append(MIDIMessage(channel: channel, note: Int(data[0]), kind: .off)) }
            if type == 0xB0 && (data[0] == 120 || data[0] == 123) {
                result.append(MIDIMessage(channel: channel, note: 0, kind: data[0] == 120 ? .silence : .allOff))
            }
            if type == 0xB0 && data[0] == 64 { result.append(MIDIMessage(channel: channel, note: 0, kind: .sustain(data[1] >= 64))) }
            if type == 0xB0 && data[0] == 121 { result.append(MIDIMessage(channel: channel, note: 0, kind: .resetControllers)) }
            data.removeAll(keepingCapacity: true)
        }
        return result
    }
}

private final class MIDIReceiver: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = MIDIByteParser()
    let deliver: @Sendable ([MIDIMessage]) -> Void
    init(deliver: @escaping @Sendable ([MIDIMessage]) -> Void) { self.deliver = deliver }
    func receive(_ list: UnsafePointer<MIDIPacketList>) {
        lock.lock(); defer { lock.unlock() }
        var messages: [MIDIMessage] = []
        var packet = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIPacketList>.offset(of: \.packet)!).assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<list.pointee.numPackets {
            let bytes = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!).assumingMemoryBound(to: UInt8.self)
            messages += parser.consume(Array(UnsafeBufferPointer(start: bytes, count: Int(packet.pointee.length))))
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
        if !messages.isEmpty { deliver(messages) }
    }
}

struct MIDIInputSource: Identifiable, Equatable {
    let id: MIDIEndpointRef
    let name: String
}

struct MIDIPerformanceEvent: Equatable {
    let time: Double
    let bytes: [UInt8]
}

enum MIDIPerformancePreset: String, CaseIterable, Identifiable {
    case softChords = "Soft chords", arpeggio = "Arpeggio", pedalStudy = "Pedal phrase"
    var id: String { rawValue }
    var events: [MIDIPerformanceEvent] {
        switch self {
        case .softChords:
            var events: [MIDIPerformanceEvent] = []
            for (index, notes) in [[60, 64, 67], [60, 65, 69], [59, 62, 67], [60, 64, 67]].enumerated() {
                let velocity = [45, 75, 105, 60][index]
                events.append(MIDIPerformanceEvent(time: Double(index) * 1.3, bytes: notes.flatMap { [0x90, UInt8($0), UInt8(velocity)] }))
                events.append(MIDIPerformanceEvent(time: Double(index) * 1.3 + 0.9, bytes: notes.flatMap { [0x80, UInt8($0), 0] }))
            }
            return events
        case .arpeggio:
            return [60, 64, 67, 72, 67, 64, 60, 55, 60, 64, 67, 72].enumerated().flatMap { index, note in
                [MIDIPerformanceEvent(time: Double(index) * 0.24, bytes: [0x90, UInt8(note), UInt8(50 + index % 4 * 20)]),
                 MIDIPerformanceEvent(time: Double(index) * 0.24 + 0.18, bytes: [0x80, UInt8(note), 0])]
            }
        case .pedalStudy:
            return [MIDIPerformanceEvent(time: 0, bytes: [0xB0, 64, 127, 0x90, 60, 40]),
                    MIDIPerformanceEvent(time: 0.2, bytes: [0x80, 60, 0]),
                    MIDIPerformanceEvent(time: 0.4, bytes: [0x90, 64, 80]),
                    MIDIPerformanceEvent(time: 0.6, bytes: [0x80, 64, 0]),
                    MIDIPerformanceEvent(time: 0.8, bytes: [0x90, 67, 120]),
                    MIDIPerformanceEvent(time: 1, bytes: [0x80, 67, 0]),
                    MIDIPerformanceEvent(time: 2, bytes: [0xB0, 64, 0])]
        }
    }
}

@MainActor
final class MIDIInput: ObservableObject {
    @Published private(set) var sources: [MIDIInputSource] = []
    @Published private(set) var selected: MIDIEndpointRef = 0
    @Published private(set) var error: String?
    @Published private(set) var testSource: MIDIEndpointRef = 0
    @Published private(set) var testingChord = false
    @Published var testVelocity = 100
    @Published var performancePreset = MIDIPerformancePreset.softChords
    @Published private(set) var performing = false
    private var performanceTask: Task<Void, Never>?
    var onMessages: (([MIDIMessage]) -> Void)?
    var onReset: (() -> Void)?
    private var client: MIDIClientRef = 0
    private var port: MIDIPortRef = 0
    private var generation: UInt64 = 0

    func start() {
        guard client == 0 else { return }
        let status = MIDIClientCreateWithBlock("SonicForge Input" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        guard status == noErr else { error = "MIDIを開始できませんでした（\(status)）。"; return }
        refresh()
    }
    func refresh() {
        guard client != 0 else { return }
        var found: [MIDIInputSource] = []
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
            found.append(MIDIInputSource(id: source, name: name?.takeRetainedValue() as String? ?? "MIDI Input"))
        }
        if found != sources { sources = found }
        if selected != 0 && !found.contains(where: { $0.id == selected }) { select(0) }
    }
    func select(_ source: MIDIEndpointRef) {
        guard source == 0 || sources.contains(where: { $0.id == source }) else { return }
        stopPerformance(reconnect: false)
        generation &+= 1
        if port != 0 { MIDIPortDispose(port); port = 0 }
        selected = 0; testingChord = false; onReset?()
        guard source != 0 else { error = nil; return }
        let token = generation
        let receiver = MIDIReceiver { [weak self] messages in
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.selected == source else { return }
                self.onMessages?(messages)
            }
        }
        let created = MIDIInputPortCreateWithBlock(client, "SonicForge Notes" as CFString, &port) { list, _ in receiver.receive(list) }
        let connected = created == noErr ? MIDIPortConnectSource(port, source, nil) : created
        guard connected == noErr else {
            if port != 0 { MIDIPortDispose(port); port = 0 }
            error = "MIDI入力へ接続できませんでした（\(connected)）。"; return
        }
        selected = source; error = nil
    }
    func createTestInput() {
        start()
        guard client != 0 else { return }
        if testSource == 0 {
            let status = MIDISourceCreate(client, "SonicForge Test Keyboard" as CFString, &testSource)
            guard status == noErr else { error = "仮想MIDIを作成できませんでした（\(status)）。"; return }
        }
        refresh(); select(testSource)
    }
    func sendTest(_ bytes: [UInt8]) {
        guard testSource != 0, !bytes.isEmpty, bytes.count <= 256 else { return }
        var list = MIDIPacketList()
        let status: OSStatus = withUnsafeMutablePointer(to: &list) { pointer in
            let first = MIDIPacketListInit(pointer)
            return bytes.withUnsafeBufferPointer { bytes in
                _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, first, 0, bytes.count, bytes.baseAddress!)
                return MIDIReceived(testSource, pointer)
            }
        }
        if status != noErr { error = "仮想MIDIの送信に失敗しました（\(status)）。" }
    }
    func toggleTestChord() {
        guard selected == testSource, testSource != 0 else { return }
        stopPerformance()
        if testingChord { sendTest([0x80, 60, 0, 64, 0, 67, 0]) }
        else { let v = UInt8(max(1, min(127, testVelocity))); sendTest([0x90, 60, v, 64, v, 67, v]) }
        testingChord.toggle()
    }
    func playPerformance() {
        createTestInput()
        guard selected != 0 && selected == testSource else { return }
        let token = generation
        let events = performancePreset.events
        performing = true
        performanceTask = Task { @MainActor [weak self] in
            var previous = 0.0
            for event in events {
                do { try await Task.sleep(nanoseconds: UInt64(max(0, event.time - previous) * 1_000_000_000)) }
                catch { return }
                guard let self, !Task.isCancelled, self.generation == token else { return }
                self.sendTest(event.bytes)
                previous = event.time
            }
            guard let self, self.generation == token else { return }
            self.performing = false; self.performanceTask = nil
        }
    }
    func stopPerformance(reconnect: Bool = true) {
        let wasRunning = performanceTask != nil
        performanceTask?.cancel(); performanceTask = nil
        if performing { performing = false }
        if reconnect && wasRunning && selected == testSource { select(testSource) }
    }
    func cancelTestState() {
        if testingChord { testingChord = false }
        stopPerformance()
    }
    func close() {
        select(0)
        if testSource != 0 { MIDIEndpointDispose(testSource); testSource = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
        sources = []
    }
}
