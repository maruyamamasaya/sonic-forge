# 母音の切替を連続した声へ近づける
Date: 2026-10-20

## Request
a/uの切替を滑らかにし、同じ人が歌い続ける感じへ。薄いコーラス/強弱/ビブラート維持、前回比較、音作りのみ。
## Investigation
前回母音切替版と、同じ旋律/浅い揺れのu単独版、既知の残響を確認。位相と音程を1本に揃え、母音の響きを補間する。
## Changes
scripts/vowel_transition_study.py追加。u旋律の位相にaの平滑化スペクトル包絡を移し、3箇所を700 msで遷移。強弱/レガート/息継ぎと同じ残響を基にし、コーラスはbyte一致。43.25秒の曲/前回コピー/旋律/不変コーラス/比較をbuildへ出力。[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
入力hash不変、前回/コーラスbyte一致、STFT往復差1.1e-16、残響再構成差1e-7未満、ステム和差1e-7未満、RMS差0.001 dB以内、3切替の700 ms重みの単調性、比較PCM一致、再読込/有限/非無音/非クリップ成功。Fast/Full文書検査とgit diff --check成功。native Fullは既知の音声初期化/アイコン生成の環境問題が未解消かつアプリソース変更なしのため未再実行。聴感評価はユーザー待ち。
## Result
build/local-vowel-model/smooth-vowel-gymnopedieに新旧比較。モデル取得/AI再生成/学習/アプリ登録なし。
## Remaining Issues
aの波形そのものを維持する方法ではなく、uの位相へ母音包絡を移すため、aの明瞭さ/自然さは試聴で判断する。
