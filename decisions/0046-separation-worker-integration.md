# 0046: 分離workerを既存の楽器編集へ接続
Date: 2026-10-19
Status: accepted

## Context
ユーザーはMLX workerと、アプリからの曲分離・試聴・音の選択・楽器保存までの接続を依頼した。モデル・設定は[0045](0045-mlx-separation-backend.md)で採用済み。

## Decision
Pythonは専用venv、workerはアプリResourcesに同梱する。最初はMP3/WAVを入力し、ローカルMLXが元曲と4ステムを共通44.1 kHz Float32 WAVへ保存する。進捗は小さなatomic JSONのポーリング、結果はjobID付きmanifestにし、標準出力ログと分離する。候補をシートで比較試聴し、明示的な採用時に未保存楽器の保存確認を行い、選んだWAVの所有コピーを既存PlayerModelへ渡す。楽器保存形式は変更しない。

## Reason
既存の波形選択・サンプラー・音源同梱保存を再利用できる。進捗callbackのないMLXに架空の進捗を付けず、パイプ詰まりも避ける。候補と編集中の音源の寿命を分け、新しい分離や失敗で編集データを失わないようにする。

## Alternatives
調査時のstdout JSON Lines方式はライブラリの出力混入と読取処理が必要になるため初期実装では採用しない。Python同梱・Swift移植・永続的な全曲素材DBは後の段階とする。

## Consequences
利用前に外部venvと固定依存・モデルを準備する必要がある。このMacでは比較環境を再利用できる。通常の取消・終了で一時ファイルを解放するが、異常終了の残骸回収は未実装。10分/2 GiB空き容量の上限は実装上の制限で、全環境での性能保証ではない。操作と技術境界は[分離ガイド](../SEPARATION.md)。
