# 0048: マスターのピークリミッター

日付: 2026-10-19

## 判断
EnsembleMasterBusで全パートの合算/固定ヘッドルーム/全体音量の後へApple AUPeakLimiterを置く。入力PreGainに−ceilingDB、最終MixerにceilingDBを適用して出力上限を変換する。固定アタック12 msと指定リリース1〜60 ms、既定オフ/−1/24。ライブ/WAVを共通化し、処理後RMSを表示。保存v11、旧1〜10はオフ移行、履歴とAI採用時の保持に含める。

## 理由と代替案
Apple標準ユニットを使い独自DSP/外部依存を増やさない。全体音量より前に置くと後段の増幅を防げないため最終段へ配置する。パート個別の圧縮だけでは合算ピークを防げない。単純なサンプル切り捨ては波形を直接潰すため採用しない。初期の1 msアタックは突発音で設定上限を超えたため、12 msへ固定して実レンダー検証する。

## 影響
旧構成/既定オフは従来ミックスを保ち、明示的オンで制御する。素材/単体楽器には作用しない。ピーク制御はサンプル単位で、トゥルーピーク/ラウドネス正規化/破損音源修復は扱わない。音質・長時間負荷は別評価。根拠はSDK AudioUnitParameters.hと[AppleのPeak Limiterパラメーター](https://developer.apple.com/documentation/audiotoolbox/1389597-peak_limiter_unit_parameters)。
