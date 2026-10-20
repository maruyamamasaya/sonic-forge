# 長い母音ジムノペディへ歌唱的な表情
Date: 2026-10-20

## Request
繊細なコーラスのまま長くし、盛り上がって下がる歌唱的な強弱を付ける。アプリ未組込。
## Investigation
既存長音/小曲スクリプトと固定版譜面を確認。モデル学習はせず、フレーズ/音内の音量と時間配置を調整する。タイ区間は素材長の制約から息継ぎ再発音に編曲。
## Changes
scripts/vowel_expressive_gymnopedie.pyで5〜20小節/43.25秒の表情版・均一版・旋律/伴奏ステム・冒頭比較を出力。あの伴奏は2声で、全曲RMSは旋律より約12 dB低い。各4小節/全体の音量の山と減衰、音内スウェル、共通テンポ変化/終盤減速。初回のタイ部分の伴奏重複を修正し、final音源を採用。[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
入力hash不変、全出力の有限/非無音/非クリップ/再読込一致、ステム和誤差1e-7未満、均一/表情の全曲RMS差0.001 dB以内、音量カーブの山/減衰成功。独立検査で伴奏イベント非重複と冒頭比較PCM一致も確認。Fast成功。Full文書検査とgit diff --check成功。標準Fullはsandbox内のAVAudioMixerNode初期化（comp != nullptr）で中断。既存AudioTestsを通常のmacOS環境で再実行したが、約2分の実行後、今回アプリソース変更なし/専用DSP検証成功のため停止し、native再検証は未完了と記録。別途build.shはiconutilのInvalid Iconsetで失敗。音源生成の技術検証とは区別し、Full成功とは扱わない。
## Result
build/local-vowel-model/expressive-gymnopedie-finalに音源とreport。AI追加生成/学習/外部送信/アプリ登録なし。聴感評価はユーザー待ち。
## Remaining Issues
発声内の元の音程変動が残る。10秒のタイは連続歌唱ではなく3拍ごとに息継ぎ再発音。音色変化や本物の息圧を再生成する調教ではない。
