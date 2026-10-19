# 音源分離の実機比較と採用結果

実施日: 2026-10-19。調査方針は[SOURCE_SEPARATION.md](SOURCE_SEPARATION.md)。

## 採用判断

このMacの初期workerには **demucs-mlx 1.6.1 / MLX 0.32.4、htdemucs、float32、batch 1** を採用する。
PyTorch版は比較基準と、今後メモリを抑える選択肢として残す。自動的なbackend切替は行わない。

実曲全体でMLXは約2.2倍速く、PyTorchとの出力の数値差は非常に小さかった。一方、OS計測のピークメモリはMLXが約2倍。32 GiBのこのMacでは正常完了したが、小メモリMacや他の重いアプリとの同時利用へ一般化しない。
これは推論バックエンドの採用であり、当時はアプリ統合前の採用判断。その後の実装と制作手順は[分離ガイド](SEPARATION.md)を参照。

## 環境と条件

- Apple M1 Max、32 GiB RAM、macOS 26.6.2、arm64、Python 3.10.4。
- 専用venvにDemucs 4.1.0 / PyTorch 2.14.1とdemucs-mlx 1.6.1 / MLX 0.32.4を導入。全依存は[比較環境の固定一覧](benchmarks/separation/requirements-macos-arm64-py310.lock.txt)。この一覧は両方を含む比較用であり、MLXだけを使う本番workerの最小依存ではない。
- ユーザー指定の1曲。元のMP3をFFmpegで共通の44.1 kHz・ステレオFloat32 WAVへ変換し、メタデータを除去。全長255.9867秒と、45秒地点からの20秒を使用。音源はローカル処理のみ、Gitへ含めない。
- 共通モデルhtdemucs、segment 7.8秒、overlap 0.25、shifts 0、split ON。MLXはattention fp32、batch 1、compile ON、cache上限4 GiB。shifts 0はランダムな時間シフトをなくす比較・初期実装用設定で、shifts 1以上の品質・負荷は今回未評価。
- 両方に同じNumPy外側正規化（チャンネル平均のmean/std、ddof=1）を適用。PyTorch APIの外側正規化と同等の処理を、MLXにも明示的に入れた。推論の入出力転送を時間に含む。
- モデル取得後の計測はオフライン設定。GPU処理は順番に実行。初回を含む3回の推論と、新規プロセスでの全曲1回を追加確認した。ユーザーの他アプリの負荷までは制御していない。

## 処理時間

| 計測 | PyTorch MPS | MLX Metal |
| --- | ---: | ---: |
| 20秒区間・最初の推論 | 5.573秒 | 8.844秒 |
| 20秒区間・同プロセス準備後2回の中央値 | 0.989秒 | 0.443秒 |
| 全曲・最初の推論 | 11.532秒 | 5.404秒 |
| 全曲・同プロセス準備後2回の中央値 | 11.030秒 | 4.959秒 |
| 新規プロセスで全曲1回・推論 | 11.352秒 | 5.088秒 |
| 同上・OS計測のプロセス全体 | 13.63秒 | 6.07秒 |
| 同上・モデルロード（backend importを含む） | 1.389秒 | 0.128秒 |

20秒の最初の計測ではMLXのコンパイル準備が大きかった。全曲の「最初」と新規プロセスの計測も、先の計測で作られたOS/Metalキャッシュは残っているため、Mac上で完全に未使用の状態からの起動時間とは呼ばない。
プロセス全体は、WAV入力読込、モデル準備、推論、検証、4本のFloat32 WAV保存を含む。MP3から共通WAVへの事前変換と、モデルのdownloadは含まない。アプリ組み込み後の総処理時間は別途測る。

## メモリ

| 新規プロセス・全曲1回 | PyTorch MPS | MLX Metal |
| --- | ---: | ---: |
| OS peak memory footprint | 2.65 GiB | 5.30 GiB |
| OS maximum resident set size | 1.65 GiB | 1.20 GiB |
| OSが当該プロセスに報告したswaps | 0 | 0 |

RSSだけを見るとMLXが小さく見えるが、GPU資源を含む負担をそれだけで判断しない。主比較は同じ`/usr/bin/time -l`のpeak memory footprint。
3回連続のMLXでは同指標が5.88 GiBまで増えた。1ジョブ1プロセスで終了時に解放する設計とする。
別に50 ms間隔でRSSと各フレームワークのMetal使用量を記録したが、PyTorch driver memoryとMLX active+cacheは同じ定義ではない。RSSへ単純加算せず、補足指標としてのみ使う。MLXのpeak active APIも記録した。
MLXのcache上限4 GiBは、稼働中のテンソルや全プロセスのメモリ上限ではない。この結果は10分上限や長時間の連続処理のメモリ保証ではない。

## 出力・音質の比較

両者とも4本、44.1 kHz・2ch・全曲11,289,012フレームで一致し、全サンプルは有限値。音量の個別正規化はしていない。

| 全曲のステム | PyTorchに対する信号対誤差比 | 最大絶対差（Float振幅） |
| --- | ---: | ---: |
| ドラム | 104.66 dB | 0.0000292 |
| ベース | 107.20 dB | 0.00000515 |
| その他 | 95.67 dB | 0.0000256 |
| ボーカル | 94.29 dB | 0.0000217 |

これは「両実装の一致度」であり、正解ステムに対する分離精度や音質スコアではない。正解ステムがないため、漏れやアタック欠落の絶対的な良否は数値から確定できない。今回の結果は、実装をMLXへ移すことによる大きな出力変化が見つからなかった根拠として扱う。

エージェントによる聴覚的な試聴評価は未実施。人の確認用に`build/separation-bench/listen/`へ4本のA/B WAVを生成した。各ファイルは同じ区間の「PyTorch 8秒 → 無音0.5秒 → MLX 8秒」。各ペアに共通ゲインを適用し、片側だけ音量を上げていない。元曲の分離素材を新しい作品へ採用する判断は、この試聴と切り出し操作で別途行う。

## 再現と保存物

- [計測スクリプト](scripts/separation_benchmark.py)：backendごとに別プロセスでrun、結果のcompareを実行。
- [構造化された実測値](benchmarks/separation/2026-10-19-m1-max.json)：入力ハッシュ、設定、各回の時間、メモリ、比較値、重みハッシュ。曲名・元パス・生の実行ログは含めない。
- 元素材は`sample_music/`、venv・入力WAV・モデル・出力WAV・診断は`build/separation-bench/`。いずれもGit対象外。
- PyTorchモデルは`adefossez/HTDemucs`の`955717e8.safetensors`、MLX重みは`ssmall256/demucs-mlx`。両方のSHA-256を実測値JSONへ記録。MLXの変換元signatureも955717e8。
- Demucs 4.1.0は標準Hugging Face cacheを使用するため、TORCH_HOMEだけでは重み保存先を変更しない。今回もその標準cacheから取得。専用worker準備時はHF_HUB_CACHE等も明示的に設定する。

専用環境を再作成する場合:

```sh
python3 -m venv build/separation-bench/venv
build/separation-bench/venv/bin/python -m pip install -r benchmarks/separation/requirements-macos-arm64-py310.lock.txt
```

モデルを事前準備した後、共通WAVを使って以下を順番に実行する。GPU利用とモデル準備には実行環境の許可が必要になる場合がある。

```sh
HF_HUB_OFFLINE=1 DEMUCS_MLX_NO_DOWNLOAD=1 DEMUCS_MLX_CACHE_DIR="$PWD/build/separation-bench/cache/mlx" /usr/bin/time -l build/separation-bench/venv/bin/python scripts/separation_benchmark.py run --backend torch --input build/separation-bench/input/full.wav --output build/separation-bench/results/recheck-torch --repeats 3
HF_HUB_OFFLINE=1 DEMUCS_MLX_NO_DOWNLOAD=1 DEMUCS_MLX_CACHE_DIR="$PWD/build/separation-bench/cache/mlx" /usr/bin/time -l build/separation-bench/venv/bin/python scripts/separation_benchmark.py run --backend mlx --input build/separation-bench/input/full.wav --output build/separation-bench/results/recheck-mlx --repeats 3
build/separation-bench/venv/bin/python scripts/separation_benchmark.py compare --torch build/separation-bench/results/recheck-torch --mlx build/separation-bench/results/recheck-mlx --output build/separation-bench/results/recheck-comparison.json
```

## 次の実装

この固定設定で専用workerとモデル準備を実装し、取消・失敗時の状態保持、WAV検証、分離試聴シート、Sample Studioへの受け渡しへ進む。workerに共通正規化を含める。MLXライブラリの生APIをそのまま差し替えただけで同じ出力になるとは扱わない。
8/16 GiB機、10分曲、複数曲種、shiftsあり、低メモリ設定、クラッシュ・取消、一般配布は未評価。
