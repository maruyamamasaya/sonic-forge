# ゴミ箱素材の一括完全削除
Date: 2026-10-19

## Request
複数のゴミ箱素材を選び、他の参照を保護し共有音声を重複計上せず、影響/容量確認後にまとめて完全削除する。
## Investigation
MaterialDeletionの単体計画・保護/lease・回収journal、MaterialLibraryModel/Viewの未保存確認/検索/ページ、SQLite schema v4と既存単体/保護解除テストを確認。
## Changes
計画をrecords/ID集合へ拡張し、対象全件と削除済み祖先のhash集合から選択外参照を除く。全件のtombstone/注釈除去/journalを同一transactionで確定し、失敗音声は先頭IDのjournalから再確認する。UIは現在ページ最大50件の明示チェック、全選択/解除、対象一覧付きの共通確認。検索/ページ/表示変更でチェック解除。[判断0055](../decisions/0055-material-batch-deletion.md)。
## Validation
Fast、素材専用テスト、Full（通常ネイティブテスト・アプリビルド）、追加文書検査とgit diff --checkは成功。選択内親子/共有hashと論理容量、選択外ゴミ箱/楽器保護と追加lease、復元後の全件拒否、空/上限超過/不明ID/通常素材の拒否、取消、最後の対象でDB失敗時の全件rollback、回収失敗後の再起動/単体再試行、Modelのチェック/検索解除/確認取消/確定を一時Storeで検証。
最終テストバイナリのbuild/AudioTests --playbackも成功し、PlayerModelのロード/再生/停止/失敗保持、楽器/MIDI/構成の実出力回帰を確認。
検証用アプリの実UIで2件のチェック/ページ全選択/選択解除、2件の名前/元曲位置一覧、保護音声5ファイル・回収0の参照保護表示、取消後のチェック維持を確認。900×760の素材シートと620幅の確認画面、1100×912の最小メインウィンドウ・縮小操作を確認。既存素材は完全削除せず、一時移動したゴミ箱から2件とも復元。全catalog行と管理音声SHA-256が事前snapshotと完全一致、DB integrity/foreign_key_checkも正常。
## Limits
現在ページ最大50件。全ページを暗黙に選択しない。全ディスクの未登録ファイル走査、複数プロセスの同時編集、APFS実空き容量の保証は対象外。音声回収の部分失敗はメタデータ削除の取消ではなくjournal再確認で扱う。
