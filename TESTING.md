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

通常テスト: デモ合成、ステレオPCM16とモノラルFloat32、波形・長さ・減衰、時刻表記、壊れた／存在しないファイル。
--playbackは実際の出力デバイスを使用する統合テスト。ロード・再生・一時停止・シーク・停止・失敗後の元音源保持・音源交換・ゲイン・末尾からの再生を確認する。
再生テストは発音する。音質・実際の聞こえ方・低遅延性能の保証ではない。

## Change Type → Required Validation
| 変更 | 必要な検証 |
| --- | --- |
| 文書 | Fast → Full + 内容の差分確認 |
| AudioAsset / デモ生成 | sh scripts/test.sh → Full |
| PlayerModel | sh scripts/test.sh --playback → Full |
| SwiftUI / UI | Full + 実アプリで視覚・操作・ウィンドウ縮小を確認 |
| build / test / verify | 正常系と関連失敗検出 → Full |
| .gitignore | git check-ignoreで除外と例外を確認 → Full |

## 手動確認
起動→デモ波形→再生→位置とメーター更新→一時停止→シーク→停止。
Open WAVで別音源を読み込み、メタデータと波形が変わること。キャンセル・壊れたWAVでは元音源を保持すること。Load Demoで戻ること。
Space、⌘O、再生末尾、音量、最小ウィンドウも確認する。

専用lint・format・CIは未導入。Swiftの型検査はビルドで行う。AI作業の実行結果と未実行はsessionsへ記録する。
