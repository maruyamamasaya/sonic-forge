# 0005: 単音サンプラーをAVAudioEngineで実装
Date: 2026-10-16
Status: accepted

## Context
サンプルの基準音を指定し、画面鍵盤から異なる音程で演奏したい。既存のWAV試聴・編集UIは維持する。

## Decision
サンプルをFloat32メモリへ事前に取り込み、PlayerNodeとVarispeedで単音演奏する。半音差を再生速度へ変換する。
既存のAVAudioPlayer試聴とは排他にし、楽器操作時は元ファイルへアクセスしない。
初版はC3〜C5の画面鍵盤、30秒・64 MB以内。デモを自動取り込みし、ユーザー素材は明示的に取り込む。

## Reason
再生速度の広い音程範囲を扱え、今後の音声処理を既存のファイル試聴から分離できる。

## Alternatives
AVAudioPlayerのrate変更は演奏範囲が狭い。音の長さを維持するpitch処理や多声音源は別途設計する。

## Consequences
速度と音の長さは連動。基準音は手動指定で、自動検出や音源分離はしない。
和音・ループ・ADSR・外部MIDI・楽器保存は次段階。初版の離鍵は即時停止。
