#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 1 ]; then
    echo 'Usage: sh scripts/evaluate_pitch_corpus.sh build/new-corpus-results.json' >&2
    exit 2
fi
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
    app/AudioAsset.swift app/WaveformEditor.swift app/ADSREnvelope.swift app/SampleInstrument.swift \
    app/PitchEstimation.swift app/PitchCorpus.swift scripts/pitch_corpus_evaluation.swift -o build/PitchCorpusEvaluation
build/PitchCorpusEvaluation app/Resources/PitchCorpus "$1"
