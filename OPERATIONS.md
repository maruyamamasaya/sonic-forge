# 開発・運用

## Local Development
ソース取得先: https://github.com/maruyamamasaya/sonic-forge

```sh
git clone https://github.com/maruyamamasaya/sonic-forge.git
cd sonic-forge
```

現在は文書と文書検証スクリプトのみ。依存インストール・アプリ起動コマンドはない。
開発開始時は [AGENTS.md](AGENTS.md) → [CURRENT.md](CURRENT.md) を確認する。
検証環境と標準コマンドは [TESTING.md](TESTING.md) を参照。

## Environment Variables
必須環境変数は未定義。.env と .env.* はGit除外、.env.example は追跡可能。
導入時は変数名・用途・必須条件を記録し、例には秘密値を含めない。

## Database Setup / External Services
DBは未導入。アプリ用外部サービスは未設定。
GitHubへのpushには対象リポジトリの書き込み権限とGit認証が必要。

## Build / Deploy
ビルドコマンド、デプロイ先、CI/CDは未設定。GitHubへのpushはアプリのデプロイではない。
導入後、実際の設定ファイルと手順への参照をここへ追加する。

## Troubleshooting
- 起動方法が見つからない: 現在はアプリ未実装。CURRENT.mdと実ファイルを確認する。
- pushできない: git remote -v で接続先、git status で状態を確認し、認証・権限・リモートとの差分を調べる。履歴を強制上書きしない。
- 環境ファイルが追跡されない: .gitignoreを確認する。秘密値を追跡するために除外を解除しない。
