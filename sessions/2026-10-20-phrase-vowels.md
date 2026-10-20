# フレーズごとの母音切替
Date: 2026-10-20

## Request
メロディのあ/うをフレーズごとに切り替え、コーラス/強弱/ビブラートを維持し前回比較。音作りのみ。
## Investigation
既存レガート/ビブラートの処理とreport、a/u長音を確認。同じ素材を使い12拍単位で切り替える。
## Changes
vowel_legato_study.pyへ任意の--phrase-vowels u,a,u,aを追加。既定は従来通り。既存ビブラート処理を再使用し、prepare_vowel_phrase_comparison.pyで前回のう単独版と比較。約43.25秒、コーラスbyte不変、全曲RMS一致。比較区間8.3〜23秒に母音切替箇所を含める。[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
既定レガートの5音源が前回とbyte一致。浅いビブラートの制御WAVも前回とbyte一致。a/u原音hash不変、12拍ごとの割当一致、前回/コーラスbyte一致、全WAV再読込/有限/非無音/非クリップ、ステム和差1e-7未満、全曲RMS差0.001 dB以内、比較区間PCM一致成功。Fast/Full文書検査とgit diff --check成功。native Fullは未再実行（既知の環境内音声初期化/アイコン生成問題が未解消、アプリソース変更なし）。聴感はユーザー確認待ち。
## Result
build/local-vowel-model/phrase-vowels-comparisonに全体/旋律/不変コーラス/前回/比較を用意。追加AI生成/モデル学習/アプリ登録なし。
## Remaining Issues
特にあの元発声の音程変動は残る。切替で自然な連続歌唱になったかは試聴で判断する。
