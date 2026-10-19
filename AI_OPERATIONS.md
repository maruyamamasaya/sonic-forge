# AI向け操作・演奏ガイド

最終確認: 2026-10-17

## この文書の役割
AIがアプリを操作・拡張するときに、操作の入口、観測する状態、停止方法を短時間で把握するためのガイド。
現在地は[CURRENT.md](CURRENT.md)、構造は[ARCHITECTURE.md](ARCHITECTURE.md)、人向けの詳しい操作は[OPERATIONS.md](OPERATIONS.md)、コードの配置は[CODEMAP.md](CODEMAP.md)を正本とする。
実装と異なる場合はコード・テストを確認し、本書を更新する。主要操作の現在の日本語名と識別子は末尾の[日本語UIとヘルプ](#日本語uiとヘルプ)も参照。

## 現在できることと境界
- WAVを読み込み、範囲を切り出してサンプラー楽器へ取り込み、基準音・ADSR・ループ・クロスフェードを設定できる。
- 最大8音を画面・PC・MIDIから演奏でき、MIDIの強弱とサステインペダルに対応する。
- 内蔵3種類を元にテンポ・移調・強弱・個別音符・ペダルを編集・保存し、自動演奏で自動演奏できる。実機や演奏スキルは不要。
- 演奏データの外部ファイル読込・保存、AI演奏…によるAIフレーズ生成は対応済み。録音は未実装。構成全体のWAV書き出しは対応済み。
- 外部AI向けの操作API・CLI・MCPは未実装。下記Swiftメソッドはアプリ内・テスト内の入口であり、外部から直接呼べるAPIではない。現時点の外部操作は実画面を通して行う。

## 最初に試す手順
1. アプリを起動→左下素材・楽器編集を開く（波形・楽器を編集…）。既存の楽器を変更せず試す場合はそのまま使用する。デモを開くは現在の未保存音色を置き換えるので、残す必要があれば先に保存…する。
2. 音源の表示があり、読み込み中でないことを確認。デモの場合は楽器にも自動取り込みされる。
3. 演奏プリセットで柔らかい和音 / 分散和音 / ペダルの演奏を選ぶ。演奏編集…で編集・開く…/保存…で演奏を読み書きし、閉じるで戻って自動演奏を押す。仮想MIDI入力は自動で作成・選択される。
4. 鍵盤の点灯・発音数・出力メーターを確認。ペダルの演奏ではPEDAL CH 1が一時表示される。
5. 自然終了後、保持音とペダルが解除され、Release後に発音数とメーターが無音へ戻ることを確認。
6. 途中停止は自動演奏停止、余韻も含め全入力を止める場合は全音停止を使う。

UIの要素番号や画面座標は固定ではない。機器やウィンドウ幅によって変わるため、操作前後に現在の画面状態を確認する。
画面が隠れたりフォーカスが外れたりすると演奏は停止する。Pausedの場合は本体ウィンドウを再選択する。

## 操作とアプリ内の入口
| 目的 | 画面 | 主な実装入口 |
| --- | --- | --- |
| 素材を用意 | デモを開く / WAVを開く… | PlayerModel.loadDemo / load |
| 音色を作る | 選択を楽器に、基準音、ADSR、ループ、継ぎ目 | prepareInstrument、rootNote、setEnvelope、setLoop |
| 楽器を探す・試聴・読込 | Library…、楽器を検索、試聴 / 試聴停止、楽器を読み込む | InstrumentLibrary.filtered / preview / stopPreview、PlayerModel.loadInstrument |
| 音色を保存・復元 | 保存… / 開く… | saveInstrumentPanel / openInstrumentPanel、InstrumentDocument |
| MIDIを選ぶ | MIDI入力 / None | MIDIInput.select / refresh |
| 実機なしの手動確認 | テスト入力、強弱、ペダルを試す、MIDI和音 | createTestInput、testVelocity、sendTest、toggleTestChord |
| 自動演奏 | プリセット、自動演奏 / 自動演奏停止 | performancePreset、playPerformance / stopPerformance |
| 構成保存・復元 | Ensemble上部開く… / 保存…、保存済み / ● 未保存 | EnsembleModel.save/load/restoreLastSession、dirty/fileURL/fileMessage |
| 複数パート | メインEnsemble / 全パート…、パート追加 / 編集中の楽器を追加 / デモ2パート、全体を再生 / 全停止 | EnsembleModel.parts/timeline/play/stop、EnsembleVoice.receive |
| AI演奏候補 | AI演奏…、候補を生成、生成を中止、採用して再生 | PerformanceComposer.generate/cancel、candidate/candidateRoot/source、MIDIInput.applyGeneratedPerformance |
| 演奏編集・保存 | 演奏編集…、テンポ、移調、強弱、Notes、Pedal、開く… / 保存… | PerformanceEditor、MIDIInput.performance、loadPerformance / savePerformance |
| 全音停止 | 全音停止 | PlayerModel.stopInstrument |

MainActorでUI・モデルを操作する。外部MIDIの受信処理や音声スレッドから直接状態を書き換えない。
責務・スレッド・接続世代の詳細は[構造](ARCHITECTURE.md)を参照。

## 成功判定で見る状態
| 状態 | 意味・判定 |
| --- | --- |
| asset / instrumentSample | 波形用素材 / 演奏用PCM。外部WAVを開くだけでは楽器への取り込みは完了しない |
| busy / error | 作業中 / ファイル・演奏エラー。処理が終わってから次の操作へ進む |
| midi.selected / midi.error | 0は未選択（画面表示は「なし」）、非0は選択した入力。接続エラーはモデルのerrorと別に表示される |
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
AIがファイルを作成し、演奏編集… → 開く…で読み込める。AI演奏…でアプリ内生成も可能。外部操作APIは未実装。
コードを実行せず、音符・ペダルの構造化データをPerformanceDocument.load/eventsで検証してから再生する。
現在の楽器での再生可能範囲は開始前に検証される。拒否された場合はエラーを読み、移調・音符・基準音を見直す。

## 拡張時の入口と確認
- PerformanceDocument.swift: 保存データ、内蔵プリセット、MIDIイベントへの変換・検証。
- PerformanceEditor.swift: 名前・全体調整・音符・ペダルの編集。閉じるは変更を保持して閉じる。保存とは別操作。
- MIDIInput.swift: 演奏の読込・保存、開始時のスナップショット、仮想sourceへの配送と停止。
- PerformanceTests.swift: 変換・保存往復・不正データ・同時発音・仮想MIDI演奏の検証。

形式を変える場合はversionと互換性を明示し、既存ファイルの扱いを決める。プリセットの追加ではMIDIPerformancePresetのcase/eventsを追加し、PerformanceDocument.presetへの変換と検証を確認する。
保存・読込の成功だけでなく、編集した音程・テンポでの演奏、ペダル解除、自然終了・途中停止も確認する。
[TESTING.md](TESTING.md)のFast、--playback、Fullと実画面確認を行い、実機未検証は明記する。

## 文書を更新するタイミング
UIの操作名、モデルの入口、演奏データ形式、成功判定、停止動作、対応範囲が変わったら本書の該当箇所を更新する。
構造はARCHITECTURE、詳細操作はOPERATIONS、検証はTESTINGに置き、同じ仕様を各文書へ複写しない。

## 楽器ライブラリの操作
1. Library…→必要ならファイル追加…、音源がなければデモ楽器追加。追加のbusyがfalseになるまで待つ。
2. 楽器を検索でファイル名検索→対象行を選択。同名は親フォルダを確認。Missingは読み込み不可なので移動後の場所から再追加する。
3. 試聴→PREVIEW表示とpreviewingを確認。独立音声エンジンなので本体の鍵盤・出力メーターは試聴の状態を表さない。previewLevelsは専用エンジンの実測値。開始3秒で停止しpreviewing=nilに戻る。試聴停止・選択変更・閉じる・非アクティブで即停止する。
4. 楽器を読み込む→未保存時は確認文を読み、保持するならキャンセルして先に保存する。置換承認時のみReplace Instrument。成功するとシートが閉じ、instrumentFileURL・基準音・ADSR・ループが対象へ変わりinstrumentDirty=false。失敗は元の楽器を保持しエラー表示。
5. 必要なら自動演奏→全音停止で本体の演奏を確認する。

一覧登録は原本への参照。Remove from Listは登録解除のみ。試聴は楽器の保存・起動時復元先を変更しない。デモ楽器追加はアプリ用保存領域に生成楽器を作る。外部からアプリを操作するAPIは未実装のため、AIは現在のUIを観測して操作する。追加・復号中に閉じても遅延発音しないことを検証する。

## 言葉からの演奏生成
接続・方式ごとの操作は[AI_GENERATION.md](AI_GENERATION.md)を正本とする。AI演奏…で方式を確認し、生成指示と基準音を観測して候補を生成。生成中はgenerating=true、完了はcandidate!=nilかつerror=nil。候補の方式・名前・音符数・BPMとピアノロールを確認して採用して再生。未保存演奏があれば置き換えて再生は明示的な置換操作となる。保持するならキャンセルして先に演奏編集…→保存…する。
採用はcandidateRootと現在のrootNoteが一致し、再検証を通る場合のみ。シートが閉じてから自動演奏が始まるため、候補完成と発音を区別する。既存のperforming・activeNotes・soundingVoices・levelsで演奏を確認。停止は自動演奏停止 / 全音停止。生成の取消は生成を中止または閉じる。取消後に遅れて返った結果は採用されず、既存演奏も変更しない。
APIキーやCLI認証情報をチャット・文書・ログへ転記しない。生成結果からコードを実行しない。Codex CLIは別プロセスとして利用し、SonicForgeの作業ディレクトリを渡さない。Other AIの指示をコピーは操作したときだけクリップボードへ指示とschemaを入れる。DemoはAI応答ではない。

## 複数の楽器と演奏を割り当てる
正本は[ENSEMBLE.md](ENSEMBLE.md)。メインEnsemble→パート追加で行を追加→INSTRUMENTのライブラリ選択または開く…→PERFORMANCEのPreset/開く…/編集中の演奏を使う。編集中の楽器を追加は現在の本体楽器と演奏をスナップショットで追加する。AI生成データは本体へ採用して編集中の楽器を追加、または保存した.sfperformanceをパートへ開く…する。パートごとに異なる基準音で生成/検証すること。音域を勝手に補正しない。
全行のReadyと共通テンポを確認して全体を再生。各行のvoices/出力、共通Beat/出力で同時演奏を判定する。本体の鍵盤やメーターはパート演奏の状態を表さない。playing=trueはRelease中も含み、releasingで区別。全停止 / 閉じる / 非アクティブで全パートを停止。Stop後はplaying=false、各voices=0、level=-60、保持音とペダルが空であることを確認する。
再生中は割り当てを変えず、Mute・音量・パン・EQ・リバーブ・ディレイを操作できる。全パートは共通tempoに従い、ファイル内tempoは変更しない。構成は保存…した状態だけがディスクへ保存される。閉じるで閉じただけ、または● 未保存の状態を保存済みだと報告しない。外部操作APIは未実装。

## 構成の保存と起動時復元の判定
[ENSEMBLE.md](ENSEMBLE.md)と[構成形式v9](ENSEMBLE_FORMAT.md)を参照。保存…→busy=false・error=nil・dirty=false・fileURL/ファイル名を確認。全パートと音源を同梱するため、元の楽器/演奏パスを構成へ別途転記しない。新しいファイルを選んだだけ、保存ダイアログを開いただけでは保存成功と判定しない。
開く…の未保存置換確認では必要に応じてキャンセル→先に保存…。失敗時の前のパート/保存先保持も確認する。起動時はrestoreLastSessionで最後の正常なファイルを一度だけ復元し、Restored・保存済み・設定・playing=falseを確認してから全体を再生。音量/Mute/共通tempo/Ensemble Master、楽器と演奏の一致を確認する。ファイル欠落時はエラーを読み開く…へ進み、復元成功と報告しない。
保存対象は現在の設定スナップショットで、未保存変更や発音状態の自動復旧ではない。再生中はSave/Openを行わず、全停止後に保存する。起動時復元で本体の単一楽器やAI生成設定を置き換えない。

## パートの開始位置を調整する
Ensemble各行のSTART（アクセシビリティ名Start beat for パート名）へ0〜256の有限拍数を入力する。0は曲頭、4は4拍後。小数拍可。停止中のみ操作し、共通テンポと各STARTを読んで意図した秒数を確認する。元のperformance.notes/pedalsのbeatを同時に動かして二重に遅らせない。
デモは空きを2つ確保してDemo Entry +4。Pad=0・Pluck=4を確認して全体を再生。待機中のPluckは0 voices・−60 dB、Beat 4以降に発音する。全停止で待機も解除し、playing=false・全voices=0を確認。最初の音符に休符がある場合はSTARTの後も無音が続く。
編集はdirty=trueになる。保存…でdirty=falseを確認し、Open/再起動でstartBeat一致を検証。モデル入口はEnsemblePart.startBeat、EnsembleModel.timeline/addDemos(staggered:)、保存はEnsemblePartSnapshot.startBeat。保存形式v4ではparts[].startBeatが必須、v1は0に移行する。AIが構成JSONを作る場合も同じ制限・音源同梱形式を守る。

## 複数パートをWAVへ書き出す
正本は[ENSEMBLE.md](ENSEMBLE.md)。全停止後、START・テンポ・全音量/MuteとMasterを確認してWAV書き出し…。モデル入口はEnsembleModel.exportPanel/exportWAV、レンダーはEnsembleExport.write。保存先を選んだだけでは成功と判定しない。exporting=true/busy=true中は編集・再生を行わず、取消はキャンセル Export（cancelExport）。完了はexporting=false/busy=false・error=nil・exportedURLとExported表示で判定する。取消はExport cancelled、失敗はエラー表示で、成功と報告しない。
WAVは48 kHz/stereo/Float32、最大256 MiB、最後のイベント＋最大Release＋50 ms。開始位置・全Muteによる無音は正常。構成のdirtyは変えず、自動保存もしない。本体の試聴音量やOS音量はファイルへ反映しない。
デモで完了後閉じる→本体WAVを開く…から出力を再読み込み、assetのレート/チャンネル/長さと波形を確認して再生・停止。元音源へ上書きしない。書き出しはオフラインなのでOSの出力デバイスを必要としない。

## タイムラインの表示と開始位置操作
ARRANGEMENTで全パートを一覧し、クリップの位置と幅、START値で構成を判断する。アクセシビリティ名はTimeline clip for パート名、値はStart/length/end beats。クリップのIncrement/Decrementは¼拍。ドラッグは停止中のみ、離した時に¼拍へスナップして0〜256へ制限する。精密な任意値はStart beat for パート名へ入力する。モデル入口はEnsembleModel.movePart、計算はEnsembleTimeline.length/movedStart、UIはEnsembleTimelineView。
クリップ長はREPEAT全回分の最後の音符離鍵またはペダルイベントまでで、冒頭の休符を含み、Release余韻は含まない。Muteは幅を変えず薄く表示。無効な演奏はInvalid performanceと表示し、正常クリップと報告しない。横スクロールして後半も確認する。
操作後はSTART/クリップ値とdirty=trueを確認。保存…後の復元は既存startBeatと同一。全体を再生では位置線とBeatを確認し、移動操作をしない。全停止でplaying=false・全voices=0・位置0を確認する。クリップ端のドラッグによる長さ変更、シークは未実装。

## パートの繰り返し回数を操作する
正本は[ENSEMBLE.md](ENSEMBLE.md)。停止して各行REPEAT（Repeat count for パート名）を1〜16の整数へ設定。×1は1回、×Nは合計N回。EnsemblePart.repeatCount、EnsembleTimeline.events/repeatedLengthを使用し、同じ繰り返しをperformance.notesへ二重追加しない。間隔は最終イベント拍のceil。拍子の仮定や自動小節補正は行わない。
Demo Repeatは空き2つへPad×2/START 0・Pluck×3/START 4を追加。タイムラインの×回数・区切り・長さとREPEATを照合し、全体を再生で次の回の発音と延長されたdurationBeatsを確認。再生/処理中は回数を変更せず、全停止で全音停止・曲頭復帰を確認する。
変更後dirty=true→保存…→保存済み、再起動後repeatCount一致を確認。構成v3はparts[].repeatCount必須、v1/v2は1へ移行。WAV書き出し…も全回分を出力し、容量超過は失敗として扱う。

## セクションを作って曲の構成を組む
正本は[ENSEMBLE.md](ENSEMBLE.md)。SONG SECTIONS→セクション追加で名前・拍長を入力し、Move section earlier/laterで順序を変更。Section length for 名前で長さを読んで編集する。セクションは最大8、長さ1〜256拍、全体最大4パート。各Section for パート名から割り当て、STARTがセクション内相対値であることを確認する。Song · absoluteは曲頭基準。
EnsembleModel.sections/addSection/reorderSection/removeSection、EnsemblePart.sectionID、EnsembleSections.offset/validatePlacementが入口。並べ替え後はタイムラインのセクション帯とクリップ絶対Start/endを確認する。元performanceのbeatを同時に書き換えない。演奏が範囲を超えるエラーは長さ/START/REPEATを直してからPlay/Save/Export。勝手に切り捨てない。割当セクションの削除が拒否されたら、必要に応じてパートをSongへ変更してから削除する。
空の構成でデモ曲を使うとIntro 8→Aメロ16→サビ16と2楽器/4クリップが追加される。共通Beat 8/24からVerse/Chorusが入る。編集はdirty=true、Save後と再起動はsections配列順/ID/拍長とsectionIDの一致を確認する。v4のsections必須、旧版はセクションなし。空セクションも曲長に含み、WAVはその末尾＋余韻。停止は全停止、playing=false/全voices=0を確認する。

## 同じ楽器のセクション別演奏を操作する
正本は[ENSEMBLE.md](ENSEMBLE.md)。Add section clip for パート名メニューで対象セクションを選び、追加クリップのPreset/開く…/編集中の演奏を使うで演奏を割り当てる。Section for clip UUID in パート名、Clip start/repeat for パート名 UUIDで個別に操作する。共有Instrument/音量/Muteの変更が全クリップへ効くことを確認する。
EnsemblePart.additionalClips/allClips、EnsembleModel.addClip/editClip/setClipPerformance/openClipPerformance/removeClipが入口。最初の演奏は従来のperformance/startBeat/repeatCount/sectionIDを維持。最大8クリップ、停止中のみ編集。追加直後は最初の演奏をコピーするため、セクション範囲や重複エラーを読んでSTART/REPEAT/演奏を調整する。自動で切り捨てたり、楽器を複製してパート上限を消費しない。
タイムラインは同じ行の複数クリップ。アクセシビリティ名にパート名・演奏名・UUIDがあり、対象IDの値/ドラッグ後に他クリップの位置が変わらないことを確認。モデルのmovePart(...clip:)もIDを指定する。クリップのUUIDを推測しない。
デモ曲は2楽器/各2クリップ。保存…後のv5にはadditionalClipsが必須、旧v1〜v4は追加なしとして開く。再起動で追加ID/演奏/配置と共有音色を確認し、Export WAVは全クリップを含む。全停止で全ボイスとペダルを解除する。

## クリップ複製と展開変更
正本は[ENSEMBLE.md](ENSEMBLE.md)。停止中にDuplicate clip for パート名 UUIDメニュー→別セクション。UUIDは現在のタイムライン/追加エディターから取得する。最初の演奏にもSECTION CLIPS行に同じメニューがある。複製後のClip transpose/Clip velocity for パート名 新UUIDを操作し、元の演奏・START・REPEATが変わらないことを確認する。
モデル入口はEnsembleModel.duplicateClip(part:clip:to:)。成功時は新UUID、失敗時はnilとerror。成功時のみ追加/dirtyとなる。演奏・相対START・REPEATを保ち、楽器/mixを共有する。対象セクションの長さ不足や区間重複は自動修正せず拒否。canEdit=falseでは変更しない。最大8クリップでメニュー無効。
成功判定はクリップ数+1、元IDの値維持、新IDのsectionIDとタイムライン絶対開始の一致。editClipでコピーだけのtranspose/velocityPercentを変え、Save後/再起動後も追加IDと全設定を確認する。構成v9を使用。全体を再生とExport WAVは既存の全クリップ経路を使う。停止は全停止→playing=false/全voices=0/ペダル解除を確認する。

## セクション全体を複製する
正本は[ENSEMBLE.md](ENSEMBLE.md)。停止中、Duplicate section 名前 UUIDボタンを操作する。モデル入口はEnsembleModel.duplicateSection(UUID)、成功は新セクションUUID、失敗はnil（canEdit=falseでは変更なし、それ以外はerror）。元の直後へ同じ長さのCopyを挿入し、sectionIDが元IDに一致する全パートの全クリップを複製する。Song基準は対象外。
成功判定: sections数+1/元の次のIDが返却ID、各パートの対象クリップ数だけ追加、新しいclip UUIDとコピー先sectionID、演奏/START/REPEATの一致。コピー側のClip transpose/velocity for パート名 UUIDで展開を変え、元の値が変わらないことを確認。パート/音源は増えない。後続セクションは移動、Songは固定。
全候補を先に検証し、どこかが上限/重複/不正なら既存sections/全クリップ/dirtyを保持する。失敗時に個別複製で途中まで補わない。保存は既存v5、再起動はsection順/ID/長さと追加clip ID/設定を照合。全体を再生とWAVは延長された全構成を使う。停止は全停止→playing=false・全voices=0・ペダル解除を確認する。

## メインEnsembleワークスペース
起動入口はWorkspaceView。EnsembleModel/InstrumentLibrary/PlayerModelは同じインスタンスを共有する。左楽器を検索→一覧選択→試聴/試聴停止、割り当て（選択パート）、新規パートに追加。選択したファイルのavailableとpartを確認し、失敗はlibrary/ensemble.errorで判定する。
中央Select part 名前またはTimeline clip for パート名/演奏名/UUIDをクリック→右Inspector。Selected clip section/start/repeat/transpose/velocityを読み、編集が対象IDだけへ反映することを確認する。ドラッグ/増減は従来movePart。古いID/削除済みIDは使わず、再読込後は最新のUUIDを再取得。選択状態は未保存変更にならない。
Inspector modeをInstrumentへ切り替え、Selected instrument root/Attack/Decay/Sustain/Release/loopを操作する。setInstrumentSettingsは共有PCMを維持し基準音/ADSR/Loopだけを変更、無効値/再生中は保持する。値は構成へ保存し、ライブラリ原本を変更しない。最初のクリップもeditClip/setClipPerformance/openClipPerformanceで編集できる。
全行を一覧で操作したい場合は全パート…（旧Ensembleシート）。素材・楽器編集を開くで従来の波形/鍵盤/MIDI/Composeへ切り替え、曲の構成へで戻る。画面移動は音を止める。main表示中はStudioのPC鍵盤・MIDIを抑制、Spaceは構成の再生/一時停止、⌘Sは構成保存。Studioでは従来のキー操作へ戻る。ファイルメニューのOpen WAV/Open Instrument/デモを開くはStudioを表示する。
メインのStop all workspace audioで構成・ライブラリ試聴・Studioを停止。再生/書き出し中は割り当て・配置・音色編集不可。Stop後playing=false/全voices=0/previewing=nilを確認する。書き出しは上部WAV書き出し…、進捗とキャンセル Exportは下部。構成Openはdirty時の確認と失敗保持を継続する。

## Natural Studio: セクション帯と音符表示
上部Wood themeはWorkspaceWoodの3値。workspaceWoodThemeV1に保存し、構成dirtyとは独立。アプリ同梱Texturesを使用する。選択変更とテーマ変更で音が鳴らないことを確認。
メインのSelect section 名前 UUIDをクリック→右WorkspaceSectionInspectorのSelected section name/lengthで編集。Move selected section earlier/later、Duplicate selected section、セクション削除を使う。複製成功時は新しいセクションを選択、削除失敗は既存を保持。全パート…の旧カードも使用可。選択だけではdirtyにならず、メイン再読込/削除で存在しない選択を解除する。
メインのTimeline zoom in/outとFit arrangementは表示倍率のみ変更し、clip.startBeatを書き換えない。狭い画面/拡大時は水平スクロール。ドラッグとアクセシビリティ増減は既存movePartを使用。セクション帯/クリップは同じ拍座標で動く。
PerformanceNoteLayout.makeが実演奏から音符の時刻/長さ/移調済み音程/調整済み強弱を得る。繰り返し間隔は既存EnsembleTimelineと同じceil、終端はペダルイベントも含む。音符自体の幅は押鍵時間。Clip note gridで音符数、Clip note Nで音程/拍/強弱を確認する。下段の編集操作は次節を参照。停止は既存Stop all workspace audio、playing=false/全voices=0/previewing=nilを確認する。

## 下段クリップ音符編集
Timeline clipを選択するとSelectedClipNotesが1回分の音符を編集する。Clip note Nをクリックして選択し、Selected note pitch/start/length/velocityへ数値を入力してApply selected noteを実行する。pitchは移調後のMIDI番号、startとlengthはクリップ内の拍、velocityは全体%適用前の1〜127。既存channelとpedalsは変更しない。
Add clip noteは0拍・基準音に近い空いた音程・0.5拍・velocity90で追加。空白グリッドのクリックでも指定位置に追加できる。Delete selected clip notesは選択音を削除し、最後の1音は削除できない。ドラッグは音符本体が移動、右端が長さ変更で、1/4拍スナップ。繰り返しは全周回へ反映される。
操作の正本はEnsembleModel.editClipNotes。canEdit必須で、全クリップ検証後に適用する。成功は対象clip.performance.notes、dirty、タイムライン長、下段表示で確認。失敗はensemble.errorに表示し元データを保持する。選択だけはdirtyにしない。停止はStop all workspace audioでplaying=false、全voices=0を確認してから編集する。構成Save→再起動復元→WAV出力は同じPerformanceDocumentを使用する。

## 音符の取り消し・やり直し
下段Undo clip note edit / Redo clip note editが選択クリップの履歴入口。モデルはcanUndoNotes/canRedoNotes、適用はrestoreNoteEdit(part:clip:redo:)。各クリップ直近50操作、ドラッグ確定/Apply/追加/削除ごとに1操作。無変更・失敗は履歴へ入れず、Undo後の新編集はそのクリップのRedoを消す。別クリップの履歴は保持する。
成功はperformance.notesと上段/下段表示、dirtyで確認。選択音は解除される。セクションや音域が変わって戻せない場合はensemble.errorで判定し、データと履歴を保持する。再生/出力中は両ボタン無効、Stop all workspace audioで停止後に操作する。Save後も使えるが構成の読込成功/再起動で履歴は空。演奏置換でも対象履歴は空。履歴自体は保存せず、適用結果のみ構成保存とWAVへ反映する。キーボードのテキストUndoと混同せず専用ボタンを使う。

## 複数音符の選択と一括編集
Multiple note selection（Multi）をONにしClip note Nをクリックすると選択を追加/解除する。通常はクリックで単独選択、Shiftクリックで追加/解除。Select all clip notes / Clear note selectionも使用できる。空白から矩形ドラッグすると交差する音符を選び、Shift付きでは既存集合へ追加する。空白クリックは通常モードで音符追加、Multiモードでは選択解除。
Selected note countで選択数を確認。Selected notes beat offset / Selected notes pitch offsetへ相対拍/半音を入力し、Move selected clip notes / Duplicate selected clip notesを実行。複製は元を残す。Delete selected clip notesは選択群を削除し、最後の全音削除は不可。選択中の音符本体ドラッグも集合を移動する。単独のPitch/Start/Length/Velocityと右端リサイズは単独選択用。
正本はEnsembleModel.editNoteGroup(part:clip:indices:action:) → editClipNotes。成功時の戻り値は移動/複製後の選択インデックス集合、失敗はnilで元データを保持。全操作は一括検証し、Undo clip note edit / Redo clip note editで1操作ずつ往復できる。選択だけはdirtyにしない。再生/出力中は不可、Stop all workspace audioで停止後に操作する。構成保存/WAVは適用後の同じ演奏を使い、選択状態は保存しない。

## 選択音符のクオンタイズ
Clip note Nを単独/複数選択→Note quantize gridで1/4・1/8・1/16・1/32・1/8 T・1/16 Tを選択→Quantize selected clip notesを実行する。狭いウィンドウでは下段の選択操作バーを横スクロールする。四分音符=1拍、Tは三連符。開始拍のみ最寄りに揃え、中間値は後ろへ丸める。クリップ先頭が原点で、長さ/音程/強弱/チャンネル/ペダルと非選択音は保持する。ドラッグのスナップ間隔は変更しない。
モデルはNoteQuantizeGrid、editNoteGroup(...action:.quantize(grid))→editClipNotes。成功後も選択を維持し、Clip note NのstartとSelected note countで確認する。一括Undo/Redoは既存ボタン。既に揃っている場合は履歴/dirtyを増やさずRedoも保持する。同音重複・セクション超過などは全体を拒否しensemble.errorで通知。再生/出力中は無効、Stop all workspace audioで停止後に適用する。保存/WAVには適用済み開始拍を反映し、格子選択そのものは保存しない。

## 選択音符のベロシティ一括調整
音符を選択→Selected notes velocity modeでSetまたはOffsetを選択→Selected notes velocity valueへ整数→Apply velocity to selected notes。Setは1〜127へ統一、Offsetは−126〜126を加算して結果を1〜127へ制限する。モード切替時の入力初期値はSet=90、Offset=0。操作バーが収まらない場合は横スクロールする。
モデルはeditNoteGroup(...action:.velocity(value)/.velocityOffset(offset))→editClipNotes。成功はClip note Nのvelocityと音符の明るさ、Selected note countで確認。クリップのvelocityPercent適用前の値であり、実際のMIDI出力は既存の%調整も受ける。非選択音・開始拍・音程・長さ・チャンネル・ペダルを保持し、Undo/Redoは一括1操作。無変更は履歴/dirty/Redoを保持する。無効値はensemble.error、適用失敗時は元データを保持。再生/出力中は無効でStop all workspace audio後に操作する。保存/WAVは適用結果を使い、モード/入力値は保存しない。

## 選択音符の長さ一括調整
音符を選択→Selected notes length modeでSet beats/Scale %を選ぶ→Selected notes length valueへ正の数値→Apply length to selected notes。Set beatsは四分音符=1拍の押鍵長へ統一。Scale %は元の長さへ同じ倍率を掛け、50で半分、200で2倍。開始位置・音程・強弱・チャンネル・ペダル・非選択音は変更しない。操作バーが狭い場合は横スクロールする。
モデルはeditNoteGroup(...action:.duration(beats)/.durationScale(factor))→editClipNotes。UIは%を100で割ってfactorへ渡す。成功はClip note Nのlength、下段の幅、タイムライン全長で確認し、選択は維持する。一括Undo/Redoは1回。無変更はdirty/履歴/Redoを保持。0/負数/非有限/重複/セクション超過などはensemble.errorで通知し、部分適用せず保持する。再生/出力中は無効、Stop all workspace audioで停止後に操作。構成保存/WAVには適用後の押鍵長を反映し、ペダルとReleaseの余韻は既存処理を維持する。

## クリップ間の音符コピー・貼り付け
音符を選択→Copy selected clip notes→Copied note countを確認→別のTimeline clipを選択→Note paste beatへ貼り付け先クリップ内の拍数→Paste copied clip notes。コピー群の最初の開始を指定位置へ置き、音符間の相対リズム/長さ/チャンネルと演奏時のMIDI音程/強弱を保持する。コピー元と貼り付け先の既存音符・ペダル・設定は保持する。Paste後は新しい音符群を選択する。操作バーが狭い場合は横スクロールする。
モデルはcopiedNotes、copyClipNotes(part:clip:indices:)、pasteClipNotes(part:clip:at:)→editClipNotes。コピーはdirty/履歴を変えない。Pasteは一括1操作のUndo/Redo対象。対象の移調と強弱%を逆算し、元のMIDI強弱が対象%で再現不能なら失敗して100%へ調整する案内を出す。無断で設定を変えない。同音重複/音域外/音数/配置の失敗はensemble.errorとnilで判定し、元データとクリップボードを保持する。再生/出力中は不可、Stop all workspace audio後に操作する。クリップボードはアプリ内セッションのみで構成読込では残り、再起動で空になる。OSのクリップボードやペダルはコピーしない。保存/WAVは貼り付け済みデータを使用する。

## 複数パート・セクションのAI編曲
正本は[AI_ARRANGEMENT.md](AI_ARRANGEMENT.md)。停止したEnsembleのAI編曲…（Arrange ensemble with AI）から方式・指示を選び候補を生成。generating=false・candidate/previewあり・error=nilで案の方式/全セクション/クリップ/音符/tempo/音量/Muteを確認し、この編曲案を採用で採用する。元を保持するなら先に現在の構成を保存…。未保存時は編曲案で置き換えるの確認がある。採用で全配置/tempo/パートmixが置換され、音符Undoは消える。楽器/Masterは保持し自動再生はしない。全体を再生/全停止・Save/Exportは既存操作。生成を中止/閉じるで候補を破棄し、元構成を保持する。生成後の編集はrevision照合で採用を拒否し、再生成する。DemoはAIではない。

## 日本語UIとヘルプ
主要画面の操作名・アクセシビリティ名は日本語。以前の英語の明示ラベルはaccessibilityIdentifierへ保持している。座標/要素番号を再利用せず、現在の日本語ラベルまたは識別子で対象を特定する。内部のモデル名・保存キー・enum rawValue・モデルのfileMessageは従来のまま。例えば画面の「保存済み・ファイル名」はモデルではSavedの接頭辞を持つ。日本語表示だけでなく既存のdirty/busy/error/playingも照合する。

| 操作 | 現在のラベル | 主な識別子または入口 |
| --- | --- | --- |
| 操作と用語の説明 | 使い方と用語を開く | help.guide → StudioHelpButton |
| 説明を検索 | 使い方と用語を検索 | help.search、用語を入力。該当説明がなければ空結果文を表示 |
| 構成を開く・保存 | 構成を開く / 構成を保存 | Open ensemble / Save ensemble |
| 編曲候補 | AIで編曲案を作る | Arrange ensemble with AI |
| 素材編集へ移動 | 素材・楽器編集を開く | Open Sample Studio |
| 全音停止 | すべての音を止める | Stop all workspace audio |
| 波形ズーム | 波形を拡大 / 波形を縮小 | Zoom in / Zoom out |
| 音符追加 | 音符を追加 | Add clip note |
| 履歴 | 音符編集を取り消す / 音符編集をやり直す | Undo clip note edit / Redo clip note edit |
| 音符を拍へ揃える | 選択音符の開始を拍に揃える | Quantize selected clip notes |
| まとめて強弱・長さを変更 | 選択音符の強弱をまとめて変更 / 選択音符の長さをまとめて変更 | Apply velocity to selected notes / Apply length to selected notes |
| 音符コピー・貼付 | 選択音符をコピー / コピーした音符を貼り付け | Copy selected clip notes / Paste copied clip notes |
| タイムライン | タイムラインのクリップ パート名, 演奏名, UUID | Timeline clip for パート名, 演奏名, UUID |
| 右側の音色調整 | 基準音、立ち上がり、減衰時間、保持音量、余韻時間、素材をループ | Selected instrument root / Attack / Decay / Sustain / Release / loop（各項目はSelected instrumentの接頭辞） |

「使い方」は木材ヘッダーを持つポップオーバー。検索で「強弱」「ベロシティ」「ADSR」「保存」等の説明を確認し、「閉じる」または外側クリックで編集へ戻る。ヘルプを開いたことを候補の採用や保存と扱わない。短い説明は入力欄・設定のhelp属性にもある。
日本語UIのデモ手順: 保存済み構成かデモ曲→全体を再生→全停止→クリップ選択→下段で音符選択→音程/開始/長さ/強弱→適用→取り消し/やり直し。編曲はAI編曲…→生成方式「デモ（AIなし）」→デモ案を作る→候補を確認→この編曲案を採用。残したい元構成は先に現在の構成を保存…。既存の置換確認・再生中のロック・停止入口は維持する。

## 曲全体の編集履歴
正本は[Ensembleの曲全体履歴](ENSEMBLE.md#曲全体の取り消しやり直し)。メインのタイムライン上部、または全パート画面の「曲の編集を取り消す / 曲の編集をやり直す」（ID: Undo song edit / Redo song edit）が入口。下段のUndo clip note edit / Redo clip note editとは区別する。

モデル入口はcanUndoSong/canRedoSong、undoSongLabel/redoSongLabel、restoreSongEdit(redo:)。成功はtrue、対象データ・タイムライン・右設定とdirty=true、positionBeats=0、playing=falseで確認する。直近50操作、選択に依存しない時間順の履歴。複製/AI採用はまとめて1操作。無変更・失敗は履歴/Redoを保持、新編集はRedoを破棄する。全体Undo/Redoで全クリップの音符履歴を消し、以後は上段から続けて戻す。元の安定IDとPCM/設定を復元し、保存先は変更しない。

再生/保存/読込/出力中は無効。Stop all workspace audioで停止し、busy=falseを確認して操作する。上段の履歴適用は音声を止め、再生を始めない。AI編曲の採用も戻せるが、履歴操作でrevisionは更新されるため以前の生成候補は再採用できず、現在の構成から再生成する。保存後も履歴は使用可能、読込成功/再起動で空、読込失敗で保持。履歴はファイルに含めず、適用結果を構成保存/再生/WAVへ渡す。ライブラリの登録やSample Studio単体の編集は対象外。

デモ確認: デモ曲→クリップを¼拍移動→上段Undo/Redoで開始拍を確認→サビを所属クリップごと複製→上段Undo/Redoで帯と全クリップを確認→AI編曲をデモ生成して採用→上段Undoで元構成・Redoで採用構成へ戻る→保存/再読込/WAV出力。元ファイルを残す場合は別名保存する。

## 途中再生と範囲ループの試聴
入口はEnsembleModel.seek(to:)/pause()/play()、setPlaybackRange(start:end:enabled:)/setRangeLoopEnabled/loopSection。UIはSong timeline ruler（曲の再生位置・拍目盛り）をクリック/Increment/Decrementするか、Song seek beat→Seek song。範囲はSong loop start / Song loop end→Apply song loop range。セクション帯選択→Loop selected sectionでも設定できる。Song range loopで有効/無効を切り替える。設定は停止中・busy=falseのみ。開始/終了は曲内の有限数・¼拍以上。失敗はfalseとensemble.errorで判定、以前の範囲を保持する。

成功はpositionBeats、playbackRange、rangeLoopEnabledとタイムラインのハイライトで確認。範囲内からplayするとそこから最初の周回を開始し、以後は範囲先頭へ戻る。再生中のシークは音声を止めて再スケジュールする。playing=true、playbackPassの増加、範囲内positionBeats、各パートvoices/出力で実行を判定する。単なる候補表示やループONだけを演奏成功と扱わない。途中の保持音は先頭/Attackから再発音し、Release途中の音声位相は復元しない。

一時停止（またはメインのSpace）→playing=false/voices=0で編集→再生で同じ範囲へ戻れる。停止入口Stop all workspace audio（全停止）は全音・ペダル・予約イベントを止め拍0へ戻す。範囲自体は保持する。曲全体へ戻る場合は停止後にSong range loopをOFF、seek(to:0)して再生。非アクティブ/画面移動でも停止する。

試聴状態はdirty/revision/Undo履歴/構成保存/WAVに含めない。WAVは常に曲全体を出力する。読込成功/再起動で範囲OFF・拍0。構成短縮で範囲が曲外なら解除され、全体Undoでも試聴範囲は復元しない。デモ確認はサビ帯→選択区切り→範囲を再生→2周以上→一時停止して音符の強弱変更→再生→全停止。保存済みの元構成を変えた場合は別名保存する。

## パートのパンを調整する
入口はEnsemblePart.pan（Double、有限数−1〜1、既定0）。メイン右設定の「パン・左右の配置」、または全パート画面の同じ操作を使う。スライダーIDはPan for パートUUID、中央ボタンはCenter pan for パートUUID。アクセシビリティ名は「パート名 のパン・左右の配置」、値は中央/左 N%/右 N%。名前変更に影響されないIDで対象を解決する。

成功はpanの数値、右設定の左右%表示、dirty=trueで確認。再生中も変更可能で、ライブMixerへ30 Hzで反映。元の楽器PCM/演奏を変えず同じパートの全クリップへ適用。停止は全停止（Stop all workspace audio）。停止後に上段のUndo/Redoで戻せる。busy中は操作不可。AI編曲はパンを保持し、提案のJSONへpanを勝手に加えない。

保存…→dirty=false・busy=false→再起動/開く…でpan一致を確認。v6以降はpan必須、旧v1〜v5は0。WAVはpan/音量/Mute/Masterを含む曲全体で出力し、書き出し成功後に再読み込みで左右を検証する。デモは空き2パート→デモ→左右配置デモ、Soft Chords=-0.65/Bouncy Phrase=+0.65を確認→再生→全停止→保存。UI%と内部−1〜1を混同しない。

## パートEQを調整する
入口はEnsemblePart.eq: PartEQ(lowDB:midDB:highDB:)。各値は有限数−12〜12 dB、既定0。右設定/全パート画面の「EQ・音質」を使用。Sliderの安定IDはEQ low for パートUUID / EQ mid for パートUUID / EQ high for パートUUID、リセットはReset EQ for パートUUID。日本語アクセシビリティ名は「パート名 のEQ・低音/中音/高音」。周波数は200 Hz/1 kHz/4 kHz固定。

成功は各dB表示・part.eq・dirty=trueで判定。再生中は30 Hzで反映、busy中は無効。同じ楽器パートの全クリップに共通で、音源PCMや演奏音符は変更しない。停止は全停止（Stop all workspace audio）→playing=false/発音0。停止後は曲全体Undo/Redoで戻す。「フラット」は3帯域を一操作で0に戻す。AI編曲はEQを保持し、提案schemaへeqを追加しない。

保存…→busy=false/error=nil/dirty=false→開く…または再起動で値一致を確認。構成v7はeqの3値が必須、旧v1〜v6は0。不正データは元の構成を保持。WAVはEQ/パン/音量/Mute/Masterを含む全体出力。空き2パート→デモ→音質調整デモ（Soft Chords +6/−3/−6、Bouncy Phrase −6/+3/+6）→再生→全停止→別名保存→WAV書き出し→再読み込みが確認手順。

## パートのリバーブを調整する
入口はEnsemblePart.reverb（Double、有限数0〜100、既定0）。メイン右設定/全パートの「リバーブ・響き」。Slider IDはReverb for パートUUID、オフボタンはReset reverb for パートUUID。日本語名は「パート名 のリバーブ・響きの量」。smallRoom固定、値はwet/dryの%、100は響きだけ。再生中も30 Hzで反映し、busy中は無効。成功は%表示/part.reverb/dirtyで判定し、停止後は曲全体Undo/Redoで戻せる。
停止は全停止（Stop all workspace audio）→playing=false/各voices=0/level=−60。自然終了は音符が終わってもreleasing=trueで最大3秒の残響を待つので、発音数0だけで再生終了と判断しない。ミュートは残響も消音。オフ・範囲周回では残響リセット。一時停止/シークは響きを復元しない。
保存…→busy=false/error=nil/dirty=false→再起動/開く…で量一致。v8はreverb必須、旧v1〜v7は0、不正な後半パートでも部分反映しない。AI編曲は既存の量を保持し、提案schemaにreverbを追加しない。空き2パート→デモ→リバーブデモ（35/15%）→再生中調整→全停止→別名保存→WAV書き出し→再読み込みで余韻まで確認。楽器単体保存には含めない。

## パートのディレイを調整する
入口はEnsemblePart.delay: PartDelay(timeMS:mix:feedback:)、各値は有限数50〜1000 ms / 0〜100% / 0〜60%。既定300/0/35。右設定/全パートの「ディレイ・繰り返す音」。Slider IDはDelay time for パートUUID / Delay mix for パートUUID / Delay feedback for パートUUID、オフはReset delay for パートUUID。日本語名は「パート名 のディレイ・間隔/量/繰り返し」。間隔の単位msと拍の開始位置を混同しない。テンポ同期なし、feedback=0でも最初の1回は返る。
再生中も30 Hzで反映、busy中は無効。成功は3値/表示/dirtyで判定。「オフ」はmixだけ0にし間隔/feedbackを保持。停止後は曲全体Undo/Redoで戻せる。AI編曲は手動値を保持し、提案schemaへdelayを追加しない。
停止は全停止（Stop all workspace audio）→playing=false/voices=0/level=−60。自然終了のreleasing中は発音数0でも残響が続く。ディレイ最大15秒＋リバーブ3秒の予算を待つ。オフ・範囲周回はAUの遅延バッファもresetし、一時停止/シークは遅延音を復元しない。Muteは遅延音も消音する。
保存…→busy=false/error=nil/dirty=false→再起動/開く…で3値一致。v9はdelayの3値必須、旧v1〜v8は300/0/35。不正な後半パートでも全体を保持。空き2パート→デモ→ディレイデモ（Soft Chords 350/18/25、Bouncy Phrase 250/30/40）→再生中調整→全停止→別名保存→WAV書き出し→Studio再読み込み/再生で確認。楽器単体保存には含めない。
