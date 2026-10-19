# 来歴付き素材ライブラリの実装方針
Date: 2026-10-19

## Request
分離音を元曲と切り出し位置に紐づけて蓄積し、検索・再利用できる素材ライブラリの実装方針を整理する。

## Investigation
分離workerとmanifest、SeparationModel、PlayerModelの一時音源所有、選択範囲、楽器v4、InstrumentLibrary、Ensembleの保存経路を確認。現在の楽器ファイルには来歴がなく、分離結果は一時保存である。

## Changes
[MATERIAL_LIBRARY.md](../MATERIAL_LIBRARY.md)に保存モデル、位置対応、検索・試聴・再利用、整合性と互換性、5段階の実装順を整理。[判断0047](../decisions/0047-material-library-plan.md)を提案として追加し、CURRENT・ROADMAP・CODEMAPと各索引を更新。アプリ実装と実データの変更なし。

## Validation
Fast成功。追加文書のリンク・書式検査と差分検査成功。SDKのSQLite3 import型検査成功。サンドボックス外で既存の通常テストとアプリビルドを含むFull成功。

## Result
SQLiteメタデータと管理音声を分離し、元曲・分離run・stem・素材を独立IDで関連付ける案を記録。位置は分離時の基準PCMに対する整数frame。元曲と選択stemを共有保存し、追加容量を確認して蓄積する。全項目は提案・未実装。

## Remaining Issues
最初の実装は来歴保持と保存基盤。分離した1区間を保存し、元ファイル移動と再起動後も元曲・位置を復元できることを確認する。その後に検索/試聴、再利用、楽器の来歴保存を進める。
