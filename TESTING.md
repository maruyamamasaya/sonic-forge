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
再生テストは発音する。音質・実際の聞こえ方・低遅延性能の保証ではない。

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
