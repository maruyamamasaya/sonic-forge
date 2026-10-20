# 日本語歌詞と地声/裏声風の音色
Date: 2026-10-20

## Request
ジムノペディへ短い日本語歌詞を付け、同じ声質/薄いコーラス/強弱/ビブラートを保って母音版と比較。低音地声風/高音裏声風を音域で切替。アプリ未組込。
## Investigation
既存ローカルQwen3-TTS生成/参照/演奏reportを確認。歌唱モデルではなく参照条件付きTTSからの音程/時間加工を試す。声区は生理再現ではなくDSP近似。
## Changes
local_vowel_model_study.pyに--lyric-study追加、4行を同じ参照/seedで各1件生成。全行EOS。japanese_lyric_gymnopedie.pyで近似F0/動的移調/有声重視の時間伸縮、共通演奏カーブ/揺れ/息成分/残響と合成。E4〜G4で芯/軽さ/息の音色を切替。初回reportのnumpy整数JSON化を修正しfinalへレンダー。[正本](../LOCAL_VOWEL_MODEL.md)。
## Validation
モデル生成の参照不変/接続0/外部送信なし/全行EOS、音声再読込/有限/非無音/非クリップ、原音不変、前回/コーラスbyte一致、ステム和差1e-7未満、RMS差0.001 dB以内、比較PCM一致成功。既知220 Hzのpitchmap +3半音は誤差0.213 cents。Fast/Full文書検査とgit diff --check成功。native Fullは既知の音声初期化/アイコン生成環境問題が未解消、アプリソース変更なしのため未再実行。声の音高や発音/自然さは未検証、精密調律完了とは扱わない。
## Result
build/local-vowel-model/japanese-lyric-gymnopedie-finalに43.25秒の歌詞/音域切替ありなし/前回母音/比較/旋律/不変コーラス/歌詞/report。追加モデル取得/学習/外部送信/アプリ登録なし。
## Remaining Issues
TTS由来の歌唱加工であり音素と音符は近似対応。元の声質/日本語の明瞭さ/声区の自然さはユーザー試聴で判断。切替音域は実測した声帯の換声点ではない。
