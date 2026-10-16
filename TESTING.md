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
