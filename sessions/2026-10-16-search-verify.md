# 検索と自動検証の強化
Date: 2026-10-16

## Request
少ないコンテキストで探索・変更・検証を完了できる開発基盤へ強化する。

## Investigation
既存の全開発ガイド・判断記録・作業記録とファイル一覧を確認。文書は短く、アプリは未実装。
関数・API・DB・テスト名・環境変数・エラーの検索性はアプリコードがなく評価不可。大規模renameの必要なし。
検証入口とsemantic / symbol / referencesの選択基準が不足。独立領域や検索インデックス設定は存在しない。
前回の未コミット変更を保持した。

## Changes
追加: scripts/verify.pyとこの記録。第三者依存を増やさずPython標準ライブラリを採用。
更新: AGENTS、CURRENT、ARCHITECTURE、CODEMAP、TESTING、OPERATIONS、sessions/README。
検索戦略はCODEMAP、検証詳細はTESTINGに集約。共通規則・階層適用条件・更新条件をAGENTSに定義。
独立した責務境界がないため子AGENTSは追加しない。記録テンプレートから独立したFiles Changed欄を除きChangesに統合した。過去の記録は保持。

## Validation
Fast / Fullを実行。一時データで正常系、欠落文書、壊れたリンク、行末空白、リポジトリ外リンク、Fast / Fullの対象差を確認。
作業途中の未作成sessionへのリンクも検出し、この記録追加後に再検証。
アプリ用検証は未整備。外部URL・見出しアンカー・仕様の正しさは自動検証対象外。

## Result
検索方式・文書更新条件・適用ルールを明確化し、1コマンドの標準Verifyを追加。

## Remaining Issues
アプリ導入時に実コードの入口・名前・関連テストを追記し、検証コマンドを集約する。CIは未導入。
semantic検索の利用可否・鮮度は各実行環境で確認が必要。アプリ規模が増えた際の有効性は未検証。
