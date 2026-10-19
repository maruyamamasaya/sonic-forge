# 0040: パート単位の3バンドEQ

日付: 2026-10-19

各パートの全クリップで共有する固定3バンド（200 Hz shelf / 1 kHz parametric・1 octave / 4 kHz shelf）を±12 dBで提供する。周波数/Q編集や音符単位のEQは今回の範囲外。独自DSPよりAVAudioUnitEQを使い、本番ライブとoffline WAVで同じEnsembleVoiceの経路を共有する。パンはEQ後のMixerに維持し、mono/stereoを共通48 kHz stereoで処理する。

0 dBの帯域はbypassし、旧構成v1〜v6はフラットへ移行。保存v7は3値を必須にして欠落・不正な設定を部分適用しない。SongStateへ含め一括フラットのUndo/Redoとdirtyを共有。AI編曲schemaは拡張せず既存EQを保持する。帯域効果は実レンダーWAVの周波数成分で検証する。
