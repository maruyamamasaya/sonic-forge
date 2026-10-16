# WAV Sample Studioの初回実装
Date: 2026-10-16

## Request
承認済み画面案をベースに、WAV読み込み・再生と音源不要のデモを動かす。

## Investigation
既存は文書とVerifyのみ。Xcode・Swiftあり、JUCE・CMakeなし。Apple公式のAVAudioFileとAVAudioPlayerを確認。
今回はApple標準基盤を採用し、当初のJUCE提案からの変更理由をdecisions/0002へ記録した。

## Changes
app/にSwiftUIの中央波形・右インスペクター・下部トランスポート、再生モデル、WAV解析・デモ合成を追加。
8秒の合成ステレオWAVを初期ロード（自動再生なし）。ファイル選択、再生、一時停止、停止、シーク、音量、メーター、エラー表示を実装。
scripts/build.sh・test.sh、tests/AudioTests.swiftを追加し、Full Verifyにテストとビルドを統合。
app/AGENTSと関連文書を更新。元音源を変更せず、読み込み失敗時は現在の音源を保持する。

## Validation
Fast / Full成功。.app生成・ローカル署名成功。
通常テスト成功: デモ合成、PCM16ステレオ／Float32モノラル、波形・減衰・長さ、時刻、壊れた／存在しないファイル。
--playback成功: 読み込み、再生、一時停止、シーク、停止、エラー後の保持、交換、ゲイン設定、末尾から再生。
実UIでデモ波形、再生中の位置・メーター更新、末尾停止、Open WAVから44.1 kHzモノラルWAVの読み込み、Load Demoへの復帰を確認。
実画面の見た目を確認。44.1 kHzの表示が切り捨てられていたため小数表示に修正し再ビルド。
最小サイズでのレイアウト、複数デバイス切替、長時間再生、聴感・遅延品質は未確認。

## Result
音源なしで試せるmacOS Sample Studioを実装。build/SonicForge.appから起動できる。

## Remaining Issues
WAVは256 MB以下、モノ／ステレオRIFFに限定。楽器化、範囲編集、保存、MIDI、AI、プラグインは未実装。
独自DSP・低遅延エンジンは後段で設計。第三者依存・ネットワーク通信なし。変更は未コミット。
