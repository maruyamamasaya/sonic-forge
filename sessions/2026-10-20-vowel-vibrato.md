# 母音レガートへ浅いビブラート
Date: 2026-10-20

## Request
繊細なコーラス/強弱を維持し、控えめなビブラートと声の揺れを加えて前回比較。音作りのみ。
## Investigation
レガート版のreport/旋律/不変コーラスと既知リバーブ処理を確認。乾いた旋律を逆変換で取り出して変調し、残響を戻す。
## Changes
scripts/vowel_vibrato_study.pyを追加。280 ms遅れで浅い音高変調を開始、速度/深さを緩く変化。追加最大13.19 cents、強弱揺れ最大0.19 dB。コーラスはbyte一致、尺43.25秒、新旧全曲RMS一致。音源/reportはbuildのみ。[詳細](../LOCAL_VOWEL_MODEL.md)。
## Validation
既知220 Hzの変動を独立ゼロ交差測定しRMS誤差0.0092 cents。リバーブ再構成差1.1e-16、入力hash不変、前回/コーラスbyte一致、ステム和差1e-7未満、RMS差0.001 dB以内、再読込/有限/非無音/非クリップ/比較PCM一致成功。Fast/Full文書検査とgit diff --check成功。native Fullは未再実行（既知の環境内音声初期化/アイコン生成問題は未解消、アプリソース変更なし）。聴感の自然さはユーザー確認待ち。
## Result
build/local-vowel-model/vibrato-gymnopedieに全体と冒頭比較。アプリ登録/新しいAI生成/学習なし。
## Remaining Issues
微小再生速度変調なのでフォルマントも少し動く。元声の音程変動に追加する制御で、歌唱モデルによる音色/息圧の再生成ではない。
