# 0002: 最初のmacOS再生アプリにApple標準基盤を採用
Date: 2026-10-16
Status: accepted

## Context
ユーザーは承認済みUIに基づくWAV読み込み・再生と、音源不要のデモを求めている。Mac専用。
C++ / JUCE / CMakeを提案していたが、環境にはXcodeのみがありJUCE・CMakeは未導入。

## Decision
最初のアプリをSwiftUI / AppKit / AVFoundationで実装し、Swiftコンパイラから.appを生成する。
UI、MainActorの再生状態、バックグラウンドのファイル解析・デモ合成を分離する。

## Reason
追加インストールや第三者依存なしで、実機で確認できるMac用の最初の制作画面を成立させるため。

## Alternatives
JUCE導入は独自DSP・プラグイン拡張に有力だが、初回のファイル再生には必須でない。
Web画面は承認済みMac専用アプリの方向性と異なる。

## Consequences
AVAudioPlayerは初期の再生用。MIDI楽器・サンプル精度の処理・プラグインホスト実装時にはエンジンを再評価する。
必要ならC++ DSPとの接続を設計する。将来移植や低遅延・プロ品質を現段階で保証しない。
