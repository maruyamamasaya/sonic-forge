# AI向け操作・演奏ガイド

最終確認: 2026-10-16

## この文書の役割
AIがアプリを操作・拡張するときに、操作の入口、観測する状態、停止方法を短時間で把握するためのガイド。
現在地は[CURRENT.md](CURRENT.md)、構造は[ARCHITECTURE.md](ARCHITECTURE.md)、人向けの詳しい操作は[OPERATIONS.md](OPERATIONS.md)、コードの配置は[CODEMAP.md](CODEMAP.md)を正本とする。
実装と異なる場合はコード・テストを確認し、本書を更新する。

## 現在できることと境界
- WAVを読み込み、範囲を切り出してサンプラー楽器へ取り込み、基準音・ADSR・ループ・クロスフェードを設定できる。
- 最大8音を画面・PC・MIDIから演奏でき、MIDIの強弱とサステインペダルに対応する。
- 内蔵3種類を元にテンポ・移調・強弱・個別音符・ペダルを編集・保存し、Auto playで自動演奏できる。実機や演奏スキルは不要。
- 演奏データの外部ファイル読込・保存は対応済み。AIによるフレーズ生成、録音・曲の書き出しは未実装。
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
| 音色を保存・復元 | Save… / Open… | saveInstrumentPanel / openInstrumentPanel、InstrumentDocument |
| MIDIを選ぶ | MIDI IN / None | MIDIInput.select / refresh |
| 実機なしの手動確認 | Test input、VELOCITY、Test pedal、MIDI chord | createTestInput、testVelocity、sendTest、toggleTestChord |
| 自動演奏 | プリセット、Auto play / Stop auto | performancePreset、playPerformance / stopPerformance |
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
AIがファイルを作成し、Edit… → Open…で読み込める。現時点ではアプリ自身のAI生成や外部操作APIは未実装。
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
