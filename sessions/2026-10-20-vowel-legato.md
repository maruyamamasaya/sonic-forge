# ジムノペディの母音接続と息継ぎ
Date: 2026-10-20

## Request
繊細なコーラス/強弱を保ち、音のつながりと息継ぎを自然な歌唱へ近づけ、前回と比較。音作りのみ。
## Investigation
前回スクリプト/reportのテンポ・旋律・強弱、原音の有声部分を確認。音ごとの立ち上がり/落ち込みを減らす方針。
## Changes
scripts/vowel_legato_study.py追加。有声中央部と120 ms重なりで16か所を接続。4小節境界/休符/同音保持の息継ぎは残す。コーラスWAVは不変、旋律の定数ゲインだけで全曲RMSを前回へ合わせる。43.25秒の新旧と冒頭比較をbuildへ出力。[詳細](../LOCAL_VOWEL_MODEL.md)。
## Validation
原音/前回hash不変、比較用前回/コーラスbyte一致、全WAV再読込/有限/非無音/非クリップ、ステム和差1e-7未満、RMS差0.001 dB以内、接続120 ms重なり、比較列全PCM一致成功。4小節境界非接続を確認。Fast/Full文書検査・git diff --check成功。native Fullは未再実行（前回の音声初期化/アイコン生成の環境エラーが未解消、今回アプリソース変更なし）。聴感はユーザー評価待ち。
## Result
build/local-vowel-model/legato-gymnopedieに比較音源。AI生成/学習/吸気音合成/アプリ組込なし。
## Remaining Issues
元声の音程変動と時間伸縮の質感が残る。自然な連続歌唱を保証せず、声のつながりはユーザーが試聴して判断する。
