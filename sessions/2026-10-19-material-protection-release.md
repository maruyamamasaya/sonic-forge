# 素材の参照一覧と保護記録の個別解除
Date: 2026-10-19

## Request
素材に関係する楽器・構成の参照を確認し、影響と回収容量の確認後に不要な保護記録を安全に解除する。
## Investigation
MaterialDeletionの既存schema v4と理由/素材ID単位の永続保護、PlayerModel/EnsembleModelの現在参照・履歴、既知ファイル監査、lease、回収journalを確認。
## Changes
MaterialDeletionに参照一覧、transaction内の仮解除rollback計算、使用中拒否とsnapshot再検証付き解除を追加。MaterialLibraryModel/Viewに一覧と確認・取消、削除済み来歴メニューを追加。解除は保護1行のみで、音声回収は別途明示確認。schemaと楽器/構成形式は維持。[判断0054](../decisions/0054-material-protection-release.md)。
## Validation
Fast、Full（通常ネイティブテスト・アプリビルド）、最終コードのsh scripts/test.sh --materials-only、追加文書リンク検査とgit diff --checkは成功。保存素材の容量0、削除済み音声の解除容量、使用中/登録ファイル拒否、不明ファイル停止、lease追加による古い計画拒否、解除時の全音声不変、再起動後の解除維持・回収容量一致・来歴への復帰を一時Storeで確認。
実アプリの検証用設定で参照一覧、登録済みファイルの解除無効、過去記録の容量/残る参照、取消を確認。1100×912の最小ウィンドウと縮小操作、確認シートの表示/操作を確認。本番素材の保護解除・完全削除は行わず、既存素材/注釈/来歴/管理音声と削除状態が事前snapshotから不変であることを確認。
## Limits
過去記録は実在ファイル台帳ではない。既知/登録ファイルと現在参照を確認し、全ディスク走査はしない。同名ファイルは従来の理由キーで保守的に保護する。容量は選択素材と削除済み祖先の論理サイズ。解除時の自動回収・一括解除は対象外。
