# 検証方法

## 標準Verify
Python 3.9以上、Git、macOS用のXcodeコンパイラを使用。第三者依存なし。

```sh
python3 scripts/verify.py --fast
python3 scripts/verify.py
```

- Fast（実装中）: 主要文書9件の存在・内容・UTF-8・行末空白・インライン相対リンク先を確認。
- Full（完了前）: 記録と子AGENTSの文書検証、作業ツリーとステージ済み差分のgit diff --check、音声テスト、.appビルド。
- macOS以外では文書のみ検証し、native検証はSKIPと表示する。アプリの検証成功とは扱わない。
- 文書検査はコードブロック・参照形式リンク・アンカー・外部URL・意味的整合・秘密検出を対象にしない。

## Native Tests
```sh
sh scripts/test.sh
sh scripts/test.sh --playback
```

通常テスト: デモ合成、ステレオPCM16とモノラルFloat32、波形・長さ・減衰、時刻表記、壊れた／存在しないファイル。選択の逆方向・端・1フレーム、ズーム／移動／fit時の境界と選択保持、選択音声のフレーム数・全サンプル一致、チャンク境界・無効範囲・末尾1フレームも確認。WAV書き出し・再読み込み・全サンプル一致、元音源とsymlink/hardlinkの保護、失敗時の既存ファイル保持と一時ファイル清掃も確認。
--playbackは実際の出力デバイスを使用する統合テスト。ロード・再生・一時停止・シーク・停止・失敗後の元音源保持・音源交換・ゲイン・末尾からの再生を確認する。選択のみの再生、一時停止／再開、終端停止、再試聴、解除／シークによる選択再生終了、音源交換時の選択・ズームリセット、低い試聴ゲインでの書き出しと再読み込み・再生も確認する。
再生テストは発音する。短い時刻窓で発音を検査するため、実行中は別アプリでのWAVレンダー等を並行しない。音質・実際の聞こえ方・低遅延性能の保証ではない。

## Change Type → Required Validation
| 変更 | 必要な検証 |
| --- | --- |
| 文書 | Fast → Full + 内容の差分確認 |
| AudioAsset / デモ生成 / WaveformEditor / SelectionAudio / WAVExport / InstrumentSample / InstrumentDocument | sh scripts/test.sh → Full |
| PlayerModel | sh scripts/test.sh --playback → Full |
| SwiftUI / UI | Full + 実アプリで視覚・操作・ウィンドウ縮小を確認 |
| build / test / verify | 正常系と関連失敗検出 → Full |
| .gitignore | git check-ignoreで除外と例外を確認 → Full |

## 手動確認
起動→デモ波形→再生→位置とメーター更新→一時停止→シーク→停止。
Open WAVで別音源を読み込み、メタデータと波形が変わること。キャンセル・壊れたWAVでは元音源を保持すること。Load Demoで戻ること。
Space、⌘O、再生末尾、音量、最小ウィンドウも確認する。
範囲選択→境界調整→Fit Selection→概要で表示移動→Fit Allの前後で選択が変わらないこと。
選択再生→終端停止→Shift-Spaceで再試聴→Escapeで解除し、通常再生に戻ること。
ズーム時の時刻目盛、範囲外プレイヘッド非表示、最小サイズでも下部が欠けないことを確認する。

専用lint・format・CIは未導入。Swiftの型検査はビルドで行う。AI作業の実行結果と未実行はsessionsへ記録する。

書き出しUI: デモ選択→Export WAV→保存→成功表示→Open WAVから再読み込み→長さ・形式・再生を確認。保存キャンセル時は選択と音源が残ることを確認。

## Instrument Tests
通常テストは基準音の名称、半音・オクターブの倍率、取り込みフレームと元音声のサンプル一致、不正範囲を確認。
--playbackでは楽器取り込み、発音・離鍵、音の置き換え、古い離鍵の無視、ゲインと実メーター、基準音変更、末尾停止を確認。
実装のAVAudioEngineグラフをoffline renderし、440 Hz素材を440／880／220 Hzとして出力することをゼロ交差で測定する。
UIはデモのRoot A3、白鍵・黒鍵、離鍵、Root変更、Use Selection、音源交換時のリセットと小型ウィンドウを確認する。
低遅延性能・すべての操作での無音切り替え・長時間負荷は保証しない。

## Instrument Persistence
通常テスト: 保存後に元WAVを削除しても復元できること、基準音・全サンプル・チャンネル・レートの一致、mono/stereo、保存先更新、未知版・不正Root・壊れた音源の拒否。
--playback: 別PlayerModelへ読み込んで演奏、dirty状態、失敗時の楽器保持を確認する。remember:falseで通常のアプリ設定をテストから変更しない。
実UI: デモの短い範囲を取り込みRootを変更→Save…→終了→再起動→同じRoot・音源長・鍵盤発音を確認。Open…の読み込みと保存キャンセルも確認する。
外部／ネットワーク保存先、大容量ファイル、異常終了の復旧、将来版への移行は未検証。

## ADSR Verification
通常テストはtests/EnvelopeTests.swiftで各段階のレベル・時間、Attack途中の離鍵、ゼロ時間、不正値、ステレオ乗算、音程倍率を変えても同じ出力時間になることを確認。
--playbackは実際の音声グラフをoffline renderし、3音程で立ち上がり・Sustain音量・離鍵後の非ゼロ出力と終端の無音を測定する。
形式v2のADSR保存・全値一致、v1の互換値、範囲外パラメーター拒否、モデルのdirty・復元も確認する。
実UIではデモで4項目を変更→鍵盤演奏→保存→終了・再起動→同じ数値と演奏を確認。最小ウィンドウの表示も確認する。

## Loop Verification
EnvelopeTestsで複数ブロックの正確な折り返し・ステレオ一致・元サンプル長超え・離鍵Release・OFF時EOFを実レンダーで確認。
AudioTestsでv3設定一致、v1/v2のOFF互換、逆転・範囲外・短すぎるループ拒否を確認。
--playbackは選択からループ設定→短いサンプルの元の長さを超えた発音とメーター、別モデルへの設定保存・復元を確認。
UIではデモのLOOP、境界操作、保存→再起動時のON/OFF・位置復元を確認する。

## Crossfade Verification
EnvelopeTestsで不連続ランプの最大隣接差がOFF時1.98から0.1未満になることを実レンダーで確認。
ステレオの重み一致、複数ブロック、3音程でのRelease、負数・半分超の拒否、OFF時の既存ループを検証。
AudioTestsはデモの境界段差の90%以上軽減、v4全値一致、v3欠落時OFF、負数・過大値拒否を確認する。
--playbackで別モデルへクロスフェードを復元し、演奏・dirtyを確認。
UIはデモのスライダー、保存・終了・再起動後の値、ウィンドウ縮小時の表示を確認する。
段差の測定は全音源での無クリックや主観的音質を保証しない。

## Polyphony Verification
--playbackで実音声グラフをoffline renderし、3音の周波数成分、1音のRelease後の消失と他音の継続、元サンプル長を超えるループを検証。
8音上限・最古音の置き換え・Release優先・同音再使用・全音停止、入力別の所有権、クリック保持とデモ和音を確認。
従来の単音ピッチ・ADSR・ファイル保存テストも継続。和音用の固定減衰に合わせ、楽器メーター試験はMaster −12 dBで実施。
UIはデモ和音、複数鍵の点灯、1音だけ離鍵、全音停止、PCキーの押下／離鍵、最小幅での表示を確認。
実際のPC複数キー同時押しはハードウェアの制限を受ける。自動UI操作ツールは複数の非修飾キー同時押しに非対応のため、同時発音はモデル・実音声グラフと画面保持で検証する。

## MIDI Verification
通常テストのMIDITests.parserはrunning status、分割メッセージ、velocity-zero離鍵、チャンネルCC120/123、SysEx・system common・リアルタイムの扱いを確認する。
--playbackは実際のCoreMIDI仮想source→入力ポート→PlayerModel→音声エンジンで検証。
デモの3音、個別離鍵、ループ保持・メーター、チャンネル/画面入力の所有権、画面外の音、CC120の余韻停止を確認する。
入力切り替え、None時の無入力、切断前の配送破棄、仮想source削除の検出、フォーカス抑制も確認。
UIではTest inputとMIDI chord、Release MIDI、入力選択、縮小表示を確認。新規仮想sourceは終了時に破棄する。
実機・Bluetooth・遅延・長時間負荷は未検証。通常Fullの成功は仮想MIDI統合テスト成功を意味せず、--playback結果を別途記録する。

## Expression / Automatic Performance Verification
通常テストでCC64の63/64境界とCC121、プリセットの時刻順・最後の離鍵/ペダル解除、レンダーの左右ベロシティ倍率を確認。
--playbackで実グラフの32/64/127の出力比率、異なる強さの3音合算と1音離鍵後の音量を測定する。
仮想MIDIで離鍵後のペダル保持、同音再押鍵、別チャンネルと画面入力の独立性、CC123/121、切断・フォーカス喪失の解除を確認。
Pedal phraseの自動演奏を実際のCoreMIDI経路で実行し、途中停止と自然終了で音・ペダルが残らないことを確認。
UIは自動演奏、プリセット切り替え、Test pedalで離鍵後保持→解除、最小幅約1000の配置を確認。実機・ハーフペダル・長時間負荷は未検証。

## Editable Performance Verification
PerformanceTestsで内蔵プリセット変換、テンポ時刻・移調・強弱倍率、音符/ペダル保存往復と別インスタンス復元、dirtyを確認する。
未知版、不正値、非有限数、件数超過、音符重複、8音超過・ペダル未解除、範囲外を拒否し、不正保存/読込で既存データを保持することを検証。
--playbackで編集→保存→再読込→仮想MIDI演奏を確認し、変更後のテンポ時点で移調した保持音、ペダル、自然終了を検証する。
UIはEdit…で全体と個別音を変更→Save…→Done→Auto play、再起動後のOpen…と値復元、最小幅の本体と編集シートを確認する。

## Instrument Library Verification
LibraryTestsは一時領域・独立UserDefaultsでデモ2種生成、重複・既存ファイル上書き防止、名前検索、別インスタンスへの一覧復元、不正ファイル拒否、Missing、登録解除時の原本保持を確認する。
--playbackでは専用エンジンの実メーター、停止・3秒自動終了・復号中閉じる場合の世代破棄、本体の未保存変更保持、一覧ファイルの読込と鍵盤演奏を確認。既存の仮想MIDI統合も継続する。
実UIではLibrary…→Add Demos→検索→行選択→Preview→Load Instrument、未保存置換のCancel、再起動後の一覧復元、小型ウィンドウ表示を確認する。外部ボリューム・大量登録・低遅延性能は未評価。

## App Icon
FullのビルドでPNG原本から標準10画像のiconsetとICNSを生成する。生成後はInfo.plistのCFBundleIconFile、Resources/AppIcon.icnsの存在・iconutilでの展開、codesign --verify --strictで同梱と署名を確認する。原本が欠落したビルドは失敗すること。Finder・Dockのキャッシュ反映は実アプリで確認する。

## AI Performance Generation Verification
GenerationTestsは無料の模擬HTTP応答とローカルCLI fixtureを使用し、strict schema/リクエスト、HTTPエラー、refusal、未完了、壊れたJSON・音域・重複・範囲上限、CLI引数/入出力/時間切れ、取消後の応答破棄、候補採用のdirty/保存先解除/保存往復を検証。通常Fullで外部AIを呼び出さない。
--playbackはCalm/Bouncyデモ生成→候補採用→仮想CoreMIDI→デモ楽器の発音と停止を確認する。
実接続は明示的な `sh scripts/test.sh --ai-live`（Codex CLIログイン・ネットワーク・実出力が必要、使用量を消費）。build/ai-live.sfperformanceへ保存・再読込し、実生成データの発音を確認。OpenAI API実接続の成否とは区別する。
実UIは方式切替、指示、Generate/Cancel、候補ピアノロール、Use & Play、未保存置換Cancel、Edit保存、最小幅の本体と生成シートを確認。Demoを実AI応答として報告しない。音楽性は自動検証では保証しない。

## Ensemble Verification
EnsembleTestsの通常検証は共通テンポへの変換/原本tempo保持、独立割り当て、4パート上限、楽器と演奏の保存ファイルからの割り当て、無効tempo/gain/音域、未割当パートの全体開始拒否、壊れた楽器の読込時の以前の状態保持を確認。
--playbackでは同一engineの2パートへ44.1/48 kHzの440/660 Hz素材を同じMIDI音程で割り当て、両成分の同時出力と片方のペダル解除/Release後の片成分だけの消失を実offline renderで測定。デモDuoの実出力・各メーター・ミュート・停止/再開・自然終了と原子的検証、既存単一楽器/MIDI/AI演奏の回帰を確認する。
実UIはEnsemble…→Add Demo Duo→Play All→パートメーター・共通Beat、片方Mute/音量、Stop All、ファイル/現在の演奏割り当て、閉じる時の停止と再表示保持、最小幅の本体とシートを確認。長時間負荷・サンプル精度同期・外部機器・曲書き出しは未検証/未対応。

## Ensemble Persistence Verification
EnsemblePersistenceTestsは独立UserDefaults/一時領域で4パートの保存→元の楽器/演奏削除→別インスタンス起動時復元を検証。PCM全サンプル・チャンネル/レート、楽器名/Root/ADSR/Loop、演奏全値、名前/順序/音量/Mute/tempo/masterの一致を確認。
各保存設定のdirty、保存先解除なしの再保存、不正版/空構成/名前/音量/演奏/後半パートの壊れたWAV/過大サイズの拒否、失敗時の前の構成/保存先保持・既存ファイル保護、欠落ファイルと復元の一度だけの実行を確認する。
--playbackは復元したデモDuoの実出力、保存Mute・音量・tempo、Mute解除、再生だけではdirtyにならないことと停止を確認。InstrumentDocumentのmakeArchive/restore共有化に伴う既存v1〜v4互換・PCM往復・ADSR/loopの回帰も継続する。
実UIでデモの設定変更→Save…→Saved→終了/再起動→Restored/Savedと全設定→Play All、Open…の置換Cancelと保存キャンセル、縮小画面を確認。384 MB近い実データ・外部ボリューム・異常終了復旧は未評価。

## Ensemble Start Position
通常テストは0/小数/256拍、テンポ変更時の秒換算、音符・離鍵・ペダル全イベントの同一シフトと他パート不変、不正値拒否、v2保存/復元・dirty・v1の0移行、v2欠落/null/範囲外拒否を確認。
--playbackは遅延パートの開始前無音と開始後出力、曲の終了拍延長、待機中Stop後の発音なし、再開を確認。実UIはDemo Entry +4、START入力・再生中編集不可、Save/Open/起動復元、880幅シートの描画を確認する。サンプル精度や長時間の同期は未保証。

## Ensemble WAV Export
EnsembleExportTestsでデモ素材を実グラフoffline renderし、先頭待機の無音・発音・ペダル後のRelease・終端無音、個別gainとMasterのエネルギー比、全Mute、48 kHz/stereo、再読込、取消/元音源保護と一時ファイル清掃を検証する。Fullと--playbackを実行する。
実UIはデモの開始位置/音量/Muteを確認→Export WAV→成功→本体Open WAVで再読込→再生/停止。Renderingの進捗と取消、保存キャンセル、エラー時の構成保持も確認する。上限近辺の長時間出力・全音源での主観的音質は未評価。

## Ensemble Timeline
EnsembleTestsで最後のペダルまでの長さ、テンポに依存しない拍表示、不正演奏、ドラッグの¼拍丸め/境界、movePartの不正値拒否・他パート/演奏不変を確認する。実UIはデモで表示・横スクロール・ドラッグとSTART連動・再生位置線・再生中移動不可・保存/復元、4パート表示と760高シートの描画を確認。既存--playbackとFullも実行する。

## Ensemble Repeats
通常テスト: イベント数・各回の音符/ペダル全bytesと間隔、最終長、1回互換、不正回数、回数のdirty/保存復元、v1/v2の1回移行、v3欠落/null/小数/範囲外拒否を確認。実WAVで2/3回目の非ゼロ音声と延長された長さを検証。実UIはDemo Repeatの×2/×3、区切り表示、回数操作、再生中変更不可、次の回の発音、保存/再起動、全回のWAV出力を確認。Fullと--playbackを実行する。

## Song Sections
EnsembleSectionTestsで並べ替え/長さの累積位置、割り当て・ドラッグ境界、参照中削除の拒否、dirty/save/load、v4必須/重複ID/無効長/未知参照/範囲超過と失敗時保持、旧v3移行を確認。実レンダーWAVで空イントロの無音・次セクションの発音・空末尾の長さを測定。--playbackではイベント終了後も曲末まで保持しStopで解除することを確認する。実UIはDemo Song、名前/拍長/順序、パート割当、タイムライン帯、Play/Save/restart/Exportを確認。

## Shared Instrument Clips
EnsembleClipTestsで同じPCMを持つ1パートのIntro/Chorusの異なる演奏、イベント位置/音程、順序変更、個別移動/dirty/削除、v5保存/ID復元とv4移行、追加情報欠落・重複ID・未知参照・同一パート内重複と失敗時保持を確認。実WAVの両区間の非ゼロ出力/間の無音を測定し、--playbackで後半クリップの発音/停止を確認。実UIはDemo Song、同一行の複数クリップ、追加編集と他クリップ不変、保存/再起動/Exportを確認。Fullと--playbackを実行する。

クリップ複製: tests/EnsembleClipTests.swiftで最初/追加クリップの複製、元の保持、独立した移調/強弱、重複/不明ID拒否時のdirty保持、v5復元、繰り返した各セクションのWAV非ゼロ出力と再読み込みを検証。実UIはDuplicate To…から別セクション→Pitch/Velocity→タイムライン→保存/再起動を確認。

セクション複製: tests/SectionDuplicationTests.swiftで複数パートの最初/追加演奏の一括複製、元の保持、独立編集、後続移動、固定Songとの重複/一部パート上限時の全体保持、空セクション/名前長/8セクション制限、v5復元、各区間のWAV非ゼロ出力と再読み込みを確認。--playbackでコピーの移調発音、再生中の複製拒否、全音停止を確認。実UIはデモサビ複製→コピー編集→タイムライン→保存/再起動→WAV出力/再読み込み。

## Main Workspace
WorkspaceTestsは選択編集入口の最初クリップ更新・未知ID保持・追加クリップ独立性、共有PCMを保つRoot/ADSR/Loop変更、別パート保持、不正Loop拒否時のdirty保持、v5保存復元を確認。--playbackで再生中の編集ロックと停止も確認する。
UI: メイン起動→クリップ選択→右Clip編集→Instrument設定→ライブラリ検索/試聴/Assign→Space再生/Stop All→Sample StudioとArrangementの往復→All Parts…→保存/再起動→WAV書出しを確認。入力欄/モーダルでSpaceが構成を再生しないこと、最小1100×760と最大化で各列/下部操作が使えることを確認。旧Sample Studioの最小高さは880。

## Natural Studio / Note Preview
WorkspaceTestsでPerformanceNoteLayoutの全繰り返し音符をproduction MIDIの時刻・移調済み音程・強弱と照合し、ペダル終端を含む長さ/押鍵幅の区別、不正値拒否を確認する。UIでは3素材のロード/切替と再起動保持、帯の選択/名前/長さ/順序/複製/削除、音符/下段選択の同期、Fit/zoom/スクロール前後の開始位置保持とドラッグを確認。最小1100×760と1920×1080基準の最大化で表示/下段境界を確認し、保存/再起動/WAV書出し/再読み込みと既存Sample Studioの導線を確認する。全素材のbundle一致も確認する。

下段音符編集: デモで追加→選択→数値Apply→移動/右端リサイズ→削除。失敗時の元データ/dirty保持、セクション超過/隣接重複/同音重複/音域/256音上限/最後の1音を確認。選択クリップだけを変更し、反復イベント・構成復元・WAV再読み込みに同じ編集を反映。実UIで最小幅の横スクロール、再生中ロックと停止後解除も確認する。

音符Undo/Redo: 全編集種別の往復、別クリップ保持、Undo後の分岐、失敗/無変更時Redo保持、50操作上限、保存後操作と構成読込リセット、変更後の配置検証失敗を検証。実UIで矢印ボタン・再生中無効・最小サイズ・復元結果の保存/出力を確認。

複数音符: 選択群の移動/複製/削除で相対間隔と全属性保持、非選択/他クリップ保持、一括Undo/Redo、無効位置/重複/全音削除/上限で元データ保持を検証。実UIでShift/Multi/矩形/All/Clear、数値差分、選択音ドラッグ、最小幅、再生中ロック、デモ保存/WAVを確認。

クオンタイズ: 6刻み/中間値/三連符、開始拍だけの変更、非選択音/全属性保持、一括Undo/Redo、無変更時dirty保持、構成復元/イベント一致、同音重複/セクション超過の原子的拒否と再生中ロックを確認。実UIで選択→格子選択→適用→Undo/Redo、狭い画面の横スクロール、デモ保存/WAVを検証。

ベロシティ一括調整: Set/正負Offset/1〜127制限、非選択/他クリップ/全属性保持、一括Undo/Redo、整数範囲外拒否、無変更時dirty保持、構成復元とMIDI出力一致を検証。実UIで複数選択→モード/値→適用→Undo/Redo、横スクロール、再生中ロック、デモ保存/WAVを確認する。

長さ一括調整: Set/50%/200%の比率と開始位置・他属性・非選択保持、Undo/Redo、0/負数/非有限/オーバーフロー/重複/セクション超過の原子的拒否、無変更時Redo保持、構成復元/MIDI note-off一致を検証。実UIでデモのSet/Scale/履歴、狭い操作バー、再生中ロック、保存/WAVを確認。

クリップ間音符: 相対リズム/長さ/チャンネル・移調/強弱%をまたぐ実MIDI値保持、コピーdirty不変、元/既存保持、PasteのUndo/Redo、重複/不正位置/範囲/再現不能強弱の拒否、構成復元/WAVを検証。実UIで別クリップ選択→位置指定→Paste→Undo/Redo、コピー数、狭い操作バー、再生中ロックとデモ出力を確認。

## AI Arrangement Proposals
ArrangementGenerationTestsは通常Fullで外部AIを呼ばず、薄いIntro/全パートChorusと均一Demo、入力から音声/原本パスを除くこと、共通strict schema/模擬HTTP/ローカルCLI、未知/重複/欠落パート・セクション境界・重複クリップ・無効演奏の原子的拒否、取消/編集後の遅い応答破棄、採用後の楽器保持/dirty/保存/復元/WAV再読み込みを検証する。--playbackでIntroのパート発音差・再生中採用拒否・停止も確認する。実AI接続の成功とは区別する。
実UIはDemo Song→Arrange…→Demo→Generate Demoで元構成保持/候補のセクションと音符/方式/音量/Muteを確認。均一指示との違い、取消、未保存置換Cancel、先にSave Current…→Use Arrangement→メインの配置→Play All/Stop All→保存/Exportを確認。1920基準と最小1100×760でシート/スクロール/操作ボタンを確認する。実接続は利用者が選択した方式で別途確認し、DemoをAI応答と報告しない。

## Japanese UI and Contextual Help
Fullと--playbackで既存の保存/復元/演奏/レンダーを回帰検証する。モデルの状態値・enum rawValue・JSONキー・保存済みの楽器/演奏名を変更しない。実UIは保存済みデモ構成の復元、日本語ヘッダー/タイムライン/右設定/音符編集、選択→数値変更→適用→取り消し→やり直し、全体再生/停止、セクション設定、楽器の基準音/ADSR/ループを確認する。
上部「使い方」→用語検索（強弱/ADSR/保存）→該当説明/空結果→閉じる、音符欄や基準音のhelp表示、AI編曲のデモ生成/候補破棄、素材画面のデモ/自動演奏/停止を確認する。1920基準と1100×760（素材画面は高さ880）で日本語の欠け・検索結果スクロール・操作ボタンを確認する。OS標準ダイアログのボタン、外部モデル名、利用者のデータ名の言語はアプリ独自の文言と区別する。

## Song History Verification
WorkspaceTests.songHistoryで、デモ全体の一括Undo/Redo、クリップ移動/無変更/分岐、セクション編集/順序/所属クリップ込み複製、AI採用前後と安定ID/PCM共有、revision失効、保存後Undo、読込成功/失敗、未割当パート、50操作上限、Undo結果のWAVレンダーを検証。--playbackでは再生中の拒否と停止後の適用も確認。
実UIではデモのクリップを移動→上段Undo/Redo、サビ複製→上段Undo/Redo、AI編曲デモ採用→上段Undo/Redo、再生中無効/全停止後有効、最小ウィンドウと木材の表示を確認する。下段の音符Undoと全体Undoは別入口で、全体適用後は下段履歴が空になることも確認する。

## Ensemble Audition Verification
EnsemblePlaybackTestsで境界前の押鍵/サステイン状態、複数パート/チャンネル、終了境界を含まないイベント、テンポ変換、不正範囲拒否、試聴だけでrevision/履歴/dirtyを変えないこと、保存復元での範囲初期化、範囲ONでも全体WAV出力を検証する。--playbackは途中開始の保持音/ペダル、一時停止/再開、3周以上、再生中シーク、停止後編集して再生、全停止後に古いイベントが発音しないことを確認。
実UI: 拍目盛りで途中へ移動→再生→Spaceで一時停止/再開。サビ帯→選択区切り→範囲再生で周回/ハイライト→一時停止→強弱編集→再生→全停止/範囲OFF。最小1100幅と1920幅で操作欄・木材を確認する。音声の位相復元/サンプル精度/継ぎ目の音質は保証しない。

## Part Pan Verification
EnsemblePanTestsがモノラル/ステレオ合成素材を実AVAudioEngineでWAVへレンダー・再読み込みし、中央/左右端/左右中間のチャンネル別エネルギーとMuteを測定。v6全値保存/復元、v1〜v5中央互換、欠落/null/型違い/範囲外/非有限の拒否・元データ保持、Undo/Redo、AI編曲時の保持を検証。
実UIでは左右配置デモ、右設定/全パートのパン/中央、再生中変更、全停止後Undo/Redo、別名保存/再起動復元、WAV書き出しと再読み込みを確認。木材UIの1920幅/最小1100幅でも設定へ到達できること。実機のスピーカー配置や音質の評価は別。
