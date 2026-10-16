# 現在のアーキテクチャ

## System Overview / Data Flow
```text
SwiftUI StudioView → MainActor PlayerModel → AVAudioPlayer → macOS system output
                         │
NSOpenPanel / DemoAudio → AudioAsset.load（background）→ peak配列 → Canvas波形
```

## Technology Stack / Important Dependencies
macOS 14以上、Swift 5言語モード、XcodeのSwiftコンパイラ。
SwiftUI / AppKit / AVFoundation / CombineとPython標準ライブラリのみ。第三者パッケージなし。
当初提案のC++ / JUCEから、最初のMac専用版はApple標準基盤へ変更。[判断理由](decisions/0002-native-playback.md)。

## Directory Structure / Main Components
- app/: UI、再生状態、WAV解析、デモ合成。領域ルールは [app/AGENTS.md](app/AGENTS.md)。
- tests/: ファイル解析と再生状態のテスト。
- scripts/: ローカル.app生成、テスト、標準Verify。
- decisions/、sessions/: 判断と作業結果。
主要シンボルは [CODEMAP.md](CODEMAP.md)。

## Audio / Storage
AVAudioFileでFloat32へデコードし、最大1800バケット／チャンネルのピークを作る。
解析は16384フレームずつバックグラウンドで読み、UIにはピークだけ渡す。
AVAudioPlayerが再生を担当。30 HzのUIタイマーで位置・レベルを更新。メーターはソース平均レベルにゲインを加えた表示で、物理出力の計測ではない。
デモは8秒・48 kHz・16-bit・ステレオの減衰音を一時ディレクトリに合成。通常終了時に削除。ユーザー音源は変更しない。

## API / Database / Authentication / External Services
いずれも未導入。実行時ネットワーク通信なし。macOSの既定出力を使用する。

## Deployment
scripts/build.shがbuild/SonicForge.appを生成してローカル用ad-hoc署名を行う。配布・公証・CIは未整備。
検証コマンドは [TESTING.md](TESTING.md)、起動は [OPERATIONS.md](OPERATIONS.md)。
