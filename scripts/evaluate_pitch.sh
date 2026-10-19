#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 2 ]; then
    echo 'Usage: sh scripts/evaluate_pitch.sh build/real-audio-low-root build/new-pitch-results.json' >&2
    exit 2
fi
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
    app/AudioAsset.swift app/WaveformEditor.swift app/ADSREnvelope.swift app/SampleInstrument.swift \
    app/PitchEstimation.swift scripts/pitch_evaluation.swift -o build/PitchEvaluation
build/PitchEvaluation "$1" "$2"
