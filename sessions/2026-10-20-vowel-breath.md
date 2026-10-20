# 息づかいと語尾の抜け
Date: 2026-10-20

## Request
母音連続化版へ息づかい/語尾を足し、繊細なコーラス/強弱/ビブラートを保って前回比較。歌詞は任意、アプリ未組込。
## Investigation
前回の旋律/既知の残響と4フレーズ境界を確認。母音の歌唱を保ち、短い吸気/呼気感と語尾の音量変化を加える。
## Changes
scripts/vowel_breath_study.py追加。帯域制限した小さな合成空気成分、最後340 msの有声減衰、吸気/呼気の非重複。コーラスbyte不変、全曲RMS一致。初回の重複を修正したfinal版を提供。[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
入力hash不変、前回/コーラスbyte一致、全WAV再読込/有限/非無音/非クリップ、ステム和差1e-7未満、RMS差0.001 dB以内、吸気/呼気非重複、指定外空気ゼロ、語尾ゲイン範囲と比較PCM一致成功。Fast/Full文書検査とgit diff --check成功。native Fullは既知の音声初期化/アイコン生成問題が未解消、アプリソース変更なしのため未再実行。自然さはユーザー試聴待ち。
## Result
build/local-vowel-model/breath-gymnopedie-finalに43.25秒の曲と比較/ステム/制御値。歌詞発音生成/モデル学習/アプリ登録なし。
## Remaining Issues
息成分は合成で、元話者の実際の吸気/呼気ではない。声の自然さや息の量は人が試聴して判断する。
