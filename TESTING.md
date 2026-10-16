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
| AudioAsset / デモ生成 / WaveformEditor / SelectionAudio / WAVExport | sh scripts/test.sh → Full |
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
