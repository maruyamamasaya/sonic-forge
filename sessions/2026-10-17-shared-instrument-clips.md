# 同じ楽器の複数セクション演奏

Date: 2026-10-17

## Request
同じ楽器を複数セクションで再利用し、演奏を別々に割り当て、タイムライン・保存・WAVへ反映する。既存UI・デモ・AI操作文書を保守。

## Changes
パート内の追加演奏クリップ（合計最大8）、個別Section/演奏/START/REPEAT、共有音色/mix、同一行の複数クリップと個別移動、v5保存とv1〜v4互換を追加。同一パート内の区間重複を拒否。Demo Songを2楽器/4クリップへ更新。判断は[0023](../decisions/0023-shared-instrument-clips.md)、操作は[ENSEMBLE.md](../ENSEMBLE.md)。

## Validation
Fast・Full（通常テストとアプリビルド）・--playback成功。PCM共有・異なる演奏の音程/配置・順序追従・個別編集/dirty/削除・v5保存/ID復元・v4移行、追加必須/重複ID/未知参照/重なりと失敗時保持、実WAVの両区間発音/間の無音、後半クリップの実発音と停止を確認。テスト初回のthrow式をprecondition外へ移してコンパイル修正後に成功。
実UIで旧v4の読込、Add Section Clipで既存Intro Padへサビを追加、追加側だけArpeggioとSTART 0.5へ変更し、先頭の演奏/開始を保持。2パート・3クリップの同一行表示と横スクロール、追加クリップのアクセシビリティIncrementを確認。横スクロール後のドラッグ判定を修正し、追加側を24 px（1拍）移動して絶対29.75拍/相対1.75拍へ更新、他クリップ不変を確認。別名保存→再起動で追加ID/Arpeggio/配置とSaved/Restored・停止状態を復元。実UIでWAV出力成功、11.55002秒とIntro/サビ両区間の非ゼロPCMを確認。無効なクリップIDが先頭演奏を動かさない保護とテストも追加。最終文書リンク検査とgit diff --check成功。

## Remaining Issues
同一パート内の区間重ね合わせ、クリップ別mix・音色上書きは未対応。最初のクリップは従来の入口で編集し、削除はパート全体のRemoveを使う。
