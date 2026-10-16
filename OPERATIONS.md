# 開発・運用

## Local Development
macOS 14以上とXcode（または対応するCommand Line Tools）が必要。インターネット・追加パッケージは不要。
リポジトリルートで実行する。

```sh
sh scripts/build.sh
open build/SonicForge.app
```

起動時にデモが読み込まれる。自動再生はしない。PlayまたはSpaceで再生する。
Open WAV…（⌘O）で自分の音源を開き、Load Demoでいつでもデモに戻れる。
波形・概要のクリック／ドラッグ、または位置スライダーでシーク。Stopは先頭へ戻り、Pauseは位置を保持する。
音量は初期値−12 dB。出力先はmacOSのサウンド設定に従う。

## Supported Files
RIFF/WAVEのモノラル／ステレオ、256 MB以下。PCM16とFloat32は自動検証済み。
他のデコード可能なWAV形式は実ファイルで確認が必要。RF64・圧縮WAV・マルチチャンネルは対象外。
読み込み失敗やキャンセル時は現在の音源を保持する。

## Environment / Database / External Services
必須環境変数・DB・外部サービスなし。元ファイルをアップロード／変更しない。
デモはOSの一時領域で合成し、通常終了時に削除。異常終了時の残存ファイルはOSの一時領域管理に任せる。

## Build / Deploy
.appはbuild/配下（Git除外）。ローカル開発用署名のみで、公開配布用の署名・公証は行わない。
標準検証は [TESTING.md](TESTING.md)。開発ルールは [AGENTS.md](AGENTS.md)。

## Troubleshooting
- 音が出ない: Play状態、Master Gain、macOSの出力先・音量を確認する。
- 開けないWAV: サイズ・チャンネル・形式を確認。エラーを閉じると元音源に戻れる。
- ビルドできない: xcode-select -pでXcode環境を確認。build生成物は再ビルド可能。
- デモだけ試す: 音源を用意せずアプリを起動し、Playを押す。
