#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/SonicForge.app/Contents/MacOS build/SonicForge.app/Contents/Resources build/module-cache
icon_source=app/Resources/AppIcon.png
iconset=build/AppIcon.iconset
test -f "$icon_source"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o build/SonicForge.app/Contents/Resources/AppIcon.icns
mkdir -p build/SonicForge.app/Contents/Resources/Textures
for wood in walnut oak cherry; do
    test -s "app/Resources/Textures/$wood.png"
    cp "app/Resources/Textures/$wood.png" "build/SonicForge.app/Contents/Resources/Textures/$wood.png"
done
xcrun swiftc -swift-version 5 -O -module-cache-path build/module-cache \
    -target "$(uname -m)-apple-macosx14.0" \
    app/AudioAsset.swift app/WaveformEditor.swift app/SelectionAudio.swift app/WAVExport.swift app/ADSREnvelope.swift app/SampleInstrument.swift app/InstrumentDocument.swift app/InstrumentLibrary.swift app/EnsembleModel.swift app/EnsembleDocument.swift app/EnsembleExport.swift app/EnsembleTimeline.swift app/EnsembleSections.swift app/EnsembleClips.swift app/PerformanceDocument.swift app/PerformanceGeneration.swift app/CodexPerformanceClient.swift app/PerformanceComposer.swift app/MIDIInput.swift app/PlayerModel.swift app/PerformanceEditor.swift app/PerformanceComposerView.swift app/InstrumentKeyboard.swift app/LibraryView.swift app/PerformanceNoteLayout.swift app/PerformanceNoteView.swift app/WorkspaceAppearance.swift app/WorkspaceSectionInspector.swift app/EnsembleTimelineView.swift app/EnsembleSectionsView.swift app/EnsembleDuplicateMenu.swift app/EnsembleClipEditor.swift app/EnsembleView.swift app/WorkspaceInspector.swift app/WorkspaceView.swift app/StudioView.swift app/SonicForgeApp.swift \
    -o build/SonicForge.app/Contents/MacOS/SonicForge
cat > build/SonicForge.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SonicForge</string>
<key>CFBundleIdentifier</key><string>local.sonicforge.studio</string>
<key>CFBundleName</key><string>SonicForge</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>local.sonicforge.instrument</string>
<key>UTTypeDescription</key><string>SonicForge Instrument</string>
<key>UTTypeConformsTo</key><array><string>public.json</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>sfinstrument</string></array></dict>
</dict><dict>
<key>UTTypeIdentifier</key><string>local.sonicforge.performance</string>
<key>UTTypeDescription</key><string>SonicForge Performance</string>
<key>UTTypeConformsTo</key><array><string>public.json</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>sfperformance</string></array></dict>
</dict><dict>
<key>UTTypeIdentifier</key><string>local.sonicforge.ensemble</string>
<key>UTTypeDescription</key><string>SonicForge Ensemble</string>
<key>UTTypeConformsTo</key><array><string>public.json</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>sfensemble</string></array></dict>
</dict></array>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/SonicForge.app
printf 'Built: build/SonicForge.app\n'
