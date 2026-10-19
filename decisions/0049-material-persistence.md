# 0049: 来歴付き素材の保存基盤
Date: 2026-10-19
Status: accepted

## Context
[0047の計画](0047-material-library-plan.md)を受け、ユーザーが最初の実装単位である来歴付き保存と再起動後の位置復元を依頼した。

## Decision
段階1〜2をSQLite3 schema v1と管理音声で実装する。元入力・基準元曲・選択stem全長・短い切片をhash共有し、source/run/stem/materialの関係と半開整数frame範囲を保存する。SeparationLeaseで採用した一時jobの寿命を延長する。容量を確認して明示保存し、再起動後は全長波形に元の範囲を戻す。重複登録は既存素材を返す。検索・タグ・削除・楽器v5は次段階。

## Reason and Alternatives
切片のみ/外部パスのみでは元曲移動後に文脈を復元できない。全長stemへの復元なら再切り出し時も同じframe座標で扱え、短いclipの開始offsetを二重加算しない。SQLiteはOS標準で、外部パッケージは追加しない。楽器への来歴保存は現在の形式/構成に広く影響するため別段階とする。

## Consequences
親音声を含む容量が必要。公開音声とDBは単一transactionではないため、staging検証→ファイル公開→DB commitの順とし、失敗時に未参照objectsが残ることを許す。回収を急いで既存素材を失わない。破損/未知版は自動初期化しない。バックアップは終了後の管理フォルダ全体コピーとし、将来の移行/修復/削除UIは別途設計する。実装範囲の正本は[MATERIAL_LIBRARY](../MATERIAL_LIBRARY.md)。
