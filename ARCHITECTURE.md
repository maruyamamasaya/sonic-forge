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
AVAudioFileでFloat32へデコードし、最大115200バケット／チャンネルのピークを作る。
解析は16384フレームずつバックグラウンドで読み、UIにはピークだけ渡す。
AVAudioPlayerが再生を担当。30 HzのUIタイマーで位置・レベルを更新。メーターはソース平均レベルにゲインを加えた表示で、物理出力の計測ではない。
WaveformEditorがソースフレーム単位の選択と、正規化した表示範囲（1〜32倍ズーム）を管理。
Canvasは表示範囲内のピークを画面幅に再集約し、選択を半透明アンバーで描く。概要波形は常に全体を表示する。
選択再生はSelectionAudioが指定フレームだけを一時Float32 CAFへコピーし、別のAVAudioPlayerで再生する。
再生位置表示には選択開始時刻を加算し、音声の終端はファイル長で制限する。根拠は [選択再生の判断](decisions/0003-selection-preview.md)。
WAVExportは選択を32-bit Float WAVへ書き出す。保存先と同じディレクトリの一時ファイルを完成後にrenameし、書き込み途中のファイルを公開しない。元音源との同一パス・symlink・hardlinkを拒否する。
デモは8秒・48 kHz・16-bit・ステレオの減衰音を一時ディレクトリに合成。通常終了時に削除。ユーザー音源は変更しない。

## API / Database / Authentication / External Services
いずれも未導入。実行時ネットワーク通信なし。macOSの既定出力を使用する。

## Deployment
scripts/build.shがbuild/SonicForge.appを生成してローカル用ad-hoc署名を行う。配布・公証・CIは未整備。
検証コマンドは [TESTING.md](TESTING.md)、起動は [OPERATIONS.md](OPERATIONS.md)。

## Sample Instrument
InstrumentSampleが全体／選択をバックグラウンドでFloat32 PCMへ取り込む（最大30秒・デコード後64 MB）。
SampleInstrumentはAVAudioEngineのPlayerNode → Varispeed → Mixer → system outputで単音を演奏。
再生速度は2^((鍵盤ノート−基準音)/12)。C3〜C5の25鍵、基準音もC3〜C5。高い音ほど短くなる。
デモの基準音はA3、外部WAVは手動指定の初期値C4。自動ピッチ検出は行わない。
MainActorで発音・停止を制御し、キー操作時のファイル読み込みは行わない。世代番号で古い完了通知を無視する。
Mixer tapのRMSを右メーターへ表示。音声スレッドのメーター更新はロックが取れなければ待たずに破棄する。
従来の試聴とは排他再生。停止・音源交換・基準音変更・フォーカス喪失で発音を止める。
