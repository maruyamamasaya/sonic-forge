#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path build/module-cache \
    -target "$(uname -m)-apple-macosx14.0" \
    app/AudioAsset.swift app/WaveformEditor.swift app/SelectionAudio.swift app/WAVExport.swift app/ADSREnvelope.swift app/SampleInstrument.swift app/InstrumentDocument.swift app/InstrumentLibrary.swift app/EnsembleModel.swift app/PerformanceDocument.swift app/PerformanceGeneration.swift app/CodexPerformanceClient.swift app/PerformanceComposer.swift app/MIDIInput.swift app/PlayerModel.swift tests/EnsembleTests.swift tests/LibraryTests.swift tests/GenerationTests.swift tests/PerformanceTests.swift tests/MIDITests.swift tests/EnvelopeTests.swift tests/AudioTests.swift -o build/AudioTests
build/AudioTests "$@"
