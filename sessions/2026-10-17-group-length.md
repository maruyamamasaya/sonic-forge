# 2026-10-17 長さ一括調整

選択音符のSet beats/Scale %を既存の一括検証・履歴へ追加。開始位置と他属性を保持し、比率を崩さず拒否する制約とAI操作を文書化。Fast / Full / --playback成功。Set/50%/200%での比率、開始位置/他属性/非選択保持、Undo/Redo、無効数値/重複/境界の原子的拒否、無変更時Redo保持、構成復元とMIDI note-off一致を検証。実UIで7音を1拍へ統一→Undo/Redo、50%短縮と150%伸長、最小幅の横スクロール、再生中ロック/停止後復帰を確認。build/SonicForge-GroupLength.sfensembleを保存し、全体WAVを出力した。保存済み・停止状態で表示。
