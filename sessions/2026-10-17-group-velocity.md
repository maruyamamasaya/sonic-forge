# 2026-10-17 ベロシティ一括調整

選択音符へのSet/Offsetを既存の一括編集/履歴経路へ追加。範囲・上限下限・全体%適用前の値であることをUIとAI向け文書へ記録。Fast / Full / --playback成功。Set/正負Offset/上下限制限、非選択音と全属性/別クリップ保持、一括Undo/Redo、範囲外整数/オーバーフロー入力拒否、無変更時dirty保持、保存復元とMIDI強弱一致を検証。実UIで7音を90へ統一→Undo/Redo、元の強弱へ戻してOffset−15適用を確認。最小幅の横スクロール、再生中ロックと停止後復帰も確認。build/SonicForge-GroupVelocity.sfensembleを保存し、全体WAVを書き出した。保存済み・停止状態で表示。
