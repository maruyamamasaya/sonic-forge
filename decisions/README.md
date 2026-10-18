# 設計判断の記録

将来の作業者が理由を必要とする重要判断だけを記録する。
番号は既存の最大番号の次を使い、NNNN-short-title.md とする。
変更後の判断は元記録を消さず、新記録から置き換え先・元判断へリンクする。

新しい記録は以下を埋める。

```markdown
# NNNN: 判断の名前
Date: YYYY-MM-DD
Status: proposed / accepted / superseded

## Context
背景と制約。
## Decision
決めたこと。
## Reason
理由と根拠。
## Alternatives
検討した代替案と採用しなかった理由。
## Consequences
影響、制約、見直し条件。
```

- [0001: AI開発用情報の配置](0001-ai-development-docs.md)

- [0002: 最初のmacOS再生基盤](0002-native-playback.md)

- [0003: 選択再生のフレーム境界](0003-selection-preview.md)

- [0004: 選択範囲のWAV書き出し](0004-wav-export.md)

- [0005: 単音サンプラー楽器](0005-sample-instrument.md)

- [0006: 音源同梱の楽器保存](0006-instrument-document.md)

- [0007: ADSRと保存形式v2](0007-adsr.md)

- [0008: サンプルループ](0008-sample-loop.md)

- [0009: ループクロスフェード](0009-loop-crossfade.md)

- [0010: 8音ポリフォニー](0010-polyphony.md)

- [0011: MIDI入力](0011-midi-input.md)

- [0012: MIDI表現と自動演奏](0012-midi-expression-presets.md)

- [0013: 編集可能な演奏ファイル](0013-editable-performances.md)

- [0014: 楽器ライブラリ](0014-instrument-library.md)

- [0015: AI演奏生成](0015-ai-performance-generation.md)

- [0016: 複数パートの同時演奏](0016-ensemble-playback.md)

- [0017: 複数パート構成の保存](0017-ensemble-persistence.md)

- [0018: パート開始位置を拍単位で保存する](0018-ensemble-start-beats.md)

- [0019: 構成全体のWAVレンダー](0019-ensemble-wav-export.md)

- [0020: パート構成タイムライン](0020-ensemble-timeline.md)

- [0021: パート単位の繰り返し](0021-ensemble-repeats.md)

- [0022: 曲のセクション構成](0022-song-sections.md)

- [0023: 共有楽器の複数演奏クリップ](0023-shared-instrument-clips.md)

- [0024: 演奏クリップの複製](0024-clip-duplication.md)

- [0025: セクション全体の複製](0025-section-duplication.md)

- [0026: Ensembleメインワークスペース](0026-ensemble-workspace.md)

- [0027: Natural Studioの素材とタイムライン表示](0027-natural-studio.md)

- [0028: 下段でのクリップ音符編集](0028-clip-note-editing.md)

- [0029: クリップごとの音符編集履歴](0029-note-edit-history.md)

- [0030: 音符の複数選択と一括編集](0030-note-multiple-selection.md)

- [0031: 選択音符の開始位置クオンタイズ](0031-note-quantization.md)

- [0032: 選択音符のベロシティ一括調整](0032-group-note-velocity.md)

- [0033: 選択音符の長さ一括調整](0033-group-note-duration.md)

- [0034: クリップ間の音符コピーと貼り付け](0034-note-clipboard.md)

- [0035: AI編曲提案と採用](0035-ai-arrangement-proposals.md)

- [0036: 人が操作できる日本語の制作画面と説明](0036-human-operated-japanese-ui.md)

- [0037: 曲全体の編集履歴](0037-song-edit-history.md)
