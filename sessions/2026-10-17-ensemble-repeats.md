# パート演奏の繰り返し

Date: 2026-10-17

## Request
回数指定の繰り返しを再生・タイムライン・構成保存・WAV出力へ反映し、デモとAI操作文書を更新する。

## Changes
REPEAT（合計1〜16回）、元演奏の整数拍ceil間隔での全MIDIイベント展開、タイムライン合計幅/境界/回数表示、構成v3とv1/v2の1回移行、Demo Repeat（0拍×2/4拍×3）を追加。再生とWAVでEnsembleTimeline.eventsを共有し、元演奏は保持。判断は[0021](../decisions/0021-ensemble-repeats.md)、操作は[ENSEMBLE.md](../ENSEMBLE.md)。

## Validation
Fast・Full（通常テストとアプリビルド）・--playback成功。イベント全bytes/回数/間隔/開始位置、タイムライン合計長、不正回数、回数のdirty/保存復元・旧v1/v2互換・v3必須/範囲/小数拒否を確認。実レンダーWAVの延長と2/3回目の音声を測定。既存の再生・保存・書き出し回帰も成功。
実UIで旧v2構成の×1復元、Demo Repeatの×2/×3・区切り・長さ、REPEAT Incrementと合計幅の連動、再生中の編集不可を確認。240 BPM・両パート×3へ変更し、Beat 41.1/51.9で第3回の両パート発音を確認、Stop Allで0音/無音・曲頭へ復帰。別名保存→再起動で×3・開始0/4拍・全体長・Saved/Restoredと停止状態を復元。WAV出力成功、13.51752秒と第3回区間の非ゼロPCMを確認。最終リンク検査とgit diff --checkも成功。

## Remaining Issues
反復間隔の任意指定・セクション編曲は未実装。上限近辺の長時間負荷は未評価。回数増加によりWAV上限を超える構成は書き出し時に拒否する。
