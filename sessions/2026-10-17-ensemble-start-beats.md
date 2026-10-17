# パートの演奏開始位置

Date: 2026-10-17

## Request
パートの入るタイミングをずらし、設定を保存できるようにする。既存UI、デモ、AI操作文書も保守する。

## Changes
各パートにSTART入力・1拍ステッパー（0〜256拍、小数可）、全イベントの開始シフト、終了位置の延長、dirty追跡を追加。Demo Entry +4はPad=0/Pluck=4のDuoを追加。構成v2でstartBeatを保存し、v1を0で読み込む。判断は[0018](../decisions/0018-ensemble-start-beats.md)、操作は[ENSEMBLE.md](../ENSEMBLE.md)、形式は[ENSEMBLE_FORMAT.md](../ENSEMBLE_FORMAT.md)。

## Validation
Fast・Full（通常テストとアプリビルド）・実音声--playback成功。全イベントの同一シフト・他パート不変・共通テンポ換算・0/小数/上限・不正値、保存/復元・dirty・v1互換・v2必須フィールド検証に成功。実出力で開始前の無音、開始後の発音、待機中停止と再開、終了拍の延長を確認。
実UIで旧v1構成をSTART 0で復元。Demo Entry +4の0/4拍を確認し、120 BPM・Pluck=4.5へ編集。開始直後Padのみ発音、Beat 4.7でPluck発音・終了20.4拍、再生中START編集不可、Stop Allと別名保存を確認。880幅で描画に欠けなし。アプリ終了/再起動後、Restored・Saved・START 0/4.5・120 BPM・停止状態の一致を確認。

最終文書・作業記録のリンク検査とgit diff --checkも成功。

## Remaining Issues
サンプル精度同期・長時間負荷は未評価。タイムライン表示、繰返し、曲書き出しは未実装。
