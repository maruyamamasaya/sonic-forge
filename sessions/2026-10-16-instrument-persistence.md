# 楽器の保存・起動時復元
Date: 2026-10-16

## Request
サンプル音源と基準音をまとめて保存し、再起動後に復元できるようにする。既存UIを維持する。

## Investigation
取り込み済みPCMとRootの状態、既存の一時音源管理、鍵盤とファイル操作、テスト・文書を確認。
元のWAVではなく、実際に鍵盤へ取り込んだバッファを保存する必要がある。

## Changes
InstrumentDocument.swiftにversion付き単一JSON（.sfinstrument）を追加。Float32 WAV本体、Root、表示名を同梱してatomic保存。
鍵盤部にOpen…／Save…、Fileメニューに⇧⌘O／⌘S、未保存マーカーを追加。
最後の保存／読込先をUserDefaultsへ記録し、起動時に復元。読込失敗は元の状態を保持し、起動時失敗はデモにフォールバック。
音源展開は一時領域のみで行い、通常終了・交換時に清掃。関連テスト、設計判断0006と文書を更新。

## Validation
Fast / Full Verify成功。--playback成功。
元WAVを削除後も全サンプルとRootを一致させて復元、mono/stereo、上書き、壊れた文書・未知版・不正Root拒否をテスト。
新しいPlayerModelへの復元と鍵盤演奏、dirty表示、読込失敗時の元楽器保持を確認。
実画面でデモの0.082〜1.071秒を取り込みRoot F4で保存→終了→再起動し、0.989秒の音源とF4を自動復元して演奏確認。
Open…から同じ楽器を手動で開けることも確認。保存先はbuild/SonicForge-demo-instrument.sfinstrument（Git除外）。

## Result
元の一時デモやWAVの場所に依存しない楽器保存と、再起動後の復元・演奏ができる。

## Remaining Issues
音源とRootのみ保存。自動保存・終了時確認・編集状態・Master Gain・楽器ライブラリは対象外。
大容量・外部／ネットワーク保存先・異常終了時の復旧・将来版移行は未評価。変更は未コミット。
