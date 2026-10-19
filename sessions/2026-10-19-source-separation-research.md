# 音源分離の技術調査と実装方針
Date: 2026-10-19

## Request
1曲を分離して使える音を1つ選び、楽器保存するための技術調査と実装方針整理。
## Investigation
Demucs作者側、demucs-mlx、python-audio-separator、Music-Source-Separation-Training、Spleeter、Swift/Metal移植、SAM Audioの一次資料を確認。既存のAudioAsset、PlayerModel.load/prepareInstrument/saveInstrument、InstrumentSample、ライブラリ登録、CLIプロセス処理を確認。
## Changes
SOURCE_SEPARATION.mdへ比較・出典・制限・worker契約・停止・モデル準備・既存接続・実機評価条件を整理。判断0044はproposed。CURRENT、ROADMAP、CODEMAPと記録一覧を更新。アプリ実装と依存導入はなし。
## Validation
Fastと新規計画文書を含むリンク・書式検査成功。内容差分を確認。Fullも成功（既存の通常音声テスト・アプリビルド、サンドボックス外）。実モデルの導入・推論・品質/速度/メモリ評価は未実施。
## Result
ローカルhtdemucsの4ステムから既存Sample Studioへ接続する案。PyTorchを比較基準にMLXを実機評価後、backendと依存を固定する。現段階では採用ライブラリ・性能は未確定。
## Remaining Issues
短い素材と1曲での実機比較、依存固定、worker、試聴UI、楽器保存までの結合。モデル・素材・実行環境の容量と条件も導入時に確認する。
