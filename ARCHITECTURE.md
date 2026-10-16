# 現在のアーキテクチャ

## System Overview / Data Flow
現在は文書とその検証スクリプトのリポジトリ。アプリの実行時データフローは存在しない。

```text
README → CURRENT → 必要な設計・検索・検証・運用文書
                      ├─ decisions（判断）
                      └─ sessions（作業履歴）
```

## Technology Stack / Important Dependencies
アプリ用の言語、フレームワーク、パッケージ管理ツール、実行環境は未選定。
文書検証にはPython標準ライブラリとGitを使用する。要件・コマンドは [TESTING.md](TESTING.md) を参照。
依存マニフェストやロックファイルは存在しない。Gitは履歴管理に使用する。

## Directory Structure / Main Components
ルートに案内・状態・作業規則・構成・検索・検証・運用文書を置く。
decisions/ は重要判断、sessions/ は作業記録。主要アプリコンポーネントは未実装。scripts/verify.py が文書検証の入口。
詳しい対応は [CODEMAP.md](CODEMAP.md) を参照。

## API Structure / Database / Authentication
いずれも未実装。APIルート、テーブル、認証方式は未定。

## External Services
GitHubはソース管理先。アプリから接続する外部サービスは未設定。

## Deployment
デプロイ先・ビルド方式・CI/CDは未設定。
将来の構成は決定後に decisions/ に理由を残し、この文書には実装された構成を反映する。
