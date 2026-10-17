# 2026-10-17 AI編曲提案

既存楽器を使う複数パート/セクションの編曲提案、タイムラインと音符による確認、一括採用を追加。接続4方式とJSON通信境界を共有し、元構成revision・全候補検証・取消世代で保持する。採用結果は既存v5保存/ライブ/WAVへ接続。設計判断0035とAI操作の正本を追加。

Fast / Full成功。通常nativeテストは制限環境のCoreAudio生成で停止し、必要なアクセスを許可して再実行成功。編曲のDemo/模擬HTTP/CLI、拒否/取消/古い応答、採用/保存/復元/WAV再読み込みと既存回帰を確認。--playbackは実UIのWAV処理と同時実行した際に既存EnsembleClipTestsの短い発音タイミング検証が失敗し、アプリ停止状態で再実行して全件成功。実AIネットワーク接続は今回未実行。

実UIで薄いIntro/厚いサビと均一Demo、指示変更/Doneの候補破棄、未保存置換Cancel、先にSave Current→採用→メイン配置/音符/発音/自然終了を確認。1920基準と最小1100×760の操作・スクロール・採用ボタンを確認。build/SonicForge-Arrange-Source.sfensembleとSonicForge-AIArrangement.sfensembleを別保存。全体WAVを出力しSample Studioで再読み込み（13.883秒・48 kHz・Stereo・32-bit）を確認。元のNotePaste構成は保持。保存済み・停止状態のEnsembleを1920基準で表示。
