# 現在のアーキテクチャ

## System Overview / Data Flow
```text
SwiftUI WorkspaceView → EnsembleModel → 共通AVAudioEngine → macOS system output
          └ StudioView → PlayerModel → AVAudioPlayer / SampleInstrument
                  └ SeparationView → SeparationModel → Python worker → 検証WAV → PlayerModel
                         │
NSOpenPanel / DemoAudio → AudioAsset.load（background）→ peak配列 → Canvas波形
```

## Technology Stack / Important Dependencies
macOS 14以上、Swift 5言語モード、XcodeのSwiftコンパイラ。
SwiftUI / AppKit / AVFoundation / CoreMIDI / Combine / CryptoKit / SQLite3とPython標準ライブラリを使用。アプリ本体は第三者パッケージなし。音源分離の比較専用venvにはPyTorch/MLX等を任意導入済みだが、MLX推論は外部venvのworkerとしてアプリから呼び出す。詳細は[実機比較](SEPARATION_BENCHMARK.md)。
当初提案のC++ / JUCEから、最初のMac専用版はApple標準基盤へ変更。[判断理由](decisions/0002-native-playback.md)。

## Directory Structure / Main Components
- app/: UI、再生状態、WAV解析、デモ合成。領域ルールは [app/AGENTS.md](app/AGENTS.md)。
- tests/: ファイル解析と再生状態のテスト。
- scripts/: ローカル.app生成、テスト、標準Verify、任意の音源分離比較。
- benchmarks/separation/: 個人情報を除いた分離の実測値と比較用依存固定一覧。音源・重み・venvはbuild/に置く（Demucs側重みは標準Hugging Face cache）。
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
音源分離は任意の専用Python環境でローカルMLXを実行する。素材保存はローカルSQLite3を使用。アプリ利用者認証は未導入。AI生成は任意のCodex CLI / OpenAI API / 手動JSON接続。詳細は下記Performance GenerationとArrangement Proposals。macOSの既定出力を使用する。

## Deployment
app/Resources/AppIcon.pngをアイコンの原本とし、scripts/build.shが標準サイズのiconsetとICNSを生成してResourcesへ同梱する。Info.plistのCFBundleIconFileで参照する。
scripts/build.shがbuild/SonicForge.appを生成してローカル用ad-hoc署名を行う。配布・公証・CIは未整備。
検証コマンドは [TESTING.md](TESTING.md)、起動は [OPERATIONS.md](OPERATIONS.md)。

## Sample Instrument
InstrumentSampleが全体／選択をバックグラウンドでFloat32 PCMへ取り込む（最大30秒・デコード後64 MB）。
SampleInstrumentは8本のSourceNode（InstrumentVoice＋ADSR）→ 各Varispeed → 出力Mixer → system outputで和音を演奏。
再生速度は2^((鍵盤ノート−基準音)/12)。基準音はC1〜C7（MIDI24〜96）。画面は25鍵で、旧範囲C3〜C5はそのまま、低音/高音では基準音を含む音域へ切り替える。MIDIは基準音±24半音の範囲で演奏可能。高い音ほど短くなる。
合成金属音デモの基準音はA3、外部WAV/評価録音は初期値C4。音高推定は明示操作で候補を示し、採用するまで基準音を変更しない。
MainActorで発音・停止を制御し、キー操作時のファイル読み込みは行わない。完了状態はUIタイマーで確認し、音声コールバックからUIを更新しない。
Mixer tapのRMSを右メーターへ表示。音声スレッドのメーター更新はロックが取れなければ待たずに破棄する。
従来の試聴とは排他再生。停止・音源交換・基準音変更・フォーカス喪失で発音を止める。離鍵はADSRのReleaseへ移行する。

## Instrument Documents
InstrumentDocumentが単一JSONファイル（.sfinstrument）を読み書きする。来歴なしはversion 4、ありはversion 5で保存し、version 1〜5を読む。
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
Add DemosはApplication Support/SonicForge/Library内に同一合成素材のMetal/Softを作成し登録する。既存同名ファイルは上書きしない。外部ファイルはコピー・再帰走査しない。この楽器一覧のクラウド同期・タグ・DB索引・外部APIは未実装。来歴付き素材のDBは別のMaterialStoreが管理する。

## Performance Generation
StudioViewのCompose… → PerformanceComposer（候補・取消世代） → PerformanceBrief / PerformanceGeneration（指示・共通schema・検証） → CodexPerformanceClient / OpenAIPerformanceClient。Codexはインストール済みネイティブ実行ファイルをProcess引数配列＋stdinで起動。空の一時作業領域・read-only・ignore-user-config・ephemeral、shell/unified_exec/apps/hooks無効、web_search無効。標準出力・標準エラーは保存せず最終JSONファイルだけを検証。120秒で停止、終了時に一時領域を清掃する。Nodeラッパーは既知の同梱バイナリへ解決してNodeのPATHに依存しない。
OpenAIはFoundation URLSessionのResponses API＋strict JSON Schema。接続先固定、リダイレクト禁止、キャッシュなし、store=false、6000出力トークン・90秒リクエスト/100秒リソース・応答1 MB上限。キーはメモリのみ。未完了・refusal・HTTPエラー・形式不正を拒否し生応答やキーをログへ出さない。音源・原本パスは添付せず、音楽の指示と基準音だけを送る。TypeScriptアプリではないためAI SDKは追加しない。
Other AIは共通の指示とschemaをコピーしJSONを貼り付ける手動接続。Demoは2種類の決定的パターンでAI呼び出しと区別。いずれもPerformanceDocument.events(root:)に加え4小節・64音符制限を適用。候補は既存演奏を変えず、Use & Playで未保存演奏の置換確認後にMIDIInput.applyGeneratedPerformanceへ渡す。ファイル保存先を解除しdirtyにする。本体楽器は保持。シート閉鎖完了後に既存の仮想CoreMIDI経路で再生する。閉じる・取消・指示変更・方式変更で旧結果は採用されない。操作・対応範囲は[AI_GENERATION.md](AI_GENERATION.md)。

## Ensemble
EnsembleModelが最大4つのEnsemblePartをメモリ内に保持する。各パートはPCM/Root/ADSR/LoopのスナップショットとPerformanceDocumentを持つ。InstrumentDocumentからの読込はバックグラウンドで全検証し、PCM取得後に展開一時領域を清掃する。失敗時は以前の割り当てを保持する。演奏読込は既存形式の検証を再利用する。
全パートを開始前に検証し、各演奏のtempoを共通テンポへ置換したコピーからイベントを作り、startBeat × 60 / tempo秒を音符・離鍵・ペダルへ加算する。開始位置は有限数0〜256拍。終了拍もシフト後の最後のイベントから求める。元の演奏データは書き換えない。各パートの±24半音・8音上限は既存検証を再利用。1つでも未割当/不正なら全体を開始しない。ミュートしたパートも検証する。
再生ごとに1つのAVAudioEngineとパート別の入力Mixer/EQ/コンプレッサー/ディレイ/リバーブ/パンMixerを準備。SampleInstrumentのdestination/panDestination引数で出力と左右配置を分け、各パンMixerをEnsembleMasterBus.inputの別busへ接続する。単一楽器の既定出力は従来通りmainMixer。EnsembleVoiceはパート別にMIDIの押鍵所有権/チャンネルCC64を管理し、同音程の別パートを干渉させない。ペダル中の同音再押鍵は再発音する。
全イベントを1つのTaskから単調時計の共通開始時刻に対する絶対秒で配送する。睡眠時間の積算によるずれは避けるが、サンプル精度ではない。再生後はパートごとのReleaseを待ち、最大6秒で終了。停止はTask取消/世代変更/全ボイス停止/共通engine破棄。閉じる・アプリ非アクティブ・本体の音声再生/全音停止でも終了する。
パートMixerの音量・ミュートは30 Hzで更新。共通出力は最大4パート分の固定1/4ヘッドルームと専用Masterを使用。各サンプラーの1/8ヘッドルームは維持する。パートと共通出力それぞれの実RMSを表示し、本体のメーターとは区別。割り当てはシートを閉じても保持し、保存した構成は起動時に復元する。操作は[ENSEMBLE.md](ENSEMBLE.md)。

## Ensemble Persistence
EnsembleDocumentが.sfensemble v11/v12を管理（来歴付き楽器を含む場合のみv12）。旧v1〜v5のpanは中央0、v1〜v3はセクションなし、v1/v2はrepeatCount=1、v1は開始位置0で読み込む。EnsembleSnapshotへ全パートのPCM/設定・演奏・mixと共通tempo/masterを固定し、InstrumentDocument.makeArchiveの楽器v4/v5をJSON内へ直接埋め込む。二重base64や外部パス参照を避ける。InstrumentDocument.restoreを共有し、読み込み用一時音源は各パートのPCM取得後に清掃。全パートの検証/復号成功後にだけモデルへ反映する。
保存/復号はバックグラウンド。保存は検証・全エンコード・サイズ確認後のatomic write。モデルはbusyで編集を止め、保存中に内部状態が変わった場合もrevisionでdirty解除を防ぐ。名前/開始位置/繰り返し回数/音量/Muteのパートpublisherとtempo/master/割り当て変更を監視し、voice/meter/位置更新は監視しない。形式の正本は[ENSEMBLE_FORMAT.md](ENSEMBLE_FORMAT.md)。
EnsembleModelは最後に正常保存/読込したパスだけをUserDefaultsのlastEnsemblePathV1へ保持。PlayerModel.startSessionから一度だけ復元し、本体の楽器復元とは独立。無音・停止状態で復元し、自動再生しない。欠落/破損時は構成エラーを表示して手動Openへ導く。復元前の構成や正常な保存先を失敗で更新しない。

## Ensemble WAV Export
EnsembleExportは検証済みEnsembleSnapshotを固定し、既存EnsembleVoice/SampleInstrumentを共通engineのoffline manual renderingへ接続。イベントを48 kHzの切上げフレームへ変換し、同時刻の順序を保ちイベント境界でバッファを分割する。共通テンポ・開始位置・mix/headroomは実再生と同じ。曲末＋各パートのRelease/ディレイ/リバーブ余韻予算の最大値＋50 msまで書く。ステレオFloat32・256 MiB上限。
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

セクション複製はEnsembleModel.duplicateSectionが元の直後へ新UUIDの同長セクションを挿入し、全パートの所属クリップを値コピーする。後続配置と固定Songを含む全パートを候補上で検証後、dirty監視を一時抑制して全状態を反映し、一度だけ変更を記録する。既存v5/イベント展開/出力を共有する。

## Main Workspace
SonicForgeAppはWorkspaceViewを表示。PlayerModelのensemble/libraryを共有し、選択したpart/clip UUIDはView内だけで管理する。WorkspaceInspectorが最新allClipsから対象を解決し、消失時は先頭へ戻す。EnsembleTimelineViewはexpanded表示と選択コールバックを追加し、旧All Partsシートでは小型表示を維持する。ドラッグ処理は既存の境界/保存経路を共有。
editClipは最初のクリップも統一して編集し、setInstrumentSettingsは同一PCMを保持した値置換で共有音色を編集。dirty/保存/全クリップ検証は既存モデルへ集約する。Workspaceのライブラリは既存InstrumentLibraryの検索/登録/試聴を使用し、構成への割当はEnsembleModel.loadInstrumentへ渡す。
Sample Studioは同じウィンドウの表示切替で従来機能を保持。画面移動・アプリ非アクティブ・終了時に音声を停止。表示中のモードでSpace/⌘Sを振り分け、入力欄/モーダルへ割り込まない。Studio非表示中はPC鍵盤/MIDIを抑制する。保存形式v5は変更しない。

## Natural Studio / Note Rendering
WorkspaceAppearanceのWorkspaceWood/WoodSurface/CabinetButtonが自然木素材・色と立体表現を担当。素材はResources/Texturesからbundleへコピーし、NSImageをキャッシュする。テーマはAppStorageのworkspaceWoodThemeV1、構成v5は変更しない。
メインの選択はpart/clipにsection UUIDを追加。帯はEnsembleTimelineViewの同じ水平スクロール座標上に配置し、WorkspaceSectionInspectorが既存sections配列と操作へ接続する。旧EnsembleSectionsViewはAll Parts用を維持。拡大版は幅からFit倍率を求め、zoomは表示状態のみ。最初/追加クリップの操作と音声エンジンを維持。
PerformanceNoteLayoutは既存PerformanceDocument.eventsで検証し、各音符を既存の繰り返し間隔で展開する。PerformanceNoteViewのCanvasが音程/押鍵長/強弱を描画し、タイムラインの縮小プレビューに使用する。Equatable表示でvoice/meter更新時の再計算を抑える。プレビューのグリッドは長い演奏でも最大約64分割へ制限。ペダル/Releaseの長さ推定はしない。

下段のClipNoteEditor.swiftはSelectedClipNotes/ClipNoteGridで1周分を編集する。EnsembleModel.editClipNotesがコピーへ適用し、PerformanceDocument.eventsとEnsembleClips.validateによる全配置検証後に既存editClipへ渡す。音声/保存/出力に別データ層を追加しない。

音符編集履歴はEnsembleModel内のクリップ別noteHistories（各50操作）。editClipNotesが成功した前後の演奏を記録し、restoreNoteEditが期待値照合と全配置検証後にeditClipへ渡す。構成読込成功/演奏置換でリセット、保存形式は変更しない。

複数選択はClipNoteEditor内のSet<Int>。ClipNoteGridが選択/矩形範囲/移動差を通知し、EnsembleModel.editNoteGroupがコピー上で集合へ差分を適用してeditClipNotesへ一括委譲する。履歴・保存・出力の経路を追加しない。

WoodSurfaceは面のサイズへ明示的にクリップする。ヘッダーはhorizontalGrainで横木目に回転し、左右の縦木目と使い分ける。回転前の寸法を交換して縦横比を保ち、親レイアウトへ画像がはみ出さないようにする。

クオンタイズはPerformanceDocument.swiftのNoteQuantizeGridとEnsembleModel.NoteGroupAction.quantize。開始拍のみ丸め、既存editClipNotesの全配置検証と履歴経路を共有する。ClipNoteEditorの格子選択はView内状態で、保存形式は変更しない。

選択音符の強弱はNoteGroupAction.velocity/velocityOffsetで生ベロシティを変更する。Offsetは入力範囲を確認後に1〜127へ制限し、既存editClipNotesの検証/履歴/保存/出力を共有する。モードと入力値はClipNoteEditor内の表示状態。

長さ一括調整はNoteGroupAction.duration/durationScaleで押鍵長のみ変更する。Setは拍数、Scaleは倍率。比率を保持して丸めず、既存の全配置検証/履歴/保存/出力を共有する。ClipNoteEditorは表示%を倍率へ変換し、入力モードはView内状態。

クリップ間音符コピーはEnsembleModel.copiedNotesをセッション内値配列として保持。copyClipNotesで相対開始拍と実MIDI音程/強弱へ変換し、pasteClipNotesで対象の移調/強弱%を逆算してeditClipNotesへ一括委譲する。既存保存形式と履歴経路を維持。OSクリップボード/ペダルは扱わない。

## Arrangement Proposals
WorkspaceViewのArrange…がArrangementComposerViewを開き、既存PerformanceComposerの接続設定を共有する。ArrangementComposerは候補/音声込みのローカルpreview/brief/revisionを保持し、取消世代で遅い応答を捨てる。ArrangementBriefが現在の音楽データだけをJSON化して送信する。API/CLIのJSON境界は既存クライアントで共通化し、短い演奏と編曲でschema/出力枠/業務検証だけを変える。
ArrangementGeneration.materializeが既存partIDと新sectionIndexを解決し、値上のEnsembleSnapshotを全検証する。applyArrangementはrevision照合と再検証の後に既存パートへ一括反映し、楽器/パートID/名前/Master/保存先を保持、配置/tempo/mixを変更してdirty化する。音符履歴はクリア。生成候補は保存せず、採用結果は既存v5/タイムライン/ライブ/WAV経路へ流れる。上限・送信内容・操作仕様は[AI_ARRANGEMENT.md](AI_ARRANGEMENT.md)。

## Japanese Presentation and Help
主要SwiftUIビューの表示とアクセシビリティ名を日本語化。既存の明示ラベルはaccessibilityIdentifierとして保持し、JapaneseUI.swiftがプリセット/生成方式/木材名/状態接頭辞の表示変換を担当する。enum rawValue・モデルの状態メッセージ・保存データ名/キーは変更しない。StudioHelpButtonは両主要画面に共通の検索付きポップオーバーを開き、StudioHelpTopicが短い用語説明を保持する。設定のhelp属性にも説明を付ける。ヘルプと検索は表示状態のみで保存/発音/編集へ接続しない。

## Song Edit History
EnsembleModelのSongState/SongEditが全体の値スナップショットを直近50操作保持する。音源PCMは共有しコピー/再デコードしない。EnsemblePartは変更後のdidSetコールバックを親へ通知する（PublishedのwillSet時点を履歴に使わない）。モデルの複合操作はbeginSongEdit/endSongEditでネストをまとめ、差分がある確定状態だけを記録。パート参照と値を保持してUUIDを復元し、削除したパートの通知は切り離す。
restoreSongEditは再生/処理中を拒否し、既存音声を停止して一括復元、noteHistoriesを破棄、revision更新とdirty化を行う。未割当/入力途中の値も戻せるよう保存用snapshotとは分離し、再生/保存/WAV時の検証は維持。保存先/表示選択/ライブラリ/clipboard/接続設定/履歴自体は巻き戻さない。構成読込成功時のみ履歴をクリアし、形式v5を維持する。操作仕様は[ENSEMBLE](ENSEMBLE.md#曲全体の取り消しやり直し)。

## Ensemble Audition Transport
EnsemblePlayback.planはtimelineの絶対イベントから[start,end)の相対秒イベントと開始前の押鍵/サステイン状態を作る。パート/チャンネル別に保持音を復元し、Attack/サンプル先頭から再発音する。Release途中の音声位相は追跡しない。通常再生では曲末の終端MIDIも配送して余韻を待つ。範囲ループは同じengine上で全ボイス/ペダルを停止し、次周を再スケジュール。generationとTask取消で古いシーク/周回の配送を防ぐ。サンプル精度/継ぎ目なしのループではない。
EnsembleModelのpositionBeats/playbackRange/rangeLoopEnabled/playbackPassは試聴専用。pauseは位置を保持、stopは拍0、seekは再生中なら再スケジュール。編集は一時停止後に行い、次回再生は最新timeline/楽器を使う。PlayerModel.prepareEnsemblePlaybackがStudio音声を止めつつ試聴カーソルを保つ。EnsembleTransportControlsをメイン/全パートで共有し、Timelineの拍目盛りとセクション選択に接続する。試聴状態は履歴/dirty/保存/WAVに含めず、読込で初期化、範囲外となる構成短縮で解除する。

## Part Pan
EnsemblePart.panとEnsemblePartSnapshot.panは−1〜1の有限数、既定0。SongStateにも含めdirty/全体Undo/Redoを共有する。SampleInstrument.panがパートのAVAudioMixerNode.panを更新し、ライブはupdateGainsで30 Hz、EnsembleExportは固定Snapshotで同じ設定を適用。中央0では既存の出力を維持する。構成v6はpan必須、v1〜v5は中央へ移行して安価なメタデータ検証後に音源を復号。AI編曲materializeは既存panを保持し提案schemaは変更しない。UIはWorkspaceInspectorのEnsemblePanControlを全パートでも共有、addDemos(panned:)が左右配置デモの入口。

## Part EQ
PartEQは低音200 HzのlowShelf・中音1 kHz/1 octaveのparametric・高音4 kHzのhighShelfを管理する。各帯域は有限数±12 dB、0 dBはその帯域をbypass。EnsembleVoiceの音声経路はSampleInstrument→入力Mixer→AVAudioUnitEQ→AUDynamicsProcessor→AVAudioUnitDelay→AVAudioUnitReverb→パン用Mixer→mainMixer。mono素材も48 kHz stereoで処理し、メーターはEQ後を測る。単体Sample Studioは従来の経路。ライブはupdateGainsで30 Hz、WAVは同じvoiceへSnapshotのEQを設定する。SongState/dirty/Undo/RedoとAI編曲の既存値保持に含め、構成v7はEQ必須、v1〜v6はフラットへ移行する。

全パートシートはセクション/タイムライン/パート設定を一つの縦ScrollViewへまとめ、固定760 pt高でも各EQへ到達できる。トランスポートはスクロール外に固定する。

## Part Reverb
PartReverbはAVAudioUnitReverbのsmallRoomプリセットと余韻予算3秒を管理。EnsemblePart.reverbは有限数0〜100、0でbypass、1以上でwetDryMixへ適用。EnsembleVoice.setReverbをライブ30 Hz/固定WAV Snapshotで共有し、オフ時・周回停止時にauAudioUnit.resetで残響を消去する。SampleInstrument.gainはパンと同じ出力Mixerへ適用し、EQ/リバーブ後の音量・Muteで既存余韻も消音する。単体Studioは従来同様mainMixerを使う。
リバーブ単独の自然終了はADSR完了後に有効パートの残響を最大3秒待つ。WAVは各パートのRelease＋非Muteの効果予算（リバーブとディレイの加算）の最大値を曲末に加える（OFFでは従来の長さ）。全停止/一時停止/シークは余韻ごと停止、範囲周回も残響をリセットする。SongState/dirty/Undo/Redo・AI編曲の値保持に含め、構成v8必須、v1〜v7はオフへ移行。

## Part Delay
PartDelayはtimeMS（50〜1000）、mix（0〜100）、feedback（0〜60）の有限数を保持。既定300/0/35で、mix=0はbypass。EnsembleVoiceのEQ→AVAudioUnitDelay（lowPassCutoff=20 kHz）→リバーブ→出力Mixerをライブ/WAVで共有し、setDelayは30 Hzで差分反映。オフとvoice.stopでAUをresetする。
余韻は最初のエコーを含めfeedbackが振幅−60 dB未満になるまでの回数×間隔（feedback=0は1回）。最大15秒で、リバーブの3秒と足し合わせる。WAVは各パートのRelease＋非Muteの効果予算の最大値、ライブはADSR完了後に最大予算を待つ。全停止/一時停止/シーク/範囲周回は遅延音も消す。SongState/dirty/Undo/Redo・AI編曲の既存値保持に含め、構成v9は3値必須、v1〜v8は既定のオフへ移行。

## Part Compressor
PartCompressorはApple AUDynamicsProcessorをAVAudioUnitEffectで使用。EQ後/ディレイ前で48 kHz stereo処理する。thresholdDB −40〜0、headroomDB 0.1〜40、attackMS 0.1〜200、releaseMS 10〜3000、makeupDB 0〜24の有限数とenabledを持つ。既定はオフ/−24/5/10/150/0。固定ratioは使わずheadroomが小さいほど強い圧縮。ExpansionRatio=1でゲート/エキスパンダーを無効化する。オフは補正音量もbypassし、他の値を保持。EnsembleVoice.setCompressorでライブ30 Hz/固定WAVを共有し、オン/オフ切替とvoice.stopでAUをreset。音声生成/残響を行わず余韻予算は追加しない。全停止/一時停止/シーク/周回も同じ停止経路。SongState/dirty/Undo/Redo・AI編曲時の手動値保持に含む。構成v10は6項目必須、v1〜v9は既定オフへ移行。判断は[0043](decisions/0043-part-compressor.md)。

## Source Separation

SeparationView → SeparationModel → SeparationClient（Process）→ Resources/separation_worker.py。固定MLXモデルと外側正規化、原曲+4ステムをFloat32 WAVへ出力。jobID付きatomic progress/manifestを使い、候補全体の検証後にのみ更新。採用時はPlayerModelがWAVの所有コピーを保持し、既存の波形・InstrumentSample・InstrumentDocumentへつなぐ。取消と終了はworker停止後に一時ファイルを削除。Python/モデルは別途準備。詳細・制限は[分離ガイド](SEPARATION.md)、判断は[0046](decisions/0046-separation-worker-integration.md)。

## 来歴付き素材保存
SeparationManifestは入力SHA-256・依存版・gain・前処理識別子を検証する。SeparationLeaseがジョブの一時ディレクトリを参照所有し、PlayerModelに採用された来歴がある間は次の分離や候補cleanup後も元曲を保持する。
MaterialLibraryView/Model → MaterialStore actor → SQLite3（保存基盤v1、注釈検索追加でv2へ移行）+ 内容SHA-256の管理ファイル。元入力・比較用元曲・選択stem全長・切片をstagingで検証し、容量確認後、ファイル公開→DB transactionの順に保存する。同じrun/stem/範囲は既存素材を返す。新しい分離runは別の来歴として保持する。
素材を開く際はhash・形式・フレーム数を確認後、全長stemまたは比較用元曲の波形と絶対フレーム範囲を復元する。失敗時は現在の音源を保持。短いclipの再編集はMaterialOrigin.frameOffsetを加算して元曲上の絶対位置へ戻し、親素材IDと注釈を継承する。孤立objectsは自動削除せず、破損/未知版DBも保持してエラーにする。詳細は[MATERIAL_LIBRARY](MATERIAL_LIBRARY.md)。

## Master Limiter
MasterLimiterのenabled/ceilingDB/releaseMSをEnsembleSnapshotとSongStateで保持。EnsembleMasterBusが全パート合算Mixer（固定1/4ヘッドルーム＋masterDB）→Apple AUPeakLimiter→mainMixerを共有し、mainMixerのtapで処理後のRMSを測る。入力側でceilingDBを逆補正し、mainMixer.outputVolumeで上限へ戻す。オン/オフ切替・周回・全停止で検出状態をreset。上限を下げるときは最終gainを先に下げ、PreGain変更時の一時的な増幅を避ける。ライブ30 HzとWAVの固定Snapshotが同じapplyを使う。オフはAUバイパス/最終gain=1で旧ミックスを保つ。既定オフ、値の範囲は[構成形式](ENSEMBLE_FORMAT.md)、操作/限界は[リミッター](MASTER_LIMITER.md)。構成v11は3項目必須、旧v1〜v10はオフ移行。AI編曲のmaterializeは既存値を保持し提案schemaは変更しない。理由は[0048](decisions/0048-master-limiter.md)。

## 素材の注釈・検索・比較試聴
MaterialStore schema v2は不変の来歴とは別にmaterial_annotations/tags/material_tagsを管理する。v1からはSQLite backup APIでbackupsへ退避後、transactionで移行。注釈保存と正規化済み検索キー/タグ関連の更新を一括commitする。検索はbind済みLIKE（記号escape）とタグID、ORDER BY created/id、LIMIT/OFFSETで50件まで返す。MaterialLibraryModelは検索generationで古い結果を無効化し、選択中の未保存注釈を検索から独立して保持する。
MaterialStore.comparison → MaterialComparisonが検証済み保存音声の区間を短いWAVへ生成し所有する。MaterialLibraryModelは素材/元曲/stemを同じ相対位置からAVAudioPlayerで切り替え、終了/停止で所有ファイルを解放する。PlayerModel.previewMaterialは他の再生を停止し、PlayerModel.stopInstrument/playNoteは素材試聴を停止する。UI閉鎖/非アクティブ/検索・選択変更では遅延発音も無効化。詳細は[MATERIAL_LIBRARY](MATERIAL_LIBRARY.md)、判断は[0050](decisions/0050-material-search-comparison.md)。

## 素材再編集と楽器の来歴
InstrumentProvenanceは元素材の不変MaterialRecordと楽器PCMに対応する絶対frameを保持する。PlayerModelは波形と取り込み済み楽器の来歴を分離し、選択変更で既存楽器の来歴を書き換えない。来歴付きは楽器v5、構成v12、来歴なしは従来v4/v11で保存。EnsembleInstrument/SongState/AI編曲/設定編集も保持する。DB不在でも短い内包PCMの演奏・再編集と来歴表示が可能で、元曲の管理音声は捏造しない。[判断](decisions/0051-material-reuse-provenance.md)。

## 素材のゴミ箱
MaterialStore schema v3のmaterial_trashは素材IDと移動日時だけを保存する。既存v2は退避してtransactionで移行。search/list/tagsは有効素材とゴミ箱を分離し、item/restore/resolve/comparisonはIDによる参照を維持する。setTrashedは音声ファイルや来歴payload/親子/注釈を変更しないため、編集中音声・派生素材・可搬楽器の来歴を壊さない。MaterialLibraryModel.showTrash/changeTrashStateとMaterialLibraryViewが未保存確認・試聴停止・状態別一覧/復元を扱う。同一区間のゴミ箱素材は再登録で自動復元しない。[判断](decisions/0052-material-trash.md)。

## 完全削除と音声回収
MaterialDeletionはschema v4のtombstones/retentions/reclaimsと削除計画を扱う。素材の不変recordを参照記録へ移し、他素材/祖先/楽器の永続保護/MaterialAudioLeaseを除いた音声だけを回収する。Storeの準備/確定を同じactorで行い、DBと候補内容の確認時snapshotを確定前に再検証する。commit後の回収journalをunlink成功ごとに解消し、失敗分は未回収メニューで再確認できる。PlayerModelの波形/元曲とMaterialComparisonがleaseを保持。楽器化/保存/読込と既知ファイル確認でretentionを保存し、構成/履歴も保護する。UIはMaterialDeletionReviewと削除済み参照記録、ModelはreviewDeletion/confirmDeletion。詳細は[完全削除](MATERIAL_DELETION.md)、判断は[0053](decisions/0053-material-permanent-deletion.md)。

MaterialDeletionのprotectionReview/prepareRelease/releaseProtectionが保護一覧・仮解除rollbackによる容量計算・snapshot再検証付き個別解除を担当する。schema v4を維持し、音声回収は既存の明示操作に分ける。

完全削除計画はrecordsのID集合で単体/複数を共通処理する。prepareBatchDeletionは最大50件のゴミ箱素材を検証し、対象/削除済み祖先のhash集合から選択外の参照を除く。全件のDB変更と重複のない回収journalを同じtransactionで確定する。部分回収失敗は辞書順先頭IDに集約し既存の単体再確認経路で復旧する。

基準音の共通範囲はNotePitch.rootRange（24〜96）。画面/PC鍵盤はkeyboardRange/computerBaseで音域を決め、InstrumentDocument/EnsembleDocument/EnsembleModel/PerformanceBriefが同じ範囲を検証する。MIDIInputは未編集内蔵プリセットのみ新音域に追従。保存構造/版は維持。[判断0056](decisions/0056-expanded-root-range.md)。

## 基準音の候補推定
PitchEstimateControl/Panel → PitchAnalysis（MainActorの状態・音源ID/世代・Task取消）→ PitchEstimator（バックグラウンドのFIR/周期解析）。取り込み済みInstrumentSampleは解析中も参照保持し、PCMを変更しない。StudioはrootNote、InspectorはsetInstrumentSettingsへ明示採用だけ渡す。保存構造は維持。[仕様](PITCH_ESTIMATION.md)。

評価録音: PitchCorpusの同梱manifest/WAVをPitchDemoMenu → PlayerModel.loadPitchDemo → 既存load/prepareInstrumentへ接続。推定器は変えず、CLI評価も同じ検証済みWAVを使う。原本/変換後SHA-256・固定切片・名目正解音を保持。[評価](PITCH_EVALUATION.md)。
