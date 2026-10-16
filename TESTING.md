# 検証方法

## 標準Verify
Python 3.9以上とGitを使用。第三者パッケージの追加は不要。
リポジトリルートで実行する。

```sh
python3 scripts/verify.py --fast
python3 scripts/verify.py
```

- Fast（実装中）: 主要文書9件の存在・空でないこと・UTF-8・行末空白・インライン相対リンク先を確認。
- Full（完了前・標準）: Fastに加えdecisions / sessionsのMarkdownと対象AGENTSを確認し、作業ツリーとステージ済み差分の `git diff --check` を実行。
- エラーは終了コード1、成功は0。既存の未コミット変更もFullの検証対象になる。

スキャンは主要文書・記録ディレクトリ・AGENTSに限定。隠しディレクトリ、node_modules / dist / build / vendor配下の子AGENTSは対象外。
インラインリンクのパスのみを検査し、コードブロック、参照形式リンク、見出しアンカー、外部URLの到達性、文書の意味的整合、秘密情報の検出は対象外。これらは差分レビューで確認する。

## Change Type → Required Validation
| 変更 | 必要な検証 |
| --- | --- |
| 文書 | 作業中Fast → 完了前Full + 内容・リンク見出し・秘密情報の目視確認 |
| verifyスクリプト | 正常実行 + 一時領域で欠落文書・壊れたリンクなどの失敗検出確認 + Full |
| .gitignore | git check-ignoreで除外と例外を確認 + Full |
| 構成・入口の変更 | 関連文書と実ファイルの照合 + Full |
| 将来のUI / API / 共通ロジック / DB | 実装時に関連テスト・型検査・必要な統合／migration検証を定義して、この表と標準Verifyへ反映 |

## アプリ用検証の状態
lint、format、typecheck、unit、integration、E2E、build、migration、security checkは未整備。
標準Verifyは文書基盤の検証であり、アプリの安全性を保証しない。既存のアプリ用コマンドはまだない。
アプリ導入後は既存コマンドを集約し、重いE2E等は実行時間と変更範囲に応じ標準から分ける。
未整備・未実行・成功を区別してsessionsへ残す。
