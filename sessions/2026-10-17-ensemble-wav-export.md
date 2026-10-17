# 複数パート全体のWAV書き出し

Date: 2026-10-17

## Request
開始位置・音量・ミュート・余韻を含む全体WAV出力、デモ再読み込み、既存UIとAI操作文書の保守。

## Changes
EnsembleExportで既存サンプラーのoffline render、イベント境界のフレーム分割、共通mixとRelease末尾、ステレオ48 kHz Float32・256 MiB上限を追加。Export WAV…、進捗・取消・成功表示、原本リンク保護・atomic公開を実装。構成保存のdirtyは変更しない。判断は[0019](../decisions/0019-ensemble-wav-export.md)、操作は[ENSEMBLE.md](../ENSEMBLE.md)。

## Validation
Fast・Full成功。デモ実グラフで待機無音、発音、ペダルとRelease余韻、終端無音、gain/masterエネルギー比、Mute、ステレオ48 kHzと再読込、取消・上限・原本/symlink/hardlink保護・失敗時原本保持と一時ファイル清掃を検証。
実UIは880幅の既存ダーク画面でExport WAVを確認。保存済みデモ2パート（START 0/4.5、120 BPM、Master−6 dB）をSonicForge-Ensemble-Mix.wavへ書き出し、Exported/Saved維持を確認。本体Open WAVで再読込、ステレオ48 kHz/32-bit・10.735秒・4.1 MB・波形、末尾まで再生と停止を確認。保存ファイルは各秒に非ゼロのPCMを含む。
実音声テストは既存のMute解除120 ms後のメーター判定で2回失敗。短いPluckの休符を固定時刻で判定せず、最大600 ms内の次の実出力を観測するようテストを修正。全--playback再実行成功。新しい出力テストは各回成功。最終文書リンク検査とgit diff --checkも成功。

## Remaining Issues
上限近辺の長時間書き出し・全音源での主観的音質は未評価。進捗/取消は自動テストで検証し、短いデモの実UIは即完了したため進捗中の目視確認は未実施。
