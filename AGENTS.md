# AIエージェントの作業ルール

## 開始時・探索予算
1. このファイル → [CURRENT.md](CURRENT.md) の順で共通ルールと現在地を確認する（Level 1）。
2. 要求に関係する [ARCHITECTURE.md](ARCHITECTURE.md) / [CODEMAP.md](CODEMAP.md) の節だけ読む（Level 2）。
3. [CODEMAPの検索戦略](CODEMAP.md#検索方法) に従い検索結果から対象を絞る（Level 3）。
4. 対象ファイルと適用される子AGENTS.mdを読む（Level 4）。
5. 定義・参照元・関連テスト・設定・データ依存を確認してから変更する（Level 5）。
AIによる操作・演奏・プリセットを扱う場合は [AI_OPERATIONS.md](AI_OPERATIONS.md) の関係する節を読み、変更時は操作入口・状態判定・停止方法も保守する。
必要な場合だけ [OPERATIONS.md](OPERATIONS.md) と [decisions/](decisions/README.md) を参照する。履歴全件を毎回読み込まない。

## 階層ルール
ルートは共通ルールのみ。対象への経路上にあるAGENTS.mdを追加で読み、下位の具体的ルールはその配下に適用する。指示が両立しない場合は矛盾を明示し、推測で進めない。
子AGENTS.mdは独立した技術スタック・検証手順・変更ルール・強い責務境界のいずれかが生じた領域にだけ置く。現在は [app/AGENTS.md](app/AGENTS.md) がmacOSアプリ固有の追加ルール。

## 調査と変更
- 無差別に全ファイルを読まず、関数名・クラス名・Component名・Route名・API Path・DB Table・環境変数・エラーメッセージ・Feature名・Test名・TODO / FIXMEを検索する。
- 入口 → 主要処理 → データアクセス → 外部依存 → テストの流れを確認する。存在しない層は推測で補わない。
- 実際のコード・設定・テストを実装の正本とする。ただし、実装の事実と意図された仕様、過去の判断、不具合を区別する。不明なことは不明と書く。
- 既存仕様を尊重し、要求に必要な小さな変更を優先する。無関係なリファクタリングや依存更新を行わない。
- 新しい重要な設計判断は decisions/ に理由と代替案を残す。
- 秘密情報・個人情報・生の実行ログを文書へ保存しない。

## 終了時
- 実装中はFast、完了前はFullを [TESTING.md](TESTING.md) に従い実行する。未整備・未実行・成功を区別する。
- sessions/ に短い作業記録を残す。
- 状態は CURRENT.md、構成は ARCHITECTURE.md、主要配置は CODEMAP.md、検証は TESTING.md、運用は OPERATIONS.md の該当箇所を更新する。
- READMEは人間向けの入口に保ち、詳細を重複させない。

## 文書の保守
詳細は役割ごとの正本へリンクし、コピーしない。CURRENTは現在地だけ、CODEMAPは主要入口だけ、sessionsは結果だけを残す。文書が別責務の詳細で膨らんだら分離し、入口にはリンクを残す。
更新条件: CURRENTは状態変更、ARCHITECTUREは構造変更、CODEMAPは入口・主要配置変更、TESTINGは検証変更、OPERATIONSは起動・運用変更。重要判断のみdecisions、AI作業終了時はsessionsへ記録する。
