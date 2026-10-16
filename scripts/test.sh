#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path build/module-cache \
    -target "$(uname -m)-apple-macosx14.0" \
    app/AudioAsset.swift app/WaveformEditor.swift app/SelectionAudio.swift app/WAVExport.swift app/PlayerModel.swift tests/AudioTests.swift -o build/AudioTests
build/AudioTests "$@"
