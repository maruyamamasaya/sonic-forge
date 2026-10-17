# 現在のアーキテクチャ

## System Overview / Data Flow
```text
SwiftUI StudioView → MainActor PlayerModel → AVAudioPlayer → macOS system output
                         │
NSOpenPanel / DemoAudio → AudioAsset.load（background）→ peak配列 → Canvas波形
```

## Technology Stack / Important Dependencies
macOS 14以上、Swift 5言語モード、XcodeのSwiftコンパイラ。
SwiftUI / AppKit / AVFoundation / CoreMIDI / CombineとPython標準ライブラリのみ。第三者パッケージなし。
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
app/Resources/AppIcon.pngをアイコンの原本とし、scripts/build.shが標準サイズのiconsetとICNSを生成してResourcesへ同梱する。Info.plistのCFBundleIconFileで参照する。
scripts/build.shがbuild/SonicForge.appを生成してローカル用ad-hoc署名を行う。配布・公証・CIは未整備。
検証コマンドは [TESTING.md](TESTING.md)、起動は [OPERATIONS.md](OPERATIONS.md)。

## Sample Instrument
InstrumentSampleが全体／選択をバックグラウンドでFloat32 PCMへ取り込む（最大30秒・デコード後64 MB）。
SampleInstrumentは8本のSourceNode（InstrumentVoice＋ADSR）→ 各Varispeed → 出力Mixer → system outputで和音を演奏。
再生速度は2^((鍵盤ノート−基準音)/12)。画面はC3〜C5の25鍵、基準音もC3〜C5。MIDIは基準音±24半音の範囲で演奏可能。高い音ほど短くなる。
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

## MIDI Input
MIDIInputがCoreMIDIのクライアント・入力ポート・選択したsourceを管理する。初期値はNone、機器接続の自動選択や保存はしない。
CoreMIDI通知でsource一覧を再取得し、選択sourceの消失時は切断してMIDI所有の音を停止する。
MIDIReceiverがコールバック上でパケットを走査し、MIDIByteParserでMIDI 1.0のNote On/OffとCC64/120/121/123を抽出。
running statusとパケット跨ぎを保持し、リアルタイムバイトは無視。SysEx・system commonでrunning statusを解除する。
受信は直列ロックで順序を保ち、Main QueueへFIFOで渡す。接続世代を照合し旧ポート由来の配送を破棄する。音声コールバックからMIDIやUIを操作しない。
PlayerModel.NoteInput.midi(channel)が既存の入力所有権へ接続。チャンネル別離鍵と全音停止は他入力の保持を尊重する。
MIDI履歴は離鍵後の余韻もCC120と切断で止めるため保持し、全音停止時に破棄する。
Test inputはMIDISourceCreateで実際の仮想sourceを公開し、MIDIReceivedから通常の受信ポートへ送る。
背景・ダイアログ中は発音を抑制し、フォーカス喪失で停止。終了時にポート・仮想source・クライアントを破棄する。
[判断](decisions/0011-midi-input.md)。

## Velocity / Sustain / Performance Presets
InstrumentVoiceが押鍵時のvelocity/127を保持し、ADSRとは独立した固定倍率としてPCMへ乗算する。
MIDIは1〜127、0は離鍵。画面・PC鍵盤は従来通り127。複数入力の同音は共有ボイスのため最初の押鍵の強さを維持する。
PlayerModelはチャンネル別CC64状態を持ち、離鍵時にmidiの所有権をmidiSustainへ移す。ペダル解除でその所有権のみを外し、他の保持入力がなければReleaseへ進む。
ペダル中の同音再押鍵はそのチャンネルの古い保持を外して再発音。CC123は通常離鍵としてペダルを尊重し、CC120・切断は余韻とペダル状態も解除する。
CC121はペダルを解除して待機中の離鍵を処理する。全音停止・フォーカス喪失・素材交換は全チャンネルを初期化する。
MIDIPerformancePresetは時刻とMIDIバイト列のイベントを返す。playPerformanceがMainActor Taskで順番に仮想sourceへ送る。
プリセット停止時はTaskをキャンセルして接続世代を更新し、古い配送と残音を破棄する。通常終了は最後のNote Off/CC64 OffからADSRの余韻を残す。
これはプリセットを元にしたデータ演奏で、AI生成やサンプル精度のシーケンサーではない。[判断](decisions/0012-midi-expression-presets.md)。

## Editable Performances
PerformanceDocument.swiftが音符・ペダルを拍単位で保持し、tempo/transpose/velocityPercentを適用してMIDIイベントへ変換する。
値・重複・同時保持音数・ペダル終端を検証し、再生時は楽器音域も検証する。形式の正本は[演奏形式v1](PERFORMANCE_FORMAT.md)。
PerformanceEditorが独立したシートで編集し、MIDIInputが演奏ファイルとdirtyを管理する。音色ファイルと保存状態は分離する。
開始時に検証済みイベントを固定し、既存の仮想CoreMIDI再生とキャンセル処理を再利用。JSON読込にコード実行は伴わない。
[判断](decisions/0013-editable-performances.md)。

## Instrument Library
InstrumentLibraryは楽器ファイルの絶対パスをUserDefaultsのinstrumentLibraryPathsV1へ保存する参照型の一覧。成功した通常保存・読込で自動登録し、Add FilesはInstrumentDocumentの全検証後に登録する。既存の最後の楽器も起動時復元成功で登録される。検索はファイル名、同名は親フォルダ表示で区別する。
LibraryViewは本体を維持する独立シート。未保存楽器の置換は確認後に既存のloadInstrumentへ渡す。一覧から除外しても原本は削除しない。移動・削除された原本はMissingとなり、新しい場所から再追加する。
試聴は専用SampleInstrumentで基準音をvelocity100・−18 dBで演奏し、0.8秒後に離鍵、開始3秒後に強制停止する（長いAttack/Releaseの全体確認ではない）。PCM・ADSR・ループを使用し、本体の楽器・dirty・起動時復元先を変更しない。本体停止後に開始し、選択/検索変更・閉じる・アプリ非アクティブ・終了時に停止。バックグラウンド復号後も世代を検査し、閉じた後の遅延発音を防ぐ。試聴の一時音源は停止時に清掃。
Add DemosはApplication Support/SonicForge/Library内に同一合成素材のMetal/Softを作成し登録する。既存同名ファイルは上書きしない。外部ファイルはコピー・再帰走査しない。クラウド同期・タグ・DB・外部APIは未実装。

## Performance Generation
StudioViewのCompose… → PerformanceComposer（候補・取消世代） → PerformanceBrief / PerformanceGeneration（指示・共通schema・検証） → CodexPerformanceClient / OpenAIPerformanceClient。Codexはインストール済みネイティブ実行ファイルをProcess引数配列＋stdinで起動。空の一時作業領域・read-only・ignore-user-config・ephemeral、shell/unified_exec/apps/hooks無効、web_search無効。標準出力・標準エラーは保存せず最終JSONファイルだけを検証。120秒で停止、終了時に一時領域を清掃する。Nodeラッパーは既知の同梱バイナリへ解決してNodeのPATHに依存しない。
OpenAIはFoundation URLSessionのResponses API＋strict JSON Schema。接続先固定、リダイレクト禁止、キャッシュなし、store=false、6000出力トークン・90秒リクエスト/100秒リソース・応答1 MB上限。キーはメモリのみ。未完了・refusal・HTTPエラー・形式不正を拒否し生応答やキーをログへ出さない。音源・原本パスは添付せず、音楽の指示と基準音だけを送る。TypeScriptアプリではないためAI SDKは追加しない。
Other AIは共通の指示とschemaをコピーしJSONを貼り付ける手動接続。Demoは2種類の決定的パターンでAI呼び出しと区別。いずれもPerformanceDocument.events(root:)に加え4小節・64音符制限を適用。候補は既存演奏を変えず、Use & Playで未保存演奏の置換確認後にMIDIInput.applyGeneratedPerformanceへ渡す。ファイル保存先を解除しdirtyにする。本体楽器は保持。シート閉鎖完了後に既存の仮想CoreMIDI経路で再生する。閉じる・取消・指示変更・方式変更で旧結果は採用されない。操作・対応範囲は[AI_GENERATION.md](AI_GENERATION.md)。

## Ensemble
EnsembleModelが最大4つのEnsemblePartをメモリ内に保持する。各パートはPCM/Root/ADSR/LoopのスナップショットとPerformanceDocumentを持つ。InstrumentDocumentからの読込はバックグラウンドで全検証し、PCM取得後に展開一時領域を清掃する。失敗時は以前の割り当てを保持する。演奏読込は既存形式の検証を再利用する。
全パートを開始前に検証し、各演奏のtempoを共通テンポへ置換したコピーからイベントを作り、startBeat × 60 / tempo秒を音符・離鍵・ペダルへ加算する。開始位置は有限数0〜256拍。終了拍もシフト後の最後のイベントから求める。元の演奏データは書き換えない。各パートの±24半音・8音上限は既存検証を再利用。1つでも未割当/不正なら全体を開始しない。ミュートしたパートも検証する。
再生ごとに1つのAVAudioEngineとパート別Mixerを準備。SampleInstrumentのdestination引数で出力を分け、各MixerをmainMixerの別busへ接続する。単一楽器の既定出力は従来通りmainMixer。EnsembleVoiceはパート別にMIDIの押鍵所有権/チャンネルCC64を管理し、同音程の別パートを干渉させない。ペダル中の同音再押鍵は再発音する。
全イベントを1つのTaskから単調時計の共通開始時刻に対する絶対秒で配送する。睡眠時間の積算によるずれは避けるが、サンプル精度ではない。再生後はパートごとのReleaseを待ち、最大6秒で終了。停止はTask取消/世代変更/全ボイス停止/共通engine破棄。閉じる・アプリ非アクティブ・本体の音声再生/全音停止でも終了する。
パートMixerの音量・ミュートは30 Hzで更新。共通出力は最大4パート分の固定1/4ヘッドルームと専用Masterを使用。各サンプラーの1/8ヘッドルームは維持する。パートと共通出力それぞれの実RMSを表示し、本体のメーターとは区別。割り当てはシートを閉じても保持し、保存した構成は起動時に復元する。操作は[ENSEMBLE.md](ENSEMBLE.md)。

## Ensemble Persistence
EnsembleDocumentが.sfensemble v5を管理（v1〜v3はセクションなし、v1/v2はrepeatCount=1、v1は開始位置0で読込）。EnsembleSnapshotへ全パートのPCM/設定・演奏・mixと共通tempo/masterを固定し、InstrumentDocument.makeArchiveの楽器v4をJSON内へ直接埋め込む。二重base64や外部パス参照を避ける。InstrumentDocument.restoreを共有し、読み込み用一時音源は各パートのPCM取得後に清掃。全パートの検証/復号成功後にだけモデルへ反映する。
保存/復号はバックグラウンド。保存は検証・全エンコード・サイズ確認後のatomic write。モデルはbusyで編集を止め、保存中に内部状態が変わった場合もrevisionでdirty解除を防ぐ。名前/開始位置/繰り返し回数/音量/Muteのパートpublisherとtempo/master/割り当て変更を監視し、voice/meter/位置更新は監視しない。形式の正本は[ENSEMBLE_FORMAT.md](ENSEMBLE_FORMAT.md)。
EnsembleModelは最後に正常保存/読込したパスだけをUserDefaultsのlastEnsemblePathV1へ保持。PlayerModel.startSessionから一度だけ復元し、本体の楽器復元とは独立。無音・停止状態で復元し、自動再生しない。欠落/破損時は構成エラーを表示して手動Openへ導く。復元前の構成や正常な保存先を失敗で更新しない。

## Ensemble WAV Export
EnsembleExportは検証済みEnsembleSnapshotを固定し、既存EnsembleVoice/SampleInstrumentを共通engineのoffline manual renderingへ接続。イベントを48 kHzの切上げフレームへ変換し、同時刻の順序を保ちイベント境界でバッファを分割する。共通テンポ・開始位置・mix/headroomは実再生と同じ。最後のイベント＋最大Release＋50 msまで書く。ステレオFloat32・256 MiB上限。
MainActor上で非実時間レンダーを行い、32ブロックごとにyield/進捗更新、各ブロックで取消を検査。ライブengineとは分離。UIのbusyで設定変更を止める。保存先横の一時WAVを閉じた後にPOSIX renameで公開し、失敗/取消は一時ファイルだけを清掃。元WAV/参照楽器/構成の同一実体を開始時と公開直前に検査する。

## Ensemble Timeline
EnsembleTimeline.lengthはPerformanceDocument.eventsを60 BPMへ換算し、最後のイベント拍を返す（休符/ペダルを含み、Releaseは除く）。EnsembleTimelineViewは24 px/拍、4拍目盛・水平スクロールで全パートを表示。クリップのGestureStateでドラッグ中の位置をプレビューし、終了時のみmovePartへ渡す。¼拍丸め/0〜256制限とcanEditを適用し、既存startBeatのdirty/保存/演奏/出力へ接続。別の配置データは持たない。

## Ensemble Repeats
EnsemblePart/SnapshotにrepeatCount（整数1〜16）を保持。EnsembleTimeline.eventsが元演奏を拍へ換算し、ceil(最終イベント拍)間隔で全MIDIイベントを展開、STARTと共通tempoを適用。ライブtimelineとWAV出力が同じ関数を使う。前回の終端イベントは同時刻の次回開始より先に置き、ペダル/離鍵の所有状態を正しく解除する。元演奏を改変しない。repeatedLengthが同じ規則でタイムラインの幅と区切りを生成する。保存v3で回数だけを同梱する。

## Song Sections
EnsembleSectionは安定UUID/name/beatsを持ち、EnsembleModel.sectionsが配列順に連結する。part.sectionIDは任意参照、nilは従来のSong基準。EnsembleSectionsがID/長さ/名前と参照/演奏終端の範囲を検証。ライブ/WAV/タイムラインは同じ累積offsetをstartBeatへ足す。元演奏は改変しない。全セクション合計も曲長の下限となり、ライブTaskは最後のイベント後も宣言された曲末まで取消可能に待機する。WAVも同じ曲末＋余韻までレンダー。
構成v4はsectionsとpart.sectionIDを保存し、全検証後に置換。削除は参照中のセクションを拒否する。ドラッグは割り当て先の範囲へ制限し、数値入力で超過した場合は開始/保存/出力を拒否する。編集UIはEnsembleSectionsView、帯と絶対拍はEnsembleTimelineView。

## Shared Instrument Clips
既存EnsemblePartのperformance/startBeat/repeatCount/sectionIDを最初の演奏として保ち、additionalClips（0〜7個）を追加。EnsembleClipはUUID/演奏/相対開始/回数/任意sectionID。allClipsが先頭演奏と追加を統一し、EnsembleClips.validate/eventsをライブとWAVで共有する。パートごとにサンプラーとmixを一つだけ使う。セクションごとの楽器PCM複製はしない。
同一パート内の演奏区間の重複を拒否し、接する境界では前クリップの終端イベントを先に配送する。最大8クリップ/パート。セクション削除の参照検査は追加分も対象。追加配列publisherでdirty追跡、保存v5は音源をパートに一度、追加配置をadditionalClipsへ保存。旧v1〜v4は追加なし。UIはEnsembleClipEditorで演奏/配置を独立編集し、タイムラインは一行内に全クリップを描く。

クリップ複製はEnsembleModel.duplicateClipが新UUID・別sectionIDの値コピーを作り、全候補をEnsembleClips.validateで検証した後に追加する。演奏/START/REPEATを保持し、失敗は原子的に拒否。EnsembleDuplicateMenuとEnsembleClipEditorが操作入口。保存形式はv5を継続する。
