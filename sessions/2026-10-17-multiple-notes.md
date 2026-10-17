# 2026-10-17 複数音符編集

複数選択と一括移動/複製/削除を既存の検証・履歴経路へ接続。Shift/Multi/矩形/All/Clearと数値差分操作を追加。Fast / Full / --playback成功。集合の相対位置/全属性/非選択保持、一括Undo/Redo、配置/重複/全音削除/256音上限拒否、保存復元とWAV再読み込みを検証。実UIでMulti/Shift/矩形/All/Clear、2音ドラッグ/数値移動/複製/削除とUndo/Redo、再生中ロックと停止後復帰、最小サイズを確認。Shiftを修飾キー付きSwiftUI Gestureへ調整して最終ビルド確認済み。build/SonicForge-MultipleNotes-Final.sfensembleを保存し、全体WAVを書き出した。保存済み・停止状態で表示。

コミット前の追加調整: ヘッダーを横木目、左右を縦木目として使い分け、WoodSurface全体を面の寸法へクリップしてずれ/はみ出しを防止。
ヘッダー修正後もFast/Full成功。基準サイズと最小サイズの実画面で横木目とクリップ範囲を確認した。
