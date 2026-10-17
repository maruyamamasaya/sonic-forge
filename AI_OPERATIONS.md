# AI向け操作・演奏ガイド

最終確認: 2026-10-17

## この文書の役割
AIがアプリを操作・拡張するときに、操作の入口、観測する状態、停止方法を短時間で把握するためのガイド。
現在地は[CURRENT.md](CURRENT.md)、構造は[ARCHITECTURE.md](ARCHITECTURE.md)、人向けの詳しい操作は[OPERATIONS.md](OPERATIONS.md)、コードの配置は[CODEMAP.md](CODEMAP.md)を正本とする。
実装と異なる場合はコード・テストを確認し、本書を更新する。

## 現在できることと境界
- WAVを読み込み、範囲を切り出してサンプラー楽器へ取り込み、基準音・ADSR・ループ・クロスフェードを設定できる。
- 最大8音を画面・PC・MIDIから演奏でき、MIDIの強弱とサステインペダルに対応する。
- 内蔵3種類を元にテンポ・移調・強弱・個別音符・ペダルを編集・保存し、Auto playで自動演奏できる。実機や演奏スキルは不要。
- 演奏データの外部ファイル読込・保存、Compose…によるAIフレーズ生成は対応済み。録音・曲の書き出しは未実装。
- 外部AI向けの操作API・CLI・MCPは未実装。下記Swiftメソッドはアプリ内・テスト内の入口であり、外部から直接呼べるAPIではない。現時点の外部操作は実画面を通して行う。

## 最初に試す手順
1. アプリを起動。既存の楽器を変更せず試す場合はそのまま使用する。Load Demoは現在の未保存音色を置き換えるので、残す必要があれば先にSave…する。
2. 音源の表示があり、読み込み中でないことを確認。デモの場合は楽器にも自動取り込みされる。
3. 演奏プリセットでSoft chords / Arpeggio / Pedal phraseを選ぶ。Edit…で編集・Open…/Save…で演奏を読み書きし、Doneで戻ってAuto playを押す。仮想MIDI入力は自動で作成・選択される。
4. 鍵盤の点灯・発音数・出力メーターを確認。Pedal phraseではPEDAL CH 1が一時表示される。
5. 自然終了後、保持音とペダルが解除され、Release後に発音数とメーターが無音へ戻ることを確認。
6. 途中停止はStop auto、余韻も含め全入力を止める場合はAll Notes Offを使う。

UIの要素番号や画面座標は固定ではない。機器やウィンドウ幅によって変わるため、操作前後に現在の画面状態を確認する。
画面が隠れたりフォーカスが外れたりすると演奏は停止する。Pausedの場合は本体ウィンドウを再選択する。

## 操作とアプリ内の入口
| 目的 | 画面 | 主な実装入口 |
| --- | --- | --- |
| 素材を用意 | Load Demo / Open WAV… | PlayerModel.loadDemo / load |
| 音色を作る | Use Selection、Root、ADSR、LOOP、CROSSFADE | prepareInstrument、rootNote、setEnvelope、setLoop |
| 楽器を探す・試聴・読込 | Library…、Search instruments、Preview / Stop Preview、Load Instrument | InstrumentLibrary.filtered / preview / stopPreview、PlayerModel.loadInstrument |
| 音色を保存・復元 | Save… / Open… | saveInstrumentPanel / openInstrumentPanel、InstrumentDocument |
| MIDIを選ぶ | MIDI IN / None | MIDIInput.select / refresh |
| 実機なしの手動確認 | Test input、VELOCITY、Test pedal、MIDI chord | createTestInput、testVelocity、sendTest、toggleTestChord |
| 自動演奏 | プリセット、Auto play / Stop auto | performancePreset、playPerformance / stopPerformance |
| 構成保存・復元 | Ensemble上部Open… / Save…、Saved / ● Unsaved | EnsembleModel.save/load/restoreLastSession、dirty/fileURL/fileMessage |
| 複数パート | Ensemble…、Add Part / Add Current / Add Demo Duo、Play All / Stop All | EnsembleModel.parts/timeline/play/stop、EnsembleVoice.receive |
| AI演奏候補 | Compose…、Generate、Cancel Generation、Use & Play | PerformanceComposer.generate/cancel、candidate/candidateRoot/source、MIDIInput.applyGeneratedPerformance |
| 演奏編集・保存 | Edit…、TEMPO、TRANSPOSE、VELOCITY、Notes、Pedal、Open… / Save… | PerformanceEditor、MIDIInput.performance、loadPerformance / savePerformance |
| 全音停止 | All Notes Off | PlayerModel.stopInstrument |

MainActorでUI・モデルを操作する。外部MIDIの受信処理や音声スレッドから直接状態を書き換えない。
責務・スレッド・接続世代の詳細は[構造](ARCHITECTURE.md)を参照。

## 成功判定で見る状態
| 状態 | 意味・判定 |
| --- | --- |
| asset / instrumentSample | 波形用素材 / 演奏用PCM。外部WAVを開くだけでは楽器への取り込みは完了しない |
| busy / error | 作業中 / ファイル・演奏エラー。処理が終わってから次の操作へ進む |
| midi.selected / midi.error | 0はNone、非0は選択した入力。接続エラーはモデルのerrorと別に表示される |
| midi.performing | イベント送信中。falseでもReleaseの余韻が残る場合がある |
| activeNotes / soundingVoices | 保持中の音程集合 / Releaseも含む発音数。ペダル保持音もactiveNotesに含む |
| sustainChannels | ペダルONのチャンネル集合。内部0〜15、画面のCHは1〜16 |
| levels | 合算後の出力レベル。無音表示の下限は−60 dB。実際の聞こえ方や音質の保証ではない |
| performanceDirty / performanceFileURL | 演奏の未保存変更 / 保存先。音色の保存状態とは独立 |
| instrumentDirty | 音色の未保存変更。演奏・プリセット選択・ペダル操作は音色の保存設定ではない |

「送信終了」「保持解除」「余韻終了」を区別する。プリセットの終了はperforming=false、activeNotesが空、sustainChannelsが空、soundingVoices=0とメーターを合わせて確認する。一般の手動演奏では、ペダルONのままでも保持音がなければ無音になり得る。
最大8音と基準音±24半音の制限がある。範囲外の音やボイスの置き換えを接続失敗と取り違えない。

## 演奏データとAI生成の入口
外部データは.sfperformanceのJSON。仕様・制限・例は[演奏形式v1](PERFORMANCE_FORMAT.md)を正本とする。
AIがファイルを作成し、Edit… → Open…で読み込める。Compose…でアプリ内生成も可能。外部操作APIは未実装。
コードを実行せず、音符・ペダルの構造化データをPerformanceDocument.load/eventsで検証してから再生する。
現在の楽器での再生可能範囲は開始前に検証される。拒否された場合はエラーを読み、移調・音符・基準音を見直す。

## 拡張時の入口と確認
- PerformanceDocument.swift: 保存データ、内蔵プリセット、MIDIイベントへの変換・検証。
- PerformanceEditor.swift: 名前・全体調整・音符・ペダルの編集。Doneは変更を保持して閉じる。保存とは別操作。
- MIDIInput.swift: 演奏の読込・保存、開始時のスナップショット、仮想sourceへの配送と停止。
- PerformanceTests.swift: 変換・保存往復・不正データ・同時発音・仮想MIDI演奏の検証。

形式を変える場合はversionと互換性を明示し、既存ファイルの扱いを決める。プリセットの追加ではMIDIPerformancePresetのcase/eventsを追加し、PerformanceDocument.presetへの変換と検証を確認する。
保存・読込の成功だけでなく、編集した音程・テンポでの演奏、ペダル解除、自然終了・途中停止も確認する。
[TESTING.md](TESTING.md)のFast、--playback、Fullと実画面確認を行い、実機未検証は明記する。

## 文書を更新するタイミング
UIの操作名、モデルの入口、演奏データ形式、成功判定、停止動作、対応範囲が変わったら本書の該当箇所を更新する。
構造はARCHITECTURE、詳細操作はOPERATIONS、検証はTESTINGに置き、同じ仕様を各文書へ複写しない。

## 楽器ライブラリの操作
1. Library…→必要ならAdd Files…、音源がなければAdd Demos。追加のbusyがfalseになるまで待つ。
2. Search instrumentsでファイル名検索→対象行を選択。同名は親フォルダを確認。Missingは読み込み不可なので移動後の場所から再追加する。
3. Preview→PREVIEW表示とpreviewingを確認。独立音声エンジンなので本体の鍵盤・出力メーターは試聴の状態を表さない。previewLevelsは専用エンジンの実測値。開始3秒で停止しpreviewing=nilに戻る。Stop Preview・選択変更・Done・非アクティブで即停止する。
4. Load Instrument→未保存時は確認文を読み、保持するならCancelして先に保存する。置換承認時のみReplace Instrument。成功するとシートが閉じ、instrumentFileURL・Root・ADSR・ループが対象へ変わりinstrumentDirty=false。失敗は元の楽器を保持しエラー表示。
5. 必要ならAuto play→All Notes Offで本体の演奏を確認する。

一覧登録は原本への参照。Remove from Listは登録解除のみ。試聴は楽器の保存・起動時復元先を変更しない。Add Demosはアプリ用保存領域に生成楽器を作る。外部からアプリを操作するAPIは未実装のため、AIは現在のUIを観測して操作する。追加・復号中に閉じても遅延発音しないことを検証する。

## 言葉からの演奏生成
接続・方式ごとの操作は[AI_GENERATION.md](AI_GENERATION.md)を正本とする。Compose…で方式を確認し、生成指示と基準音を観測してGenerate。生成中はgenerating=true、完了はcandidate!=nilかつerror=nil。候補の方式・名前・音符数・BPMとピアノロールを確認してUse & Play。未保存演奏があればReplace & Playは明示的な置換操作となる。保持するならCancelして先にEdit…→Save…する。
採用はcandidateRootと現在のrootNoteが一致し、再検証を通る場合のみ。シートが閉じてから自動演奏が始まるため、候補完成と発音を区別する。既存のperforming・activeNotes・soundingVoices・levelsで演奏を確認。停止はStop auto / All Notes Off。生成の取消はCancel GenerationまたはDone。取消後に遅れて返った結果は採用されず、既存演奏も変更しない。
APIキーやCLI認証情報をチャット・文書・ログへ転記しない。生成結果からコードを実行しない。Codex CLIは別プロセスとして利用し、SonicForgeの作業ディレクトリを渡さない。Other AIのCopy Briefは操作したときだけクリップボードへ指示とschemaを入れる。DemoはAI応答ではない。

## 複数の楽器と演奏を割り当てる
正本は[ENSEMBLE.md](ENSEMBLE.md)。Ensemble…→Add Partで行を追加→INSTRUMENTのライブラリ選択またはOpen…→PERFORMANCEのPreset/Open…/Use Current。Add Currentは現在の本体楽器と演奏をスナップショットで追加する。AI生成データは本体へ採用してAdd Current、または保存した.sfperformanceをパートへOpen…する。パートごとに異なるRootで生成/検証すること。音域を勝手に補正しない。
全行のReadyと共通TEMPOを確認してPlay All。各行のvoices/出力、共通Beat/出力で同時演奏を判定する。本体の鍵盤やメーターはパート演奏の状態を表さない。playing=trueはRelease中も含み、releasingで区別。Stop All / Done / 非アクティブで全パートを停止。Stop後はplaying=false、各voices=0、level=-60、保持音とペダルが空であることを確認する。
再生中は割り当てを変えず、Muteと音量だけを操作する。全パートは共通tempoに従い、ファイル内tempoは変更しない。構成はSave…した状態だけがディスクへ保存される。Doneで閉じただけ、または● Unsavedの状態を保存済みだと報告しない。外部操作APIは未実装。

## 構成の保存と起動時復元の判定
[ENSEMBLE.md](ENSEMBLE.md)と[構成形式v2](ENSEMBLE_FORMAT.md)を参照。Save…→busy=false・error=nil・dirty=false・fileURL/ファイル名を確認。全パートと音源を同梱するため、元の楽器/演奏パスを構成へ別途転記しない。新しいファイルを選んだだけ、保存ダイアログを開いただけでは保存成功と判定しない。
Open…の未保存置換確認では必要に応じてCancel→先にSave…。失敗時の前のパート/保存先保持も確認する。起動時はrestoreLastSessionで最後の正常なファイルを一度だけ復元し、Restored・Saved・設定・playing=falseを確認してからPlay All。音量/Mute/共通tempo/Ensemble Master、楽器と演奏の一致を確認する。ファイル欠落時はエラーを読みOpen…へ進み、復元成功と報告しない。
保存対象は現在の設定スナップショットで、未保存変更や発音状態の自動復旧ではない。再生中はSave/Openを行わず、Stop All後に保存する。起動時復元で本体の単一楽器やAI生成設定を置き換えない。

## パートの開始位置を調整する
Ensemble各行のSTART（アクセシビリティ名Start beat for パート名）へ0〜256の有限拍数を入力する。0は曲頭、4は4拍後。小数拍可。停止中のみ操作し、共通テンポと各STARTを読んで意図した秒数を確認する。元のperformance.notes/pedalsのbeatを同時に動かして二重に遅らせない。
デモは空きを2つ確保してDemo Entry +4。Pad=0・Pluck=4を確認してPlay All。待機中のPluckは0 voices・−60 dB、Beat 4以降に発音する。Stop Allで待機も解除し、playing=false・全voices=0を確認。最初の音符に休符がある場合はSTARTの後も無音が続く。
編集はdirty=trueになる。Save…でdirty=falseを確認し、Open/再起動でstartBeat一致を検証。モデル入口はEnsemblePart.startBeat、EnsembleModel.timeline/addDemos(staggered:)、保存はEnsemblePartSnapshot.startBeat。保存形式v2ではparts[].startBeatが必須、v1は0に移行する。AIが構成JSONを作る場合も同じ制限・音源同梱形式を守る。

## 複数パートをWAVへ書き出す
正本は[ENSEMBLE.md](ENSEMBLE.md)。Stop All後、START・TEMPO・全音量/MuteとMasterを確認してExport WAV…。モデル入口はEnsembleModel.exportPanel/exportWAV、レンダーはEnsembleExport.write。保存先を選んだだけでは成功と判定しない。exporting=true/busy=true中は編集・再生を行わず、取消はCancel Export（cancelExport）。完了はexporting=false/busy=false・error=nil・exportedURLとExported表示で判定する。取消はExport cancelled、失敗はエラー表示で、成功と報告しない。
WAVは48 kHz/stereo/Float32、最大256 MiB、最後のイベント＋最大Release＋50 ms。開始位置・全Muteによる無音は正常。構成のdirtyは変えず、自動保存もしない。本体の試聴音量やOS音量はファイルへ反映しない。
デモで完了後Done→本体Open WAV…から出力を再読み込み、assetのレート/チャンネル/長さと波形を確認して再生・停止。元音源へ上書きしない。書き出しはオフラインなのでOSの出力デバイスを必要としない。

## タイムラインの表示と開始位置操作
ARRANGEMENTで全パートを一覧し、クリップの位置と幅、START値で構成を判断する。アクセシビリティ名はTimeline clip for パート名、値はStart/length/end beats。クリップのIncrement/Decrementは¼拍。ドラッグは停止中のみ、離した時に¼拍へスナップして0〜256へ制限する。精密な任意値はStart beat for パート名へ入力する。モデル入口はEnsembleModel.movePart、計算はEnsembleTimeline.length/movedStart、UIはEnsembleTimelineView。
クリップ長は最後の音符離鍵またはペダルイベントまでで、冒頭の休符を含み、Release余韻は含まない。Muteは幅を変えず薄く表示。無効な演奏はInvalid performanceと表示し、正常クリップと報告しない。横スクロールして後半も確認する。
操作後はSTART/クリップ値とdirty=trueを確認。Save…後の復元は既存startBeatと同一で、保存形式変更なし。Play Allでは位置線とBeatを確認し、移動操作をしない。Stop Allでplaying=false・全voices=0・位置0を確認する。クリップ端のドラッグによる長さ変更、シーク、複製は未実装。
