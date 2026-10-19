# 音源分離の技術調査と実装方針

調査・実測日: 2026-10-19。両backendの実機比較を完了し、[実測結果](SEPARATION_BENCHMARK.md)と[採用判断0045](decisions/0045-mlx-separation-backend.md)に基づき、このM1 Max・32 GiBではMLXを採用。アプリ統合も実装済み。操作・現行の境界は[分離ガイド](SEPARATION.md)。
全体構想は[ROADMAP.md](ROADMAP.md)、当初の提案は[0044](decisions/0044-source-separation-plan.md)、実装の判断は[0046](decisions/0046-separation-worker-integration.md)。

## 結論

最初はローカルのDemucs系4ステム分離を使い、「曲 → ドラム／ベース／ボーカル／その他 → 試聴 → 範囲選択 → 楽器保存」をつなぐ。
モデルはhtdemucs。実機比較によりdemucs-mlx 1.6.1 / MLX 0.32.4を初期backendとして採用した。設定・依存・制約は[実機比較](SEPARATION_BENCHMARK.md)を参照。以下の候補比較と実装案は調査時の記録で、実測値と採用の最新情報は同文書を正本とする。

アプリはSwiftUI / AVFoundationのまま、推論だけを専用Python環境の別プロセスへ分ける方針。結果は検証済みWAVと小さなJSONで受け取り、現在のSample Studioへ渡す。将来の高品質モデルやSwift実装への交換はこの境界の内側で行う。

## 候補の比較

以下は各実装元の説明に基づく。異なるモデル・評価条件のベンチマーク数値を並べて品質順位にはしない。ライセンス欄はコード側の表記であり、個別の重み・依存物・入力素材の利用条件を一括で保証するものではない。

| 候補 | 対象・Macへの適合 | 評価と扱い | コード側表記・一次資料 |
| --- | --- | --- | --- |
| Demucs / HTDemucs | 標準はdrums/bass/vocals/other。作者側Mac手順はApple SiliconのMPS、CPUへの切替を案内 | 4ステムの比較基準。元Metaリポジトリはアーカイブ済み、作者側も積極的な保守ではないため版固定が必要。6ステムのpianoは公式に品質上の注意あり | MIT。[元実装](https://github.com/facebookresearch/demucs)、[作者側](https://github.com/adefossez/demucs)、[Mac手順](https://github.com/adefossez/demucs/blob/main/docs/mac.md) |
| demucs-mlx | 同じDemucs系をApple SiliconのMLXで推論。Python 3.10以上、推論時PyTorch不要 | 初期実行候補。上流との一致・速度は作者報告なので実機追試する。進捗callbackがない点をUI設計へ反映。Intel用には採用しない | MIT。[実装・要件](https://github.com/ssmall256/demucs-mlx)、[依存定義](https://github.com/ssmall256/demucs-mlx/blob/main/pyproject.toml) |
| python-audio-separator + RoFormer等 | 複数のモデルをCLI/APIで扱う。PyTorchモデルはMPS、ONNXモデルは利用可能ならCoreML provider | ボーカル品質改善や対象別分離を追加する第2候補。これは単一モデルではなく実行ラッパー。最初から全モデル・ensembleを導入すると検証範囲が広がる | MIT。[実装・Apple Silicon手順](https://github.com/nomadkaraoke/python-audio-separator) |
| Music-Source-Separation-Training | 多様なモデルの学習・推論・設定を扱う | RoFormer等の比較実験と将来の学習用候補。最初のアプリ依存として研究環境一式を取り込まない | MIT。[実装](https://github.com/ZFTurbo/Music-Source-Separation-Training) |
| Spleeter | 2/4/5ステム、5ステムはpianoを含む。TensorFlow系 | 既知の比較対象。現アプリに別ランタイムを増やすため初期優先度は低い。Macでの導入・品質は未検証 | コードMIT。[実装](https://github.com/deezer/spleeter) |
| Swift / Metal移植 | demucs-swiftはdemucs-rs経由のApple Silicon対応、SwiftPM/XCFramework構成 | Python不要の将来候補。現在は直接swiftcビルドなので組み込み方式の変更が必要。移植の数値一致とバイナリ供給を先に確認 | Apache-2.0。[実装](https://github.com/SplitFireAI/demucs-swift) |
| SAM Audio | テキスト・時間範囲などで対象音を指定。SEや特定楽器の抽出という将来像に近い | 別の研究段階。公式はPython 3.11以上・CUDA推奨、重み取得にアクセス申請が必要。Macでの動作・資源は未検証。初期の標準機能にはしない | SAM License。[公式実装・要件](https://github.com/facebookresearch/sam-audio) |

CoreML provider経由のONNX推論と、Swift/Core MLモデルの直接組み込みは別方式。どちらも全モデルがそのまま動くとは扱わない。

## 分離できる単位と最初の範囲

4ステムは「大きなまとまり」を分ける。ドラム内のキックとスネア、other内のギターとエレピ、SEやオーケストラヒットをそれぞれ独立抽出する保証はない。ボーカルの分離と、声の質感の分析も別工程。
まずは分離後のドラムやベースから、人が使える短い箇所を選ぶ。ドラム全体から1打を切り出せても、重なった打楽器の完全分離ではない。
htdemucs_6sは比較後に実験機能とし、pianoステムをエレピ専用とは表示しない。細かな対象抽出は対象別モデルまたはプロンプト分離を後で評価する。

初回の範囲案:

- 入力は現在と同じRIFF/WAVE、モノラル／ステレオ、256 MiB以下。MP3/M4A等のデコード入口は別の追加作業とする。
- 初期上限案は10分以内。出力を44.1 kHz・ステレオFloat32にそろえると10分で約202 MiB/ステムとなり、現行の256 MiB読込制限内に収まる。4本だけで約808 MiBとなるため一時領域・元音源・変換作業用の余裕も事前確認する。
- 4本を1回で分離し、1本ずつ試聴・編集。全WAVを同時にSwiftのPCMバッファへ読み込まない。
- 楽器にするのは選択範囲のみ。現在の30秒・デコード後64 MiB制限を維持し、長ければ短く選び直せるようにする。
- 分離結果の自動ノイズ除去、自動採譜、音程検出、質感分析、DB、モデル追加学習はこの一周に含めない。

10分上限は設計案で、メモリ・処理時間の実測で短くする可能性がある。モデルのチャンク処理と、曲全体の入出力バッファのメモリは別に測る。

## 推奨構成と既存処理への接続

以下のSeparation名は追加予定の責務で、現在の実装ではない。

```text
Sample Studio「曲を分離…」
 → SeparationModel（状態、ジョブID、キャンセル、候補一覧）
 → SeparationClient（Process、専用Python実行ファイル、引数配列）
 → Python worker（固定モデル、ローカル推論、WAV検証・生成）
 → 結果manifestと4本のWAV
 → 1本を試聴 →「この音を編集」
 → PlayerModel.load → 波形で範囲選択
 → prepareInstrument(useSelection: true)
 → 基準音・ADSR・ループを調整
 → saveInstrument → InstrumentDocument → InstrumentLibrary.register
```

現コードの確認点:

- `app/AudioAsset.swift`のloadはRIFF/WAVE確認と256 MiB制限を持つ。バックエンドがMP3を読めても、そのまま現UIの対応形式にはならない。
- `app/PlayerModel.swift`のloadは音源準備に成功してから置換するが、成功時は編集中の楽器状態を初期化する。「この音を編集」前に未保存楽器の保存／破棄／取消を扱う。分離開始だけで置換しない。
- `prepareInstrument`と`InstrumentSample.load`が選択区間をPCM化する。保存時は音源同梱の既存形式を使えるため、一時ステムへの外部参照を楽器に残す必要はない。
- `CodexPerformanceClient`にはProcess・取消・一時領域の先例がある。ただし分離用に責務を分け、AI演奏生成へ依存させない。
- メイン3列と下部トランスポート、Sample Studioの波形・鍵盤・設定の構成を維持する。分離の候補は専用シートで扱う。

### workerとの契約案

- 1プロセス・1ジョブ・同時実行1件。初期は常駐せず、完了・取消で推論メモリを解放する。
- stdinまたは入力JSONにprotocolVersion、jobID、アプリ管理の入力コピー、出力先、固定backend/model、設定を渡す。shell文字列を組み立てない。
- stdoutはサイズを制限したJSON Linesイベント、stderrは上限付き診断として並行排出。標準出力のライブラリログをJSONに混ぜない。
- イベントは準備中／推論中／出力検証中／完了。実際のcallbackがないbackendは不定進捗と経過時間を表示し、架空のパーセントや残り時間を作らない。
- 成功manifestは版、jobID、backend/package/model識別、重みhash、実際のdevice、設定、入力hash、各stemの相対パス・レート・チャンネル・フレーム数を持つ。
- Swift側でも期待する4種、パスがジョブ領域内であること、ファイル形式・長さ・サイズを確認。workerでは非有限PCM・破損・書込途中を拒否。無音stemは正常結果として表示する。
- stemごとの自動音量正規化で相対音量を変えない。出力時のゲイン・クリップ方針を固定し、必要な減衰は全stemへ共通適用してmanifestへ記録する。元音源との比較は同じ時刻・対応するレート変換位置で行う。
- 終了コード0だけで成功にせず、全WAV検証とmanifestのatomic公開が完了して初めて候補一覧へ反映する。遅れて届いた旧jobIDの結果は破棄する。

### 停止・失敗・保存

- 状態はidle → preparing → separating → validating → ready。failed/cancelling/cancelledを区別し、処理中もUIを応答可能に保つ。
- 取消・終了時はworkerとその子プロセスの終了を確認してから作業ファイルを削除する。通常終了要求→猶予→強制終了の実装とテストが必要。
- 分離中は既存の演奏・試聴を停止し、負荷を競合させない。試聴も既存の排他再生へ接続する。ウィンドウ閉鎖・アプリ終了で取消する。フォーカス喪失では試聴を止めるが、重いバッチ推論の取消とは分ける。
- モデル未準備、容量不足、メモリ不足、非対応入力、途中失敗を表示し、現在の素材・楽器・曲を保持する。MPS失敗時にCPUで黙って再試行せず、実際の実行先と再試行を示す。
- 元ファイルは変更しない。ジョブ専用領域へコピーし、出力を検証後に採用。選んだstemを編集中はそのファイルを保持し、別素材への交換・明示破棄・終了で解放する。保存済み楽器は以後その一時領域に依存しない。
- モデルcacheと一時ジョブを分ける。異常終了時の残骸は次回起動時にアプリ所有の非実行ジョブだけ清掃する。全曲の結果の永続管理は後の素材蓄積段階で設計する。
- 原曲・stem・選択開始終了・モデルと設定の対応をジョブmanifestに持たせる。永続的な出所情報を楽器形式へ追加するかは、既存互換性を確認した別判断にする。

## 依存導入・配布

まず開発用の専用venvとworkerを使う。Python本体、backendとその推移依存、モデルのID・取得元・hashを実機検証後に固定する。OSのPythonへ直接追加せず、モデル重み・音源・venvはGitへ含めない。
モデルを準備する通信と、音源を処理する推論を分け、準備後の推論はネットワークなしで成立させる。音源の外部送信は初期設計に含めない。
ライブラリの自動downloadや変換fallbackは、アプリ側の明示的な準備処理に閉じ込める。重み破損時は再準備へ戻し、別モデルへ黙って切り替えない。

一般配布向けのPython同梱・署名・公証、またはSwift/MLX/Core MLへの移行は、この段階では未確定。直接swiftcで作る現在のアプリにSwiftPM依存をすぐ導入するより、まず別プロセスで品質と制作体験を検証するのが今回の設計判断。

## 実装順と採用条件

1. **小さな実機比較（完了）**：PyTorch Demucs htdemucsとdemucs-mlx htdemucsを、同じ入力・同じshift/overlap/seed条件で比較。短い素材→1曲の順。両方が動く版を固定する。
2. **workerを実装（完了）**：採用済みMLXの固定設定を使い、JSON契約、WAV検証、取消、エラー、モデル準備を実装。
3. **分離シートを追加（完了）**：4ステムの一覧、元音源との同じ時刻の比較試聴、処理状況と取消、編集への受け渡し。
4. **既存の楽器化へ接続（完了）**：範囲選択→楽器化→保存→ライブラリ読込→再起動後の発音まで確認。

比較で記録するもの:

| 観点 | 確認内容・通過条件 |
| --- | --- |
| 実行条件 | Macのチップ・RAM・OS、Python/backend/依存版、重みhash、実deviceを記録。実測したM1 Max・32 GiBの詳細は実機比較記録へ |
| 時間・資源 | モデル取得・初回読込・推論・WAV保存を別計測。短い素材と3〜5分曲で壁時計時間、ピークメモリ、ディスク量を測る。Mac未実測の速度は約束しない |
| 出力整合 | 4本のレート・チャンネル・フレーム数・時間位置・有限PCM・先頭末尾を確認。無音入力・モノラル・別レートも扱う |
| 移植品質 | 同一設定の基準出力との誤差・stem別SNRと試聴を記録。モデル自体の分離品質とは分けて判断 |
| 素材としての品質 | 漏れ、金属的な揺れ、アタック欠落、低音、残響を代表区間で比較。最低1つの短い素材を選んで保存し、鍵盤で使えることを確認 |
| 運用 | モデル準備後はオフライン推論、途中取消、破損重み、容量不足、worker異常終了が元データを壊さない |

MLXに問題があれば、動作確認できたPyTorch MPS/CPUを初期backendとする。両者で実用条件を満たさなければ、python-audio-separatorの固定モデルを追加比較する。実測前に高速・高品質・省メモリを採用理由として確定しない。

## 検証の分担

これは今後追加する検証案であり、まだテストは実装していない。現在の実行手順は[TESTING.md](TESTING.md)。

- 通常テストはモデル不要のfixture workerで状態遷移・引数・JSON制限・旧ジョブ拒否・取消・壊れたmanifest・パス逸脱・途中ファイル・元状態保持を確認する。
- 実モデルテストは明示実行とし、必要な重み・固定fixtureの有無を表示する。未準備を成功としない。自動テストで任意の音楽ファイルをdownloadしない。
- 試聴品質は人が確認。実モデルで成功したことと、全素材から使える音が得られることを区別する。
- UI追加時は最小サイズ、日本語説明、識別子、停止入口を確認し、AI_OPERATIONS・OPERATIONS・TESTING・CODEMAPを更新する。

## 調査の限界

調査後、専用環境への導入・重み取得・指定実曲での両backendの推論と数値比較を実施し、比較用依存を固定した。結果は[実機比較](SEPARATION_BENCHMARK.md)。その後アプリ統合、fixtureによる取消・契約異常系、実曲からの楽器保存復元も確認した。詳細は[分離ガイド](SEPARATION.md)。人の主観音質評価、実機メモリ不足や電源断、一般配布は未検証。リンク先は変化するため導入・更新時には固定版と実測を確認する。
