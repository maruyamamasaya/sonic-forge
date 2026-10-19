# 0045: M1 Maxでの音源分離にMLXを採用
Date: 2026-10-19
Status: accepted

## Context
ユーザーはこのMacでPyTorch版とMLX版を動かし、音質・時間・メモリを比較して採用を決めるよう依頼した。[0044](0044-source-separation-plan.md)の比較を、指定された実曲の20秒区間と約4分16秒の全体で実施した。

## Decision
M1 Max・32 GiB向け初期workerにdemucs-mlx 1.6.1 / MLX 0.32.4、htdemucs、float32 attention、batch 1、shifts 0、overlap 0.25、segment 7.8秒、compile ON、cache上限4 GiBを採用する。共通の外側正規化をworkerに含める。PyTorch版は比較基準として保持し、失敗時の無断自動切替はしない。

## Reason
全曲の新規プロセス計測でMLX 6.07秒、PyTorch 13.63秒。出力は全長・形式・有限値が一致し、stem別の信号対誤差比は約94〜107 dB。実装の差が小さいことを数値で確認できた。OSのpeak memory footprintはMLX 5.30 GiB、PyTorch 2.65 GiBで、速度とメモリの交換条件を明示して採用する。

## Alternatives
PyTorch MPSはメモリ面に優れるが今回約2.2倍遅かった。MLX batch自動調整・fp16 attention・shifts追加は未評価のため既定にしない。別モデルやネイティブSwift版へは今回移行しない。

## Consequences
この採用を8/16 GiB機や10分曲へ一般化しない。最初のコンパイル負荷、ジョブ終了時のメモリ解放を扱う必要がある。人の主観試聴と正解stemに対する分離品質は未評価。アプリ統合・取消・復旧は次の実装。実測方法、制約、重みhash、固定依存は[実機比較](../SEPARATION_BENCHMARK.md)を正本とする。
