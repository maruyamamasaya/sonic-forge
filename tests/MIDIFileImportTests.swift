import Foundation

@MainActor enum MIDIFileImportTests {
    static func u32(_ n: Int) -> [UInt8] { [UInt8((n>>24)&255),UInt8((n>>16)&255),UInt8((n>>8)&255),UInt8(n&255)] }
    static func vlq(_ n: Int) -> [UInt8] { var value=n, bytes=[UInt8(n&127)]; value >>= 7; while value>0 { bytes.insert(UInt8(value&127)|128,at:0); value >>= 7 }; return bytes }
    static func file(_ tracks:[[UInt8]],format:Int=1,division:Int=480) -> Data {
        var b=Array("MThd".utf8)+u32(6)+[0,UInt8(format),0,UInt8(tracks.count),UInt8(division>>8),UInt8(division&255)]
        for t in tracks { b += Array("MTrk".utf8)+u32(t.count)+t }; return Data(b)
    }
    static let end:[UInt8] = [0,255,47,0]
    static func rejects(_ data: Data) { do { _ = try MIDIFileImport.decode(data); fatalError("Invalid MIDI accepted") } catch {} }
    static func run() async throws {
        // Format 0, running status and velocity-zero off; tempo default 120.
        let track:[UInt8] = [0,0x90,60,90]+vlq(480)+[60,0]+end
        let zero=try MIDIFileImport.decode(file([track],format:0))
        precondition(zero.parts.count==1 && zero.tempo==120 && zero.parts[0].notes[0].duration==1)
        let tempo:[UInt8] = [0,255,81,3,7,161,32]+vlq(480)+[255,81,3,15,66,64]+end
        let two:[UInt8] = [0,0x90,60,90]+vlq(960)+[0x80,60,0]+end
        let mapped=try MIDIFileImport.decode(file([tempo,two]))
        precondition(abs(mapped.parts[0].notes[0].duration-3)<1e-8 && mapped.warnings.contains(where:{$0.contains("テンポ変化")}))
        let pedal:[UInt8] = [0,0xB2,64,127,0,0x92,60,80]+vlq(480)+[0x82,60,0]+vlq(480)+[0xB2,64,0]+end
        let sustain=try MIDIFileImport.decode(file([pedal],format:0))
        let excerpt=try sustain.parts[0].performance(start:0.5,end:1.5,tempo:120)
        precondition(excerpt.notes[0].beat==0 && excerpt.notes[0].duration==0.5 && excerpt.pedals.first?.down==true && excerpt.pedals.last?.down==false)
        let atBoundary = MIDIFilePart(id:"boundary",name:"boundary",channel:0,notes:[PerformanceNote(beat:0,duration:2,pitch:60,velocity:80)],pedals:[PerformancePedal(beat:0,down:true),PerformancePedal(beat:1,down:true)])
        let boundary = try atBoundary.performance(start:0,end:1,tempo:120)
        precondition(boundary.pedals.count==2 && boundary.pedals.last?.down==false)
        let duplicate:[UInt8] = [0,0x90,60,80]+vlq(240)+[0x90,60,90]+vlq(240)+[0x80,60,0,0,0x80,60,0]+end
        let repaired=try MIDIFileImport.decode(file([duplicate],format:0))
        precondition(repaired.parts[0].notes.count==2 && repaired.parts[0].notes[0].duration==0.5)
        let sysex:[UInt8] = [0,240,2,1,247,0,0x90,60,80]+vlq(480)+[0x80,60,0]+end
        let skipped = try MIDIFileImport.decode(file([sysex],format:0))
        precondition(skipped.warnings.count>0)
        rejects(Data()); rejects(file([track],format:2)); rejects(file([track],format:0,division:0xE728))
        rejects(file([[0,60,80]+end],format:0)); rejects(file([[0x81,0x81,0x81,0x81,0,0x90,60,80]+end],format:0))
        rejects(file([[0,0x90,60,200]+end],format:0)); rejects(file([[0,255,81,2,1,2]+end],format:0))
        rejects(file([[0,0x90,60,80]],format:0)); rejects(Data(file([track],format:0).dropLast()))
        let many=PerformanceDocument(name:"poly",notes:(60...68).map{PerformanceNote(beat:0,duration:1,pitch:$0,velocity:80)},pedals:[])
        do { _ = try many.events(); fatalError("polyphony accepted") } catch {}
        // Fixed public MIDI fixture: actual bytes, not a transcription made by the test.
        let real=URL(fileURLWithPath:"tests/Fixtures/gymnopedie_1.mid")
        let satie=try MIDIFileImport.load(real)
        precondition(satie.parts.count==2 && satie.parts.map(\.notes.count)==[181,101] && satie.tempo==60 && satie.endBeat==141)
        for p in satie.parts { _ = try p.performance(start:0,end:satie.endBeat,tempo:satie.tempo) }
        let sample=PitchEstimationTests.sample { t,_ in 0.3*sin(2 * .pi * 261.625*t) }
        let instrument=EnsembleInstrument(sample:sample,root:60,envelope:.standard,loop:SampleLoop(endFrame:Int64(sample.buffer.frameLength)),name:"MIDI test")
        let performance=try zero.parts[0].performance(start:0,end:1,tempo:120)
        let snapshot=EnsembleSnapshot(tempo:120,masterDB:-6,parts:[EnsemblePartSnapshot(name:"track",instrument:instrument,performance:performance,gainDB:0,muted:false)])
        let defaults=UserDefaults(suiteName:"MIDIImport-"+UUID().uuidString)!
        let model=EnsembleModel(defaults:defaults)
        precondition(model.importMIDI(snapshot) && model.parts.count==1 && model.dirty)
        precondition(model.restoreSongEdit() && model.parts.isEmpty)
        precondition(model.restoreSongEdit(redo:true) && model.parts.count==1)
        let bad=EnsembleSnapshot(tempo:1,masterDB:snapshot.masterDB,parts:snapshot.parts)
        let old=model.parts[0].id
        precondition(!model.importMIDI(bad) && model.parts[0].id==old)
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let path=dir.appendingPathComponent("midi.sfensemble")
        try EnsembleDocument.save(try model.snapshot(),to:path)
        let restored=try EnsembleDocument.load(path)
        precondition(restored.parts[0].performance==performance)
        let wav=dir.appendingPathComponent("midi.wav")
        try await EnsembleExport.write(restored,to:wav)
        let audio=try AudioAsset.load(wav)
        precondition(audio.channels==2 && audio.sampleRate==48000 && audio.peaks.flatMap{$0}.max()!>0)
        print("PASS: SMF 0/1/running/tempo-map/CC64/excerpt/retrigger/malformed bounds, Satie, atomic import undo/redo, archive and WAV")
    }
}
