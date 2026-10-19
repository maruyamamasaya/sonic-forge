# M1 Maxでの音源分離実機比較
Date: 2026-10-19

## Request
このMacでPyTorch版とMLX版を動かし、音質・時間・メモリを比較して採用を決める。ユーザーがsample_musicに素材を配置。
## Investigation
M1 Max・32 GiB・macOS 26.6.2。専用Python 3.10.4環境にDemucs 4.1.0/PyTorch 2.14.1、demucs-mlx 1.6.1/MLX 0.32.4を導入。指定曲を共通WAVへ変換し、20秒と255.9867秒の全曲で各3回、全曲は新規プロセスでも各1回計測。処理はオフライン設定、音源の外部送信なし。
## Changes
再利用可能な計測スクリプト、比較用依存固定一覧、個人情報を除いた構造化実測値、SEPARATION_BENCHMARK.md、採用判断0045を追加。CURRENT/ROADMAP/構成/コード地図/検証/関連計画を更新。素材はGit除外。アプリへの統合はまだ行わない。
## Validation
両backendで4ステムの全長・レート・チャンネル・有限値を確認。曲全体の実装間SNRは約94〜107 dB。比較スクリプトの同一出力・切れたstem拒否・無音stemの未定義指標をnullにすることを確認（初回の確認用ハーネスはvenvのsymlinkをresolveして失敗し、sys.executableで修正後に成功）。Fast、文書リンク・書式、diff確認成功。Fullも成功（既存通常音声テスト・アプリビルド）。人による主観試聴と正解stem評価は未実施。
## Result
MLXを初期worker用に採用。新規プロセスの全曲処理はMLX 6.07秒/PyTorch 13.63秒、OSピークfootprintは5.30/2.65 GiB。速度とメモリの交換条件を明記。試聴用の4種類A/B WAVをbuild配下へ用意。
## Remaining Issues
分離worker・モデル準備・取消・失敗処理・試聴UI・既存楽器保存との接続。8/16 GiB機、10分曲、複数曲種、主観音質、一般配布は未評価。
