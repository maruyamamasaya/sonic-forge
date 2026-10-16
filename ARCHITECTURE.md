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
SampleInstrumentは8本のSourceNode（InstrumentVoice＋ADSR）→ 各Varispeed → 共通Mixer → system outputで和音を演奏。
再生速度は2^((鍵盤ノート−基準音)/12)。C3〜C5の25鍵、基準音もC3〜C5。高い音ほど短くなる。
デモの基準音はA3、外部WAVは手動指定の初期値C4。自動ピッチ検出は行わない。
MainActorで発音・停止を制御し、キー操作時のファイル読み込みは行わない。完了状態はUIタイマーで確認し、音声コールバックからUIを更新しない。
Mixer tapのRMSを右メーターへ表示。音声スレッドのメーター更新はロックが取れなければ待たずに破棄する。
従来の試聴とは排他再生。停止・音源交換・基準音変更・フォーカス喪失で発音を止める。離鍵はADSRのReleaseへ移行する。

## Instrument Documents
InstrumentDocumentがversion 4の単一JSONファイル（.sfinstrument）を読み書きする。
取り込み済みPCMを32-bit Float WAVに変換してbase64で同梱し、基準音・ADSR・ループとサンプル表示名を保存。外部音源パスへの依存はない。
保存はバックグラウンド生成＋atomic write。読み込みはサイズ・版・基準音・音源を検証後、一時領域へ展開して既存エンジンへ渡す。
全検証と試聴プレイヤー準備に成功してから現在の状態を置き換え、失敗時は元の楽器を保持する。
最後に保存／開いたファイルのパスだけをアプリのUserDefaultsに保持し、起動時に復元。未発見・破損時は説明付きでデモへフォールバック。
展開先は通常終了・楽器交換時に削除。元の楽器ファイルは変更しない。波形編集の選択・ズーム、Master Gain、未保存の変更は保存しない。

## ADSR
ADSREnvelope.swiftが線形Attack / Decay / Sustain / Releaseを管理。A・D・Rは0〜5秒、Sは0〜1。
SourceNode内でサンプルごとに乗算し、速度変更の前段では計算用レートに音程倍率を掛けて、音程に依存しない秒数を維持する。
InstrumentVoiceはPCM位置とエンベロープを短いロックで保護。レンダー側はtry-lockのみで待たず、取得不可ならそのブロックを無音にする。ファイルI/OやUI通知はしない。
パラメーターは押鍵時にスナップショット化し、変更は次の発音から反映。Releaseは現在のレベルから減衰し、サンプル末尾では先に停止。
形式v1はA=0 / D=0 / S=1 / R=0で読み込み、従来の鳴り方を維持。v2はADSRを必須とし、不正値は読み込みを拒否する。

## Sample Loop
SampleLoopは取り込み済みPCM先頭からの開始フレームと排他的終了フレーム、enabledを保持する。
InstrumentVoiceは先頭から再生し、終了で開始へ戻る。Release中も折り返してエンベロープ終端で停止する。
押鍵時のスナップショットで、編集は次の発音に反映。無効時は従来のEOF停止。
保存v3はループを必須検証し、v1/v2は全体範囲・OFFとして復元。[判断](decisions/0008-sample-loop.md)。

## Loop Crossfade
SampleLoop.crossfadeFramesは0〜min(ループ長の半分, 100 ms相当のフレーム)。0で従来通り。
末尾Nフレームを先頭Nフレームと線形混合し、折り返し後はstart+Nから続ける。重みの和は1で、ステレオ共通の重みを使用。
ADSR乗算の前で処理し、Releaseでも継続。再生用スナップショットのみ変更し元PCMは不変。
重複分だけ定常ループ周期は短くなり、音程変更時は速度に従いフェード時間も変化する。
v4で保存。v3の欠落値は0、v1/v2は従来通りループOFF。[判断](decisions/0009-loop-crossfade.md)。

## Polyphony / Input
8スロットが独立したPCM位置、ADSR、ループスナップショット、Varispeedを持つ。PCMバッファだけを共有する。
同音の再押鍵は同スロットを再使用。空き→最古のRelease中→最古の保持音の順で割り当てる。
各スロット出力を1/8に固定し、合算後にMaster Gainを適用。発音数に追従する自動音量変更はしない。
PlayerModelはscreen/computer/demoのノート所有権を保持し、最後の入力が離れた音だけをReleaseする。
activeNotesは保持音、soundingVoicesはRelease中を含む実ボイス数。タイマーが自然終了とスティールを同期する。
PCキーのkeyDown/keyUpは既存ローカルモニターで処理し、リピートは無視、テキスト入力・ダイアログ・修飾キー付き操作は保持する。
停止・基準音変更・音源交換・フォーカス喪失は全音停止。Hold keysとデモ和音は演奏中だけの状態で保存しない。
OutputMeterStateをOutputMeterColumnが直接購読し、メーター更新による鍵盤全体の再レイアウトを避ける。
[判断](decisions/0010-polyphony.md)。
