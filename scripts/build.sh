#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/SonicForge.app/Contents/MacOS build/module-cache
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
    -target "$(uname -m)-apple-macosx14.0" \
    app/AudioAsset.swift app/WaveformEditor.swift app/SelectionAudio.swift app/WAVExport.swift app/ADSREnvelope.swift app/SampleInstrument.swift app/InstrumentDocument.swift app/PerformanceDocument.swift app/MIDIInput.swift app/PlayerModel.swift app/PerformanceEditor.swift app/InstrumentKeyboard.swift app/StudioView.swift app/SonicForgeApp.swift \
    -o build/SonicForge.app/Contents/MacOS/SonicForge
cat > build/SonicForge.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SonicForge</string>
<key>CFBundleIdentifier</key><string>local.sonicforge.studio</string>
<key>CFBundleName</key><string>SonicForge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>local.sonicforge.instrument</string>
<key>UTTypeDescription</key><string>SonicForge Instrument</string>
<key>UTTypeConformsTo</key><array><string>public.json</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>sfinstrument</string></array></dict>
</dict></array>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/SonicForge.app
printf 'Built: build/SonicForge.app\n'
