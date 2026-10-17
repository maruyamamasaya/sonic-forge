# 0033: 選択音符の長さ一括調整

下段LengthのSet beatsは選択音符を同じ正の拍数へ揃え、Scale %は元の長さへ同じ正の倍率を掛ける。四分音符=1拍、50%=半分、200%=2倍。開始位置を固定し、音程・強弱・チャンネル・ペダル・非選択音を保持する。モード切替の入力初期値はSet=1拍、Scale=100%。

NoteGroupAction.duration/durationScaleから既存editClipNotesへ委譲する。一括適用は1回のUndo/Redo対象で、無変更ならdirty/履歴/Redoを保持する。倍率は比率を保つため丸めや切り詰めを行わない。ゼロ・負数・非有限値、演奏範囲/同音重複/セクション超過などは全体を拒否して元データを保持する。

保存形式・再生・WAV出力は既存のPerformanceDocumentを共有し、モードと入力値はView内状態のみ。ペダルやADSR Releaseの余韻は押鍵長と分け、今回変更しない。
