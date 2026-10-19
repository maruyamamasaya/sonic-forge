import Foundation

struct MIDIFilePart: Identifiable {
    let id: String
    let name: String
    let channel: Int
    let notes: [PerformanceNote]
    let pedals: [PerformancePedal]
    var pitchRange: ClosedRange<Int> { notes.map(\.pitch).min()!...notes.map(\.pitch).max()! }
    func performance(start: Double, end: Double, tempo: Double, transpose: Int = 0) throws -> PerformanceDocument {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end-start <= 256 else { throw AudioError.invalid("読み込む範囲は0より長く、256拍以内にしてください。") }
        let selected = notes.compactMap { n -> PerformanceNote? in
            let a = max(start,n.beat), b = min(end,n.beat+n.duration)
            guard b > a else { return nil }
            return PerformanceNote(beat:a-start, duration:b-a, pitch:n.pitch, velocity:n.velocity, channel:n.channel)
        }
        var canonicalPedals: [PerformancePedal] = []
        for p in pedals {
            if canonicalPedals.last?.beat == p.beat { canonicalPedals[canonicalPedals.count-1] = p }
            else if canonicalPedals.last?.down != p.down { canonicalPedals.append(p) }
        }
        var selectedPedals = canonicalPedals.filter { $0.beat >= start && $0.beat < end }.map { PerformancePedal(beat:$0.beat-start, down:$0.down, channel:$0.channel) }
        if canonicalPedals.last(where: { $0.beat < start })?.down == true { selectedPedals.insert(PerformancePedal(beat:0,down:true,channel:channel),at:0) }
        if selectedPedals.last?.down == true { selectedPedals.append(PerformancePedal(beat:end-start,down:false,channel:channel)) }
        let value = PerformanceDocument(name:String(name.prefix(80)),tempo:tempo,transpose:transpose,notes:selected,pedals:selectedPedals)
        _ = try value.events()
        return value
    }
}
struct MIDIFileSong {
    let name: String
    let tempo: Double
    let parts: [MIDIFilePart]
    let endBeat: Double
    let warnings: [String]
}

/// Bounded SMF 0/1 reader. No soundfonts, network, or executable MIDI payloads.
enum MIDIFileImport {
    static let maximumBytes = 1024*1024
    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var left: Int { bytes.count-index }
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= left else { throw AudioError.invalid("MIDIのデータが途中で切れています。") }
            defer { index += count }; return Array(bytes[index..<index+count])
        }
        mutating func byte() throws -> UInt8 { try take(1)[0] }
        mutating func number(_ count: Int) throws -> Int { try take(count).reduce(0) { $0*256+Int($1) } }
        mutating func vlq() throws -> Int {
            var value = 0
            for _ in 0..<4 { let b = try byte(); value = value*128+Int(b&127); if b < 128 { return value } }
            throw AudioError.invalid("MIDIの可変長数値が無効です。")
        }
    }
    private struct Event { let tick: Int; let track: Int; let channel: Int; let kind: Int; let a: Int; let b: Int }
    static func load(_ url: URL) throws -> MIDIFileSong {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maximumBytes else { throw AudioError.invalid("MIDIは1 MB以内にしてください。") }
        let handle = try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        return try decode(handle.read(upToCount:maximumBytes+1) ?? Data(),name:url.deletingPathExtension().lastPathComponent)
    }
    static func decode(_ data: Data, name: String = "MIDI") throws -> MIDIFileSong {
        guard !data.isEmpty, data.count <= maximumBytes else { throw AudioError.invalid("MIDIは1 MB以内にしてください。") }
        var reader = Reader(bytes:Array(data))
        guard try reader.take(4) == Array("MThd".utf8) else { throw AudioError.invalid("Standard MIDI Fileではありません。") }
        let headerSize = try reader.number(4)
        guard headerSize >= 6, headerSize <= reader.left else { throw AudioError.invalid("MIDIヘッダーが無効です。") }
        let format = try reader.number(2), trackCount = try reader.number(2), division = try reader.number(2)
        guard (format == 0 || format == 1), (1...64).contains(trackCount), format != 0 || trackCount == 1 else { throw AudioError.invalid("MIDI形式0/1・最大64トラックに対応しています。") }
        guard division > 0, division & 0x8000 == 0 else { throw AudioError.invalid("SMPTE時間形式には未対応です。PPQ形式を選んでください。") }
        _ = try reader.take(headerSize-6)
        var events: [Event] = [], names: [Int:String] = [:], endTicks: [Int:Int] = [:]
        var tempos: [(Int,Int)] = [(0,500000)]
        var ignored = 0, eventCount = 0
        for track in 0..<trackCount {
            guard try reader.take(4) == Array("MTrk".utf8) else { throw AudioError.invalid("MIDIトラックが見つかりません。") }
            let length = try reader.number(4)
            var r = Reader(bytes:try reader.take(length)), tick = 0, running: UInt8 = 0, ended = false
            while r.left > 0 {
                try Task.checkCancellation()
                eventCount += 1
                guard eventCount <= 100000 else { throw AudioError.invalid("MIDIのイベントが多すぎます。") }
                tick += try r.vlq()
                guard tick <= 1_000_000_000 else { throw AudioError.invalid("MIDIの時間が長すぎます。") }
                let first = try r.byte()
                let status: UInt8
                var firstData: UInt8?
                if first < 128 {
                    guard running >= 0x80, running < 0xF0 else { throw AudioError.invalid("MIDIのrunning statusが無効です。") }
                    status = running; firstData = first
                } else { status = first }
                if status == 0xFF {
                    running = 0
                    let type = try r.byte(), count = try r.vlq(), bytes = try r.take(count)
                    if type == 0x2F {
                        guard count == 0, r.left == 0 else { throw AudioError.invalid("MIDIの終端イベントが無効です。") }
                        ended = true; break
                    }
                    if type == 3, let text = String(bytes:bytes,encoding:.utf8) {
                        names[track] = String(text.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(60))
                    }
                    if type == 0x51 {
                        guard count == 3 else { throw AudioError.invalid("MIDIテンポが無効です。") }
                        let microseconds = bytes.reduce(0) { $0*256+Int($1) }
                        guard microseconds > 0, tempos.count < 1024 else { throw AudioError.invalid("MIDIテンポが無効、または多すぎます。") }
                        tempos.append((tick,microseconds))
                    }
                } else if status == 0xF0 || status == 0xF7 {
                    running = 0; let count = try r.vlq(); _ = try r.take(count); ignored += 1
                } else {
                    guard status < 0xF0 else { throw AudioError.invalid("MIDIのシステムイベントが未対応です。") }
                    running = status
                    let firstValue: UInt8
                    if let firstData { firstValue = firstData } else { firstValue = try r.byte() }
                    let kind = Int(status & 0xF0), a = Int(firstValue)
                    let b = (kind == 0xC0 || kind == 0xD0) ? 0 : Int(try r.byte())
                    guard a < 128, b < 128 else { throw AudioError.invalid("MIDIのデータバイトが無効です。") }
                    if [0x80,0x90].contains(kind) || (kind == 0xB0 && a == 64) {
                        events.append(Event(tick:tick,track:track,channel:Int(status&15),kind:kind,a:a,b:b))
                    } else { ignored += 1 }
                }
            }
            guard ended else { throw AudioError.invalid("MIDIトラックの終端がありません。") }
            endTicks[track] = tick
        }
        guard reader.left == 0 else { throw AudioError.invalid("MIDI末尾に未対応のデータがあります。") }
        let orderedTempos = tempos.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }.map(\.element)
        var ticks = [0], seconds = [0.0], micros = [500000]
        for t in orderedTempos {
            if t.0 == ticks.last! { micros[micros.count-1] = t.1 }
            else { seconds.append(seconds.last!+Double(t.0-ticks.last!)*Double(micros.last!)/Double(division)/1_000_000); ticks.append(t.0); micros.append(t.1) }
        }
        let baseTempo = max(40,min(240,60_000_000/Double(micros[0])))
        func beat(_ tick: Int) -> Double {
            var lo = 0, hi = ticks.count
            while lo+1 < hi { let mid = (lo+hi)/2; if ticks[mid] <= tick { lo = mid } else { hi = mid } }
            return (seconds[lo]+Double(tick-ticks[lo])*Double(micros[lo])/Double(division)/1_000_000)*baseTempo/60
        }
        let endBeat = beat(endTicks.values.max() ?? 0)
        guard endBeat.isFinite, endBeat > 0, endBeat*60/baseTempo <= 1800, events.count <= 32768 else { throw AudioError.invalid("MIDIは30分・32768イベント以内にしてください。") }
        var warnings: [String] = []
        if ticks.count > 1 { warnings.append("テンポ変化は演奏時刻に換算します。構成では共通テンポで伸縮します。") }
        if baseTempo != 60_000_000/Double(micros[0]) { warnings.append("元のテンポは範囲外のため、時刻を保って40〜240 BPMへ換算します。") }
        if ignored > 0 { warnings.append("音色指定・音量CC・ピッチベンド・SysEx等の\(ignored)件は反映しません。楽器を手動で割り当ててください。") }
        var parts: [MIDIFilePart] = [], retrigger = 0, unmatched = 0, dangling = 0
        let groups = Dictionary(grouping:events,by:{ "\($0.track):\($0.channel)" })
        let keys = groups.keys.sorted { a,b in let x = groups[a]!.first!, y = groups[b]!.first!; return x.track == y.track ? x.channel < y.channel : x.track < y.track }
        for key in keys {
            let list = groups[key]!, track = list[0].track, channel = list[0].channel
            var active: [Int:(Int,Int)] = [:], notes: [PerformanceNote] = [], pedals: [PerformancePedal] = []
            func close(_ pitch: Int, _ tick: Int) {
                if let (start,velocity) = active.removeValue(forKey:pitch), tick > start {
                    notes.append(PerformanceNote(beat:beat(start),duration:beat(tick)-beat(start),pitch:pitch,velocity:velocity,channel:channel))
                }
            }
            for e in list {
                if e.kind == 0xB0 { pedals.append(PerformancePedal(beat:beat(e.tick),down:e.b >= 64,channel:channel)) }
                else if e.kind == 0x90 && e.b > 0 {
                    if active[e.a] != nil { close(e.a,e.tick); retrigger += 1 }
                    active[e.a] = (e.tick,e.b)
                } else if active[e.a] != nil { close(e.a,e.tick) } else { unmatched += 1 }
            }
            for pitch in Array(active.keys) { close(pitch,endTicks[track]!); dangling += 1 }
            if !notes.isEmpty {
                let title = names[track].flatMap { $0.isEmpty ? nil : $0 } ?? "Track \(track+1)"
                parts.append(MIDIFilePart(id:key,name:"\(title) · Ch \(channel+1)",channel:channel,notes:notes.sorted { $0.beat < $1.beat },pedals:pedals))
            }
        }
        guard !parts.isEmpty else { throw AudioError.invalid("演奏できる音符がありません。") }
        if retrigger+unmatched+dangling > 0 { warnings.append("同音の再押鍵\(retrigger)件は前の音を離鍵、対応しない離鍵\(unmatched)件は無視、終端の保持音\(dangling)件は離鍵しました。") }
        if parts.contains(where:{$0.channel == 9}) { warnings.append("Ch 10はドラム音名です。音源マップを再現せず、割り当てたサンプラーを音程変更して鳴らします。") }
        return MIDIFileSong(name:String(name.prefix(80)),tempo:baseTempo,parts:parts,endBeat:endBeat,warnings:warnings)
    }
}
private extension Character {
    var isASCIIControl: Bool { unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
}
