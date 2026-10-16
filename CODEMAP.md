# コードと情報の地図

## 現在の入口
| 目的 | 主なファイル | 検索キーワード |
| --- | --- | --- |
| コンセプト・人間向け案内 | README.md | SonicForge、音 |
| 現在地・次の作業 | CURRENT.md | 未実装、次に行うこと |
| AI作業規則 | AGENTS.md | 開始時、終了時 |
| 実装構成 | ARCHITECTURE.md | Technology、API、Database |
| 検証 | TESTING.md | 検証、未整備 |
| 開発・運用 | OPERATIONS.md | Local、Environment、Deploy |
| Git除外設定 | .gitignore | .env、dist、build |
| 設計判断 | decisions/ | Context、Decision |
| 作業履歴 | sessions/ | Request、Validation |

## アプリケーションコード
Application Entry、UI、API、Database、Authentication、外部依存、Testsはすべて未実装。
追加した際は「機能 → 実際の主要ファイル → 検索語」をここに追記する。将来の推奨パスを実在するパスとして書かない。

## 検証基盤
- Feature: ドキュメント自動検証
- Primary paths: `scripts/verify.py`
- Search keywords: `check_documents`、`CORE`、`--fast`
- Key entry points: `main` → `check_documents`
- Related tests: 専用テストスイートは未整備。検証方法と限界は [TESTING.md](TESTING.md)。

今後の機能もFeature / Primary paths / Search keywords / Key entry points / Related testsを短く追記する。

## 検索方法
| 分かっていること | 優先する探索 |
| --- | --- |
| 概念だけ | 利用可能ならsemantic / repository search。なければ概念の同義語で範囲を絞る |
| 関数・クラス名 | symbol / exact searchで定義を特定 |
| 特定文字列・環境変数・エラー | rg / git grepの完全一致検索 |
| 呼び出し元・影響範囲 | references searchと関連テスト検索。なければシンボル名を横断検索 |

semantic検索やインデックスの設定はリポジトリ内にない。実行環境で利用可能かを確認し、導入を前提にしない。検索結果は候補であり、正確なシンボル・パスが分かったらexact / symbolへ切り替え、実ファイルで裏付ける。インデックスの鮮度・未追跡ファイルの収録範囲にも注意する。
対象を絞った後、定義・参照・テスト・設定・データ依存と、対象へ適用されるAGENTS.mdを確認する。

```sh
rg --files --hidden -g '!.git/**'
rg -n -F '検索する関数名' .
rg -n 'TODO|FIXME' .
git grep -n '検索語'
```

rgは通常隠しファイルや除外対象を省く。.gitignoreなどは必要に応じ明示して読む。
文書中の例と実際の実装を区別し、必要なら検索対象ディレクトリを限定する。
rgがなければ git grep やIDEの検索・シンボル検索を使う。git grepは通常未追跡ファイルを含まない。
検索の一致なしは機能が不要・仕様がないことの証明にはならない。
